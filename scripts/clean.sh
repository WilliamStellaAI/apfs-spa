#!/usr/bin/env bash
#
# clean.sh — tiered, safe disk cleanup for macOS
# 分级清理脚本：默认 dry-run，只有加 --yes 才真的删除。
#
# Usage:
#   ./clean.sh --tier 1                  # dry-run: show what T1 would free
#   ./clean.sh --tier 1 --yes            # actually clean T1
#   ./clean.sh --tier 2 --yes            # T2 + T1
#   ./clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac com.tencent.wwmapp"
#   ./clean.sh --tier 4 --yes            # EXTREMELY risky, triple-confirm
#
# Tiers:
#   T1 regenerable dev caches        (safe, re-downloaded on next build)
#   T2 emulators / simulators / IDEs (safe if user confirms not needed)
#   T3 sandboxes of UNINSTALLED apps (needs explicit --apps bundle ids)
#   T4 in-use app sandboxes / VMs    (forbidden by default)
#
set -u

TIER=1
YES=0
APPS=""
SHOW_DU_CMD="${SHOW_DU_CMD:-}"

usage() {
  sed -n '2,14p' "$0"
  exit 0
}

[ $# -eq 0 ] && usage

while [ $# -gt 0 ]; do
  case "$1" in
    --tier) TIER="${2:-1}"; shift 2 ;;
    --yes)  YES=1; shift ;;
    --apps) APPS="$2"; shift 2 ;;
    *) echo "unknown: $1"; usage ;;
  esac
done

say()  { printf '%s\n' "$1"; }
bold() { printf '\033[1m%s\033[0m\n' "$1"; }

# size_of <path...> — best-effort human size
size_of() { du -sh "$@" 2>/dev/null | sort -hr | head -5; }

# would_delete <label> <path...> — print size, delete only with --yes
would_delete() {
  local label="$1"; shift
  if [ -e "$1" ] || [ -L "$1" ]; then
    say ""
    bold "  [$label]"
    size_of "$@"
    if [ "$YES" = 1 ]; then
      rm -rf "$@"
      say "  deleted."
    else
      say "  (dry-run; add --yes to delete)"
    fi
  fi
}

before=$(df -h / | awk 'NR==2{print $4}')
bold "Avail BEFORE: $before"

case "$TIER" in
  1)
    bold "== T1 — regenerable dev caches (always safe, re-downloaded) =="
    would_delete "CocoaPods"          "$HOME/Library/Caches/CocoaPods"
    would_delete "ReactNative prebuilts" "$HOME/Library/Caches/ReactNative"
    would_delete "Gradle caches"      "$HOME/.gradle/caches"
    would_delete "npm cache"          "$HOME/.npm/_cacache"
    would_delete "yarn cache"         "$HOME/Library/Caches/Yarn"
    would_delete "Xcode DerivedData"  "$HOME/Library/Developer/Xcode/DerivedData"
    would_delete "EAS local build tmp" /tmp/eas-build-*
    ;;
  2)
    bold "== T2 — emulators / simulators / IDE data (confirm first) =="
    bold ">> These delete permanently. Verify the user no longer needs them."
    would_delete "MuMu emulator"  "$HOME/Library/Application Support/com.netease.mumu.nemux" "$HOME/Library/Nemu"
    would_delete "Nox emulator"   "$HOME/Library/Application Support/NoxAppPlayer"
    would_delete "CoreSimulator"  "$HOME/Library/Developer/CoreSimulator"
    ;;
  3)
    bold "== T3 — sandboxes of UNINSTALLED apps =="
    if [ -z "$APPS" ]; then
      say "No --apps given. Pass bundle ids, e.g.:"
      say '  ./clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac com.tencent.wwmapp"'
      exit 1
    fi
    for b in $APPS; do
      would_delete "container $b" "$HOME/Library/Containers/$b"
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
    for b in $APPS; do
      would_delete "container $b" "$HOME/Library/Containers/$b"
    done
    ;;
  *)
    echo "Unknown tier: $TIER"; usage ;;
esac

after=$(df -h / | awk 'NR==2{print $4}')
bold "Avail AFTER: $after"

echo
if [ "$YES" = 1 ]; then
  bold "Done. 请用 `df -h /` 复核收益；若 Avail 未变，真正的大头在别处，重新扫描。"
else
  bold "Dry-run only. Re-run with --yes to actually clean. 本次仅预览，未删除任何内容。"
fi
