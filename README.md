# tailscale-proxy

基于官方 `tailscale/tailscale` 镜像的 Tailscale 出口节点（exit node）容器，附带一个极简的运行时长状态页。

- **出口节点**：其他 Tailscale 节点的互联网流量可走本容器出口。
- **状态页**：Web 服务仅展示当前服务运行时长（每秒自动刷新）。
- **开箱即用**：用户只需提供 `TS_AUTHKEY` 与 `TS_HOSTNAME` 两个环境变量，其余 exit node 配置（userspace 模式、`--advertise-exit-node` 等）全部内置到镜像 entrypoint。
- **Render 友好**：无持久化磁盘依赖，使用 ephemeral auth key + 用户态网络。

## 一键部署到 Render

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/jinhan1414/tailscale-proxy)

点击上方按钮，Render 会读取本仓库根目录的 [`render.yaml`](./render.yaml) 创建服务。部署前请在 Tailscale 管理后台生成**可重用 + ephemeral** 的 Auth Key：https://login.tailscale.com/admin/settings/keys

部署后在 Tailscale 管理后台**批准该节点为 exit node**（`--advertise-exit-node` 仅通告，需后台批准才生效）：
https://login.tailscale.com/admin/machines

## 环境变量

| 变量 | 是否必填 | 说明 |
|---|---|---|
| `TS_AUTHKEY` | 是 | Tailscale Auth Key（建议可重用 + ephemeral），在 Render 中设为 secret |
| `TS_HOSTNAME` | 是 | 节点主机名，决定 MagicDNS 名称 `<TS_HOSTNAME>.<tailnet>.ts.net` |

其余配置由镜像 entrypoint 内置：

| 变量 | 值 | 作用 |
|---|---|---|
| `TS_USERSPACE` | `true` | 用户态网络模式（Render 无特权环境必需） |
| `TS_STATE_DIR` | `/tmp/tailscale` | 容器内临时状态目录 |
| `TS_EXTRA_ARGS` | `--advertise-exit-node` | 通告本节点为 exit node |
| `TS_ACCEPT_DNS` | `false` | 不接受上游 DNS |

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
# 编辑 .env 填入 TS_AUTHKEY 和 TS_HOSTNAME

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
