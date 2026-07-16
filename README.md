# tailscale-proxy

基于官方 `tailscale/tailscale` 镜像的 Tailscale 出口节点（exit node）容器，附带一个极简的运行时长状态页。

- **出口节点**：其他 Tailscale 节点的互联网流量可走本容器出口。
- **状态页**：Web 服务仅展示当前服务运行时长（每秒自动刷新）。
- **开箱即用**：用户只需提供 `TS_AUTHKEY`、`TS_HOSTNAME` 与 R2 状态存储变量，其余 exit node 配置（userspace 模式、`--advertise-exit-node` 等）全部内置到镜像 entrypoint。
- **Render Free 友好**：使用 Cloudflare R2 持久化 `/var/lib/tailscale`，不依赖 Render Persistent Disk，重启后节点名保持稳定。

## 一键部署到 Render

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/jinhan1414/tailscale-proxy)

点击上方按钮，Render 会读取本仓库根目录的 [`render.yaml`](./render.yaml) 创建服务。

部署前先准备三类配置：

1. 在 Tailscale 管理后台生成 **Reusable + Pre-approved + 非 Ephemeral** 的 Auth Key：https://login.tailscale.com/admin/settings/keys
2. 在 Cloudflare R2 创建私有 bucket，例如 `chatgptexcel2api-state`。
3. 在 Cloudflare R2 创建具备对象读写权限的 API Token，记录 `Account ID`、`Access Key ID`、`Secret Access Key`。

不要使用 ephemeral auth key。R2 持久化的目标是复用同一个 Tailscale 设备身份；ephemeral 节点离线后可能被控制台自动清理，和稳定 hostname 的目标冲突。

部署后在 Tailscale 管理后台**批准该节点为 exit node**（`--advertise-exit-node` 仅通告，需后台批准才生效）：
https://login.tailscale.com/admin/machines

首次启动时，如果 R2 中还没有 state 包，日志会出现：

```text
No existing R2 state archive found; bootstrapping a new Tailscale state
Backing up Tailscale state to R2: r2:chatgptexcel2api-state/tailscale/render-proxy/state.tar.gz
```

第二次及以后重启时，日志应出现：

```text
Tailscale state restored from R2
```

此时 Tailscale 设备名应继续保持 `render-proxy`，不会变成 `render-proxy-1`。

## 环境变量

| 变量 | 是否必填 | 说明 |
|---|---|---|
| `TS_AUTHKEY` | 是 | Tailscale Auth Key（可重用 + 预批准 + 非 ephemeral），在 Render 中设为 secret |
| `TS_HOSTNAME` | 是 | 节点主机名，决定 MagicDNS 名称 `<TS_HOSTNAME>.<tailnet>.ts.net` |
| `R2_STATE_ENABLED` | 是 | Render Free 使用 `true`，本地无 R2 测试可用 `false` |
| `R2_ACCOUNT_ID` | 是 | Cloudflare Account ID，在 Render 中设为 secret |
| `R2_ACCESS_KEY_ID` | 是 | R2 API Token 的 Access Key ID，在 Render 中设为 secret |
| `R2_SECRET_ACCESS_KEY` | 是 | R2 API Token 的 Secret Access Key，在 Render 中设为 secret |
| `R2_BUCKET` | 是 | R2 bucket 名称，例如 `chatgptexcel2api-state` |
| `R2_OBJECT_KEY` | 否 | state 对象路径，默认 `tailscale/render-proxy/state.tar.gz` |
| `R2_STATE_BACKUP_INTERVAL_SECONDS` | 否 | 周期备份间隔，默认 `300` 秒 |

其余配置由镜像 entrypoint 内置：

| 变量 | 值 | 作用 |
|---|---|---|
| `TS_USERSPACE` | `true` | 用户态网络模式（Render 无特权环境必需） |
| `TS_STATE_DIR` | `/var/lib/tailscale` | Tailscale state 目录，会被打包同步到 R2 |
| `TS_EXTRA_ARGS` | `--advertise-exit-node` | 通告本节点为 exit node |
| `TS_ACCEPT_DNS` | `false` | 不接受上游 DNS |

## Cloudflare R2 配置

在 Cloudflare 中完成以下操作：

```text
1. 进入 R2，创建 bucket：chatgptexcel2api-state
2. 创建 R2 API Token，权限至少包含该 bucket 的对象读取和对象写入
3. 记录 Account ID、Access Key ID、Secret Access Key
4. bucket 保持私有，不开启 public access
```

Render 环境变量填写示例：

```text
R2_STATE_ENABLED=true
R2_ACCOUNT_ID=<cloudflare-account-id>
R2_ACCESS_KEY_ID=<r2-access-key-id>
R2_SECRET_ACCESS_KEY=<r2-secret-access-key>
R2_BUCKET=chatgptexcel2api-state
R2_OBJECT_KEY=tailscale/render-proxy/state.tar.gz
```

`R2_OBJECT_KEY` 建议包含 hostname。后续如果部署多个 proxy，可以用不同路径隔离：

```text
tailscale/render-proxy/state.tar.gz
tailscale/render-proxy-us/state.tar.gz
tailscale/render-proxy-gb/state.tar.gz
```

## Docker 镜像

镜像由 GitHub Actions 自动构建并推送到 GHCR（支持 `linux/amd64` 与 `linux/arm64`）：

```bash
docker pull ghcr.io/jinhan1414/tailscale-proxy:latest
```

可用标签：
- `latest` — main 分支最新
- `vX.Y.Z` — 对应版本 tag
- `sha-<short>` — 某次提交

## 本地运行

```bash
# 1. 准备环境变量
cp .env.example .env
# 编辑 .env 填入 TS_AUTHKEY、TS_HOSTNAME 和 R2 变量
# 本地不测 R2 时，可保留 R2_STATE_ENABLED=false

# 2. 构建并运行
docker compose up -d

# 3. 查看状态页
# 浏览器打开 http://localhost:8080
```

## 文件结构

```
.
├── Dockerfile               # 多阶段构建：Go 编译 + 官方 tailscale 镜像
├── entrypoint.sh            # 内置 exit node 配置 + 进程监督
├── docker-compose.yml       # 本地测试
├── render.yaml              # Render Blueprint
├── .github/workflows/
│   └── docker.yml           # GitHub Actions：构建并推送镜像到 GHCR
├── go.mod
├── main.go                  # 运行时长 Web 服务
└── web/
    └── index.html           # 状态页（go:embed 内嵌）
```

## 状态页接口

- `GET /` — 运行时长页（HTML，每秒自动刷新）
- `GET /api/uptime` — 返回 JSON：`{"uptime_seconds": N, "started_at": "RFC3339", "formatted": "X天 X小时 X分钟 X秒"}`

## 验证 exit node

部署并在 Tailscale 后台批准 exit node 后，从另一台 Tailscale 设备启用 exit node：

```bash
tailscale up --exit-node=<TS_HOSTNAME>
curl https://ifconfig.me   # 出口 IP 应为本节点
```

## 验证 R2 持久化

在 Render 中手动重启服务，然后检查日志：

```text
Tailscale state restored from R2
```

再到 Tailscale 管理后台检查设备列表。正确结果是仍然只有稳定的 `render-proxy` 节点；如果出现 `render-proxy-1`，通常是以下原因之一：

```text
1. R2_STATE_ENABLED 没有设为 true
2. R2 凭证或 bucket 配置错误，state 没有成功上传
3. 使用了 ephemeral auth key，节点离线后被 Tailscale 清理
4. R2_OBJECT_KEY 改变，导致新容器没有读到旧 state
```
