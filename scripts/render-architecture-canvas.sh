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
#   *.html  — Canvas-parity SVG node DAG
#   *.md    — Mermaid DAG + checklist
#   preview URL via scripts/preview-architecture.sh (default http://127.0.0.1:8766/)
#
# Flags:
#   --no-open   skip preview server / URL open
#   --no-state  skip state writes
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT=""
OUT=""
GRAPH_OUT=""
NO_STATE=0
NO_OPEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --graph-out) GRAPH_OUT="${2:-}"; shift 2 ;;
    --no-state) NO_STATE=1; shift ;;
    --no-open) NO_OPEN=1; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"
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

  # Prefer Cursor canvases that look like this skill / apfs-spa workspace
  local d best=""
  for d in "$HOME"/.cursor/projects/*/canvases; do
    [ -d "$d" ] || continue
    case "$d" in
      *mac-storage-governance*|*apfs-spa*)
        echo "$d/mac-disk-architecture.canvas.tsx"
        return
        ;;
    esac
  done

  # Else: most recently modified canvases/ (avoid picking a random stale project first)
  best="$(ls -1dt "$HOME"/.cursor/projects/*/canvases 2>/dev/null | head -1 || true)"
  if [ -n "$best" ] && [ -d "$best" ]; then
    echo "$best/mac-disk-architecture.canvas.tsx"
    return
  fi

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

# Publish HTML preview as a stable local URL (not a file path as primary UX)
CACHE_DIR="${APFS_SPA_HOME:-$HOME}/.cache/apfs-spa"
mkdir -p "$CACHE_DIR" 2>/dev/null || true
LATEST="$CACHE_DIR/latest-architecture.html"
if cp -f "$HTML_PATH" "$LATEST" 2>/dev/null; then
  :
else
  LATEST="$(dirname "$HTML_PATH")/latest-architecture.html"
  cp -f "$HTML_PATH" "$LATEST" 2>/dev/null || LATEST="$HTML_PATH"
fi

PREVIEW_URL=""
if [ "$NO_OPEN" = 0 ]; then
  PREVIEW_URL="$("$ROOT/scripts/preview-architecture.sh" "$HTML_PATH" 2>/tmp/apfs-spa-preview-meta.txt | tail -1)" || true
fi
[ -n "$PREVIEW_URL" ] || PREVIEW_URL="http://127.0.0.1:${APFS_SPA_PREVIEW_PORT:-8766}/"

echo "latest:  $LATEST"
echo "url:     $PREVIEW_URL"
if [ -f /tmp/apfs-spa-preview-meta.txt ]; then
  cat /tmp/apfs-spa-preview-meta.txt >&2 || true
fi

echo ""
echo "PRESENTATION (Agent):"
echo "  Primary URL: $PREVIEW_URL"
echo "  Cursor: open .canvas.tsx"
echo "  Do not lead with .html file paths; do not substitute bar charts / indented trees for the node DAG"
