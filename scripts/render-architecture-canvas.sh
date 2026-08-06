#!/usr/bin/env bash
#
# render-architecture-canvas.sh — scan JSON → Canvas + HTML + Mermaid + 跨会话状态
#
# Usage:
#   ./scripts/render-architecture-canvas.sh --report /tmp/apfs-spa.json
#   ./scripts/render-architecture-canvas.sh --report /tmp/apfs-spa.json \
#       --out ~/.cursor/projects/<ws>/canvases/mac-disk-architecture.canvas.tsx
#
# Always also writes sibling:
#   *.html  — 浏览器打开（Codex / WorkBuddy / 任意宿主）
#   *.md    — Mermaid 架构 DAG + 清单（可直接贴进支持 Mermaid 的聊天）
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT=""
OUT=""
GRAPH_OUT=""
NO_STATE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --graph-out) GRAPH_OUT="${2:-}"; shift 2 ;;
    --no-state) NO_STATE=1; shift ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

[ -n "$REPORT" ] && [ -f "$REPORT" ] || { echo "need --report FILE" >&2; exit 1; }

pick_out() {
  if [ -n "${APFS_SPA_CANVAS_OUT:-}" ]; then
    echo "$APFS_SPA_CANVAS_OUT"
    return
  fi
  # Cursor: any project canvases dir under ~/.cursor/projects
  local d
  for d in "$HOME"/.cursor/projects/*/canvases; do
    [ -d "$d" ] || continue
    echo "$d/mac-disk-architecture.canvas.tsx"
    return
  done
  # Portable default (Codex / WorkBuddy / CLI)
  mkdir -p "$HOME/.cache/apfs-spa"
  echo "$HOME/.cache/apfs-spa/mac-disk-architecture.canvas.tsx"
}

if [ -z "$OUT" ]; then
  OUT="$(pick_out)"
fi

ARGS=(--report "$REPORT" --out "$OUT")
[ -n "${APFS_SPA_STATE:-}" ] && ARGS+=(--state "$APFS_SPA_STATE")
[ -n "$GRAPH_OUT" ] && ARGS+=(--graph-out "$GRAPH_OUT")

mapfile_out="$(python3 "$ROOT/scripts/render_architecture_canvas.py" "${ARGS[@]}")"
# python prints: canvas\nhtml\nmermaid
CANVAS_PATH="$(printf '%s\n' "$mapfile_out" | sed -n '1p')"
HTML_PATH="$(printf '%s\n' "$mapfile_out" | sed -n '2p')"
MD_PATH="$(printf '%s\n' "$mapfile_out" | sed -n '3p')"

BASE="${APFS_SPA_HOME:-$HOME}"
export APFS_SPA_LEDGER="${APFS_SPA_LEDGER:-$BASE/.cache/apfs-spa/ledger.sqlite}"

# Mandatory ledger snapshot (architecture history) — script-enforced, not an MD convention
snap_id="$(python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-snapshot --report "$REPORT")"
python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-action \
  --kind canvas \
  --result ok \
  --detail-json "$(python3 -c 'import json,sys; print(json.dumps({"canvas":sys.argv[1],"html":sys.argv[2],"mermaid":sys.argv[3],"snapshot_id":int(sys.argv[4])}))' "$CANVAS_PATH" "$HTML_PATH" "$MD_PATH" "$snap_id")" \
  --snapshot-id "$snap_id" >/dev/null
echo "ledger snapshot: #$snap_id  db=$APFS_SPA_LEDGER"

if [ "$NO_STATE" = 0 ]; then
  "$ROOT/scripts/state.sh" record-scan --report "$REPORT" >/dev/null
  "$ROOT/scripts/state.sh" record-canvas --path "$CANVAS_PATH" >/dev/null
  echo "state: $("$ROOT/scripts/state.sh" path)"
  "$ROOT/scripts/state.sh" resume-hint
fi

echo "canvas:  $CANVAS_PATH"
echo "html:    $HTML_PATH"
echo "mermaid: $MD_PATH"
echo ""
echo "PRESENTATION (Agent — do not paste .canvas.tsx into chat):"
echo "  Cursor:     open the .canvas.tsx (interactive DAG)"
echo "  Codex/etc:  open HTML in browser, OR paste the .md Mermaid block into chat"
echo "  Forbidden:  rewrite as bar-chart-only report that drops the architecture tree"
