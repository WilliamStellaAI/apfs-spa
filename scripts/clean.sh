#!/usr/bin/env bash
#
# clean.sh — tiered, safe disk cleanup for macOS
# 分级清理：默认 dry-run；--yes 时默认隔离到 quarantine（可回滚）；
# 只有再加 --purge 才真正 rm -rf。
#
# Usage:
#   ./clean.sh --tier 1                  # dry-run: show what T1 would free
#   ./clean.sh --tier 1 --yes            # quarantine (recoverable)
#   ./clean.sh --tier 1 --yes --purge    # hard delete (no quarantine)
#   ./clean.sh --tier 2 --yes            # T2 (confirm first)
#   ./clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac"
#   ./clean.sh --list-quarantine         # show quarantine stamps
#   ./clean.sh --restore <stamp>         # restore one quarantine stamp
#
# Tiers:
#   T1 regenerable caches            (safe, re-downloaded on next build)
#   T2 emulators / simulators / IDEs (safe if user confirms not needed)
#   T3 sandboxes of UNINSTALLED apps (needs explicit --apps bundle ids)
#   T4 in-use app sandboxes / VMs    (forbidden by default)
#
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_SH="$ROOT/scripts/state.sh"
LEDGER_SH="$ROOT/scripts/ledger.sh"

TIER=1
YES=0
PURGE=0
APPS=""
LIST_Q=0
RESTORE_STAMP=""

# APFS_SPA_HOME overrides $HOME for selftests (never set this on real cleanups unless intentional)
BASE="${APFS_SPA_HOME:-$HOME}"
QUARANTINE_ROOT="${APFS_SPA_QUARANTINE:-$BASE/.cache/apfs-spa-quarantine}"
# Governance ledger (SQLite). Required before any destructive action.
export APFS_SPA_LEDGER="${APFS_SPA_LEDGER:-$BASE/.cache/apfs-spa/ledger.sqlite}"

CLEANED_PATHS=()

usage() {
  sed -n '2,18p' "$0"
  exit 0
}

[ $# -eq 0 ] && usage

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-1}"; shift 2 ;;
    --yes)  YES=1; shift ;;
    --purge) PURGE=1; shift ;;
    --apps) APPS="$2"; shift 2 ;;
    --list-quarantine) LIST_Q=1; shift ;;
    --restore) RESTORE_STAMP="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown: $1"; usage ;;
  esac
done

say()  { printf '%s\n' "$1"; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

size_of() { du -sh "$@" 2>/dev/null | sort -hr | head -8; }

rel_under_home() {
  local p="$1"
  case "$p" in
    "$BASE"/*) printf '%s\n' "${p#"$BASE"/}" ;;
    /tmp/*)    printf 'tmp/%s\n' "${p#/tmp/}" ;;
    *)         printf 'abs%s\n' "$(printf '%s' "$p" | tr '/' '_')" ;;
  esac
}

STAMP=""
QUARANTINE_DIR=""

ensure_quarantine() {
  if [ "$PURGE" = 1 ]; then
    return 0
  fi
  if [ -z "$STAMP" ]; then
    STAMP="$(date +%Y%m%d-%H%M%S)"
    QUARANTINE_DIR="$QUARANTINE_ROOT/$STAMP"
    mkdir -p "$QUARANTINE_DIR"
    say "Quarantine: $QUARANTINE_DIR"
  fi
}

ensure_ledger() {
  if [ ! -x "$LEDGER_SH" ] && [ ! -f "$LEDGER_SH" ]; then
    say "FATAL: ledger.sh missing at $LEDGER_SH — refusing to clean without governance ledger."
    exit 3
  fi
  # init db + system locks (idempotent)
  python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" init >/dev/null
}

# Returns 0 if unlocked; prints lock info and returns 3 if locked.
ledger_check_path() {
  local src="$1"
  local mode="quarantine"
  [ "$PURGE" = 1 ] && mode="purge"
  [ "$YES" != 1 ] && mode="dry-run"
  if python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" assert-unlocked \
      --path "$src" --mode "$mode" --record; then
    return 0
  fi
  return 3
}

retire_path() {
  local src="$1"
  ensure_ledger
  if ! ledger_check_path "$src"; then
    say "REFUSED by ledger lock (exit 3): $src"
    say "Unlock only if you really mean it: ./scripts/ledger.sh unlock --id <id>"
    exit 3
  fi
  if [ "$PURGE" = 1 ]; then
    rm -rf "$src"
    say "  purged: $src"
    CLEANED_PATHS+=("$src")
    return 0
  fi
  ensure_quarantine
  local rel dest dest_parent
  rel="$(rel_under_home "$src")"
  dest="$QUARANTINE_DIR/$rel"
  dest_parent="$(dirname "$dest")"
  mkdir -p "$dest_parent"
  if [ -e "$dest" ]; then
    dest="${dest}.$(date +%s)"
    rel="${dest#"$QUARANTINE_DIR"/}"
  fi
  mv "$src" "$dest"
  if [ $? -ne 0 ] || [ -e "$src" ]; then
    say "  FAILED to move (macOS privacy/TCC?): $src"
    say "  Grant Full Disk Access to Cursor (or Terminal), then retry."
    say "  系统设置 → 隐私与安全性 → 完全磁盘访问权限 → 打开 Cursor"
    exit 4
  fi
  # MANIFEST: original_abs_path<TAB>rel_under_quarantine
  printf '%s\t%s\n' "$src" "$rel" >> "$QUARANTINE_DIR/MANIFEST.tsv"
  say "  quarantined → $dest"
  CLEANED_PATHS+=("$src")
}

# would_delete <label> <path> [<path>...]
would_delete() {
  local label="$1"
  shift
  local existing=()
  local p
  for p in "$@"; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      existing+=("$p")
    fi
  done
  if [ ${#existing[@]} -eq 0 ]; then
    return 0
  fi

  say ""
  bold "  [$label]"
  size_of "${existing[@]}"
  ensure_ledger
  if [ "$YES" = 1 ]; then
    for p in "${existing[@]}"; do
      retire_path "$p"
    done
  else
    for p in "${existing[@]}"; do
      if ! ledger_check_path "$p"; then
        say "  LOCKED (would refuse on --yes): $p"
      fi
    done
    say "  (dry-run; add --yes to quarantine, or --yes --purge to hard-delete)"
  fi
}

list_quarantine() {
  if [ ! -d "$QUARANTINE_ROOT" ]; then
    say "No quarantine yet at $QUARANTINE_ROOT"
    exit 0
  fi
  bold "Quarantine stamps under $QUARANTINE_ROOT"
  # shellcheck disable=SC2086
  if ! du -sh "$QUARANTINE_ROOT"/* 2>/dev/null | sort -hr; then
    say "(empty)"
  fi
  exit 0
}

# Restore using MANIFEST.tsv written at quarantine time
restore_stamp() {
  local stamp="$1"
  local src="$QUARANTINE_ROOT/$stamp"
  local manifest="$src/MANIFEST.tsv"
  if [ -z "$stamp" ] || [ ! -d "$src" ]; then
    say "Stamp not found: $stamp"
    say "Use --list-quarantine to see available stamps."
    exit 1
  fi
  if [ ! -f "$manifest" ]; then
    say "No MANIFEST.tsv in $src — cannot safely auto-restore."
    say "Manual: move folders under the stamp back to their original paths."
    exit 1
  fi
  bold "Restoring from $src"
  local orig rel qpath
  # shellcheck disable=SC2034
  while IFS=$'\t' read -r orig rel; do
    [ -n "$orig" ] || continue
    qpath="$src/$rel"
    if [ ! -e "$qpath" ]; then
      say "  missing in quarantine: $rel"
      continue
    fi
    if [ -e "$orig" ]; then
      say "  skip (exists): $orig"
      continue
    fi
    mkdir -p "$(dirname "$orig")"
    mv "$qpath" "$orig"
    say "  restored: $orig"
  done < "$manifest"

  bold "Done. You may remove the stamp dir if empty: rm -rf \"$src\""
  exit 0
}

# Known in-use sandboxes — refuse even on T3/T4 unless APFS_SPA_ALLOW_REDLINE=1
redline_guard() {
  local b
  for b in $APPS; do
    case "$b" in
      com.tencent.xinWeChat|com.tencent.WeWorkMac|com.tencent.wwmapp)
        if [ "${APFS_SPA_ALLOW_REDLINE:-0}" != 1 ]; then
          say "REFUSED: $b is a known in-use IM sandbox (red line)."
          say "Clear cache inside the app, or set APFS_SPA_ALLOW_REDLINE=1 only after explicit user confirmation."
          exit 2
        fi
        ;;
    esac
  done
}

[ "$LIST_Q" = 1 ] && list_quarantine
[ -n "$RESTORE_STAMP" ] && restore_stamp "$RESTORE_STAMP"

before=$(df -h / | awk 'NR==2{print $4}')
bold "Avail BEFORE: $before"
if [ "$YES" = 1 ] && [ "$PURGE" = 1 ]; then
  bold "MODE: hard delete (--purge)"
elif [ "$YES" = 1 ]; then
  bold "MODE: quarantine (recoverable)"
else
  bold "MODE: dry-run"
fi

shopt -s nullglob 2>/dev/null || true

case "$TIER" in
  1)
    bold "== T1 — regenerable caches (safe, re-downloaded) =="
    would_delete "CocoaPods"            "$BASE/Library/Caches/CocoaPods"
    would_delete "ReactNative prebuilts" "$BASE/Library/Caches/ReactNative"
    would_delete "Gradle caches"        "$BASE/.gradle/caches"
    would_delete "npm cache"            "$BASE/.npm/_cacache"
    would_delete "yarn cache"           "$BASE/Library/Caches/Yarn"
    would_delete "Xcode DerivedData"    "$BASE/Library/Developer/Xcode/DerivedData"
    would_delete "Homebrew cache"       "$BASE/Library/Caches/Homebrew"
    would_delete "node-gyp cache"       "$BASE/Library/Caches/node-gyp"
    would_delete "Cursor ShipIt"        "$BASE/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt"
    would_delete "Trae CN cache"        "$BASE/Library/Caches/Trae CN"
    would_delete "Trae ShipIt"          "$BASE/Library/Caches/cn.trae.app.ShipIt"
    would_delete "Antigravity updater" "$BASE/Library/Caches/antigravity-updater"
    eas_paths=(/tmp/eas-build-*)
    if [ ${#eas_paths[@]} -gt 0 ]; then
      would_delete "EAS local build tmp" "${eas_paths[@]}"
    fi
    ;;
  2)
    bold "== T2 — emulators / simulators / IDE data (confirm first) =="
    bold ">> These remove large local data. Verify the user no longer needs them."
    would_delete "MuMu emulator"  "$BASE/Library/Application Support/com.netease.mumu.nemux" "$BASE/Library/Nemu"
    would_delete "Nox emulator"   "$BASE/Library/Application Support/NoxAppPlayer"
    would_delete "CoreSimulator"  "$BASE/Library/Developer/CoreSimulator"
    ;;
  3)
    bold "== T3 — sandboxes of UNINSTALLED apps =="
    if [ -z "$APPS" ]; then
      say "No --apps given. Pass bundle ids, e.g.:"
      say '  ./clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac com.tencent.wwmapp"'
      exit 1
    fi
    redline_guard
    for b in $APPS; do
      would_delete "container $b" "$BASE/Library/Containers/$b"
    done
    ;;
  4)
    bold "== T4 — EXTREMELY RISKY (in-use app sandboxes / VMs) =="
    bold ">> Requires --yes AND explicit --apps. Double-check with the user."
    if [ "$YES" != 1 ]; then
      say "T4 requires --yes. Refusing to run."
      exit 1
    fi
    if [ -z "$APPS" ]; then
      say "Pass explicit --apps list."
      exit 1
    fi
    redline_guard
    for b in $APPS; do
      would_delete "container $b" "$BASE/Library/Containers/$b"
    done
    ;;
  *)
    echo "Unknown tier: $TIER"; usage ;;
esac

after=$(df -h / | awk 'NR==2{print $4}')
bold "Avail AFTER: $after"

echo
mode="dry-run"
if [ "$YES" = 1 ]; then
  mode="quarantine"
  [ "$PURGE" = 1 ] && mode="purge"
fi

# Always require ledger present before finishing a clean attempt
ensure_ledger

if [ "$YES" = 1 ]; then
  if [ -x "$STATE_SH" ] || [ -f "$STATE_SH" ]; then
    "$STATE_SH" record-clean \
      --tier "$TIER" \
      --mode "$mode" \
      --stamp "${STAMP:-}" \
      --avail-before "$before" \
      --avail-after "$after" >/dev/null || true
  fi
  paths_joined=""
  if [ ${#CLEANED_PATHS[@]} -gt 0 ]; then
    paths_joined="$(printf '%s\n' "${CLEANED_PATHS[@]}")"
  fi
  python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-action \
    --kind clean \
    --tier "$TIER" \
    --mode "$mode" \
    --stamp "${STAMP:-}" \
    --paths "$paths_joined" \
    --result ok \
    --avail-before "$before" \
    --avail-after "$after" \
    --detail-json "{\"apps\":$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$APPS")}" \
    >/dev/null || true
  if [ "$PURGE" = 1 ]; then
    bold "Done (purged). 用 df -h / 复核；若 Avail 未变，真正的大头在别处。"
  else
    bold "Done (quarantined). 恢复: ./clean.sh --restore $STAMP"
    bold "列表: ./clean.sh --list-quarantine"
    bold "请用 df -h / 复核收益；若 Avail 未变，真正的大头在别处，重新扫描。"
  fi
else
  python3 "$ROOT/scripts/ledger.py" --db "$APFS_SPA_LEDGER" record-action \
    --kind clean \
    --tier "$TIER" \
    --mode dry-run \
    --result ok \
    --avail-before "$before" \
    --avail-after "$after" \
    >/dev/null || true
  bold "Dry-run only. Re-run with --yes to quarantine, or --yes --purge to hard-delete."
fi
bold "Ledger: $APFS_SPA_LEDGER  (locks: ./scripts/ledger.sh list-locks)"
