#!/bin/sh
set -u

# Built-in exit node config defaults — externally provided values take precedence.
export TS_USERSPACE="${TS_USERSPACE:-true}"
export TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
export TS_EXTRA_ARGS="${TS_EXTRA_ARGS:---advertise-exit-node}"
export TS_ACCEPT_DNS="${TS_ACCEPT_DNS:-false}"

R2_STATE_ENABLED="${R2_STATE_ENABLED:-false}"
R2_STATE_ARCHIVE="${R2_STATE_ARCHIVE:-/tmp/tailscale-state.tar.gz}"
R2_STATE_BACKUP_INTERVAL_SECONDS="${R2_STATE_BACKUP_INTERVAL_SECONDS:-300}"
R2_STATE_READY_TIMEOUT_SECONDS="${R2_STATE_READY_TIMEOUT_SECONDS:-120}"
R2_OBJECT_KEY="${R2_OBJECT_KEY:-tailscale/render-proxy/state.tar.gz}"
R2_ENDPOINT="${R2_ENDPOINT:-}"

mkdir -p "$TS_STATE_DIR" /var/run/tailscale

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "[entrypoint] ERROR: $name is required" >&2
    exit 1
  fi
}

r2_enabled() {
  is_true "$R2_STATE_ENABLED"
}

configure_rclone() {
  require_env R2_ACCOUNT_ID
  require_env R2_ACCESS_KEY_ID
  require_env R2_SECRET_ACCESS_KEY
  require_env R2_BUCKET

  if ! command -v rclone >/dev/null 2>&1; then
    echo "[entrypoint] ERROR: rclone is not installed in the image" >&2
    exit 1
  fi

  if [ -z "$R2_ENDPOINT" ]; then
    R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
  fi

  export RCLONE_CONFIG_R2_TYPE="s3"
  export RCLONE_CONFIG_R2_PROVIDER="Cloudflare"
  export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
  export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
  export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"
  export RCLONE_CONFIG_R2_NO_CHECK_BUCKET="true"
}

r2_remote_path() {
  printf 'r2:%s/%s' "$R2_BUCKET" "$R2_OBJECT_KEY"
}

restore_tailscale_state() {
  r2_enabled || return 0
  configure_rclone

  echo "[entrypoint] Restoring Tailscale state from R2: $(r2_remote_path)"
  if rclone copyto "$(r2_remote_path)" "$R2_STATE_ARCHIVE" 2>/tmp/r2-restore-error.log; then
    if ! tar -xzf "$R2_STATE_ARCHIVE" -C "$TS_STATE_DIR"; then
      echo "[entrypoint] ERROR: restored R2 state archive is invalid" >&2
      exit 1
    fi
    echo "[entrypoint] Tailscale state restored from R2"
    return 0
  fi

  if grep -Eiq 'not found|nosuchkey|404|could not find|couldn.t find|object.*not' /tmp/r2-restore-error.log; then
    echo "[entrypoint] No existing R2 state archive found; bootstrapping a new Tailscale state"
    return 0
  fi

  echo "[entrypoint] ERROR: failed to restore Tailscale state from R2" >&2
  cat /tmp/r2-restore-error.log >&2
  exit 1
}

backup_tailscale_state() {
  r2_enabled || return 0
  configure_rclone

  echo "[entrypoint] Backing up Tailscale state to R2: $(r2_remote_path)"
  tar -czf "$R2_STATE_ARCHIVE" -C "$TS_STATE_DIR" . || return 1
  rclone copyto "$R2_STATE_ARCHIVE" "$(r2_remote_path)"
}

wait_for_tailscale_ready() {
  elapsed=0
  while [ "$elapsed" -lt "$R2_STATE_READY_TIMEOUT_SECONDS" ]; do
    if tailscale status >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "[entrypoint] ERROR: Tailscale did not become ready before state backup timeout" >&2
  return 1
}

state_backup_loop() {
  r2_enabled || return 0
  wait_for_tailscale_ready || return 1
  backup_tailscale_state || return 1

  while true; do
    sleep "$R2_STATE_BACKUP_INTERVAL_SECONDS"
    backup_tailscale_state || return 1
  done
}

# Validate required user-provided env vars.
if [ -z "$TS_AUTHKEY" ]; then
  echo "[entrypoint] ERROR: TS_AUTHKEY is not set" >&2
  exit 1
fi
if [ -z "$TS_HOSTNAME" ]; then
  echo "[entrypoint] ERROR: TS_HOSTNAME is not set" >&2
  exit 1
fi

restore_tailscale_state

echo "[entrypoint] Starting containerboot (exit node, userspace)..."
/usr/local/bin/containerboot &
CB_PID=$!

echo "[entrypoint] Starting status-server..."
/usr/local/bin/status-server &
WEB_PID=$!

STATE_PID=""
if r2_enabled; then
  echo "[entrypoint] Starting R2 state backup loop..."
  state_backup_loop &
  STATE_PID=$!
fi

cleanup() {
  echo "[entrypoint] Shutting down..."
  if r2_enabled; then
    backup_tailscale_state || echo "[entrypoint] ERROR: final R2 state backup failed" >&2
  fi
  if [ -n "$STATE_PID" ]; then
    kill -TERM "$STATE_PID" 2>/dev/null
  fi
  kill -TERM "$CB_PID" "$WEB_PID" 2>/dev/null
}
trap cleanup TERM INT

# Wait until either child process exits, then tear everything down
# so Render restarts the container.
while kill -0 "$CB_PID" 2>/dev/null && kill -0 "$WEB_PID" 2>/dev/null; do
  if [ -n "$STATE_PID" ] && ! kill -0 "$STATE_PID" 2>/dev/null; then
    echo "[entrypoint] R2 state backup loop exited; shutting down." >&2
    cleanup
    sleep 2
    exit 1
  fi
  sleep 1
done

echo "[entrypoint] A child process exited; shutting down."
cleanup
sleep 2
exit 1
