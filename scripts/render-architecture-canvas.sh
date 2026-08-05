#!/usr/bin/env bash
#
# render-architecture-canvas.sh — scan JSON → Canvas + 写入跨会话状态
#
# Usage:
#   ./scripts/render-architecture-canvas.sh --report /tmp/apfs-spa.json
#   ./scripts/render-architecture-canvas.sh --report /tmp/apfs-spa.json \
#       --out ~/.cursor/projects/<ws>/canvases/mac-disk-architecture.canvas.tsx
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
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

[ -n "$REPORT" ] && [ -f "$REPORT" ] || { echo "need --report FILE" >&2; exit 1; }

if [ -z "$OUT" ]; then
  # Prefer Cursor project canvases for this skill workspace if present
  CANDIDATES=(
    "$HOME/.cursor/projects/Users-nirass-cursor-skills-mac-storage-governance/canvases/mac-disk-architecture.canvas.tsx"
  )
  for c in "${CANDIDATES[@]}"; do
    if [ -d "$(dirname "$c")" ]; then
      OUT="$c"
      break
    fi
  done
  if [ -z "$OUT" ]; then
    OUT="$ROOT/docs/mac-disk-architecture.canvas.tsx"
  fi
fi

ARGS=(--report "$REPORT" --out "$OUT")
[ -n "${APFS_SPA_STATE:-}" ] && ARGS+=(--state "$APFS_SPA_STATE")
[ -n "$GRAPH_OUT" ] && ARGS+=(--graph-out "$GRAPH_OUT")

python3 "$ROOT/scripts/render_architecture_canvas.py" "${ARGS[@]}"

BASE="${APFS_SPA_HOME:-$HOME}"
export APFS_SPA_LEDGER="${APFS_SPA_LEDGER:-$BASE/.cache/apfs-spa/ledger.sqlite}"

# Mandatory ledger snapshot (architecture history) — script-enforced, not an MD convention
snap_id="$(python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-snapshot --report "$REPORT")"
python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-action \
  --kind canvas \
  --result ok \
  --detail-json "$(python3 -c 'import json,sys; print(json.dumps({"canvas":sys.argv[1],"snapshot_id":int(sys.argv[2])}))' "$OUT" "$snap_id")" \
  --snapshot-id "$snap_id" >/dev/null
echo "ledger snapshot: #$snap_id  db=$APFS_SPA_LEDGER"

if [ "$NO_STATE" = 0 ]; then
  "$ROOT/scripts/state.sh" record-scan --report "$REPORT" >/dev/null
  "$ROOT/scripts/state.sh" record-canvas --path "$OUT" >/dev/null
  echo "state: $("$ROOT/scripts/state.sh" path)"
  "$ROOT/scripts/state.sh" resume-hint
fi

echo "canvas: $OUT"
