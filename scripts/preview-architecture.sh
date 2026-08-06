#!/usr/bin/env bash
#
# preview-architecture.sh — 起本地预览服务，只输出可点网址（不把 html 路径当主交付）
#
# Usage:
#   ./scripts/preview-architecture.sh
#   ./scripts/preview-architecture.sh /path/to/mac-disk-architecture.html
#
# 成功时 stdout 最后一行是纯 URL，便于 Agent 直接贴给用户。
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HTML="${1:-}"
PORT="${APFS_SPA_PREVIEW_PORT:-8766}"
CACHE_DIR="${APFS_SPA_HOME:-$HOME}/.cache/apfs-spa"
SERVE_DIR="$CACHE_DIR/preview"
PID_FILE="$CACHE_DIR/preview.pid"
LOG_FILE="${TMPDIR:-/tmp}/apfs-spa-preview.log"

if [ -z "$HTML" ]; then
  for c in \
    "$CACHE_DIR/latest-architecture.html" \
    "$ROOT/docs/latest-architecture.html" \
    "$ROOT/docs/mac-disk-architecture.html" \
    "$ROOT/canvases/mac-disk-architecture.html"
  do
    if [ -f "$c" ]; then HTML="$c"; break; fi
  done
fi
[ -n "${HTML:-}" ] && [ -f "$HTML" ] || { echo "need existing html path" >&2; exit 1; }
HTML="$(cd "$(dirname "$HTML")" && pwd)/$(basename "$HTML")"

mkdir -p "$SERVE_DIR" "$CACHE_DIR" 2>/dev/null || {
  # Agent sandbox may block ~/.cache — fall back next to the html
  SERVE_DIR="$(dirname "$HTML")/.apfs-spa-preview"
  PID_FILE="$SERVE_DIR/preview.pid"
  mkdir -p "$SERVE_DIR"
}

# Always publish as a stable name so the URL never changes
cp -f "$HTML" "$SERVE_DIR/index.html"
cp -f "$HTML" "$CACHE_DIR/latest-architecture.html" 2>/dev/null || true
cp -f "$HTML" "$(dirname "$HTML")/latest-architecture.html" 2>/dev/null || true

URL="http://127.0.0.1:${PORT}/"

server_up() {
  curl -sf -o /dev/null --max-time 1 "$URL" 2>/dev/null
}

start_server() {
  # stop stale listener on this port only
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | xargs kill 2>/dev/null || true
  fi
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  sleep 0.15
  (
    cd "$SERVE_DIR"
    nohup python3 -m http.server "$PORT" --bind 127.0.0.1 >"$LOG_FILE" 2>&1 &
    echo $! >"$PID_FILE"
  )
}

if ! server_up; then
  start_server
else
  # Even if port is up, restart so we never leave a stale process serving old files
  start_server
fi
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if server_up; then break; fi
  sleep 0.2
done

if ! server_up; then
  echo "preview server failed; log: $LOG_FILE" >&2
  exit 1
fi

# Best-effort: open system browser (Agent 环境可能失败，不要紧——URL 仍有效)
if [ "$(uname -s)" = Darwin ]; then
  /usr/bin/open "$URL" 2>/dev/null || true
fi

echo "preview_dir: $SERVE_DIR" >&2
echo "pid: $(cat "$PID_FILE" 2>/dev/null || echo '?')" >&2
# Last line = the deliverable for humans / agents
echo "$URL"
