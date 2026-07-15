#!/bin/sh

# Built-in exit node config defaults — externally provided values take precedence.
export TS_USERSPACE="${TS_USERSPACE:-true}"
export TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
export TS_EXTRA_ARGS="${TS_EXTRA_ARGS:---advertise-exit-node}"
export TS_ACCEPT_DNS="${TS_ACCEPT_DNS:-false}"

mkdir -p "$TS_STATE_DIR" /var/run/tailscale

# Validate required user-provided env vars.
if [ -z "$TS_AUTHKEY" ]; then
  echo "[entrypoint] ERROR: TS_AUTHKEY is not set" >&2
  exit 1
fi
if [ -z "$TS_HOSTNAME" ]; then
  echo "[entrypoint] ERROR: TS_HOSTNAME is not set" >&2
  exit 1
fi

echo "[entrypoint] Starting containerboot (exit node, userspace)..."
/usr/local/bin/containerboot &
CB_PID=$!

echo "[entrypoint] Starting status-server..."
/usr/local/bin/status-server &
WEB_PID=$!

cleanup() {
  echo "[entrypoint] Shutting down..."
  kill -TERM "$CB_PID" "$WEB_PID" 2>/dev/null
}
trap cleanup TERM INT

# Wait until either child process exits, then tear everything down
# so Render restarts the container.
while kill -0 "$CB_PID" 2>/dev/null && kill -0 "$WEB_PID" 2>/dev/null; do
  sleep 1
done

echo "[entrypoint] A child process exited; shutting down."
cleanup
sleep 2
exit 1
