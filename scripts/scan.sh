#!/usr/bin/env bash
#
# scan.sh — read-only disk usage scan for macOS
# 只读扫描：定位磁盘占用大户，不做任何删除。
#
# Usage:
#   ./scan.sh            # full scan
#   ./scan.sh --quick    # df only + home tier-1
#
set -u

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

sec() { echo; bold "── $1 ──"; }

home_scan() {
  sec "Home first level (du -h -d 1 ~)"
  du -h -d 1 "$HOME" 2>/dev/null | sort -hr | head -25
}

lib_scan() {
  sec "~/Library breakdown"
  du -h -d 1 "$HOME/Library" 2>/dev/null | sort -hr | head -20

  sec "~/Library/Application Support (top 15)"
  du -h -d 1 "$HOME/Library/Application Support" 2>/dev/null | sort -hr | head -15

  sec "~/Library/Containers (top 10 — app sandboxes)"
  du -h -d 1 "$HOME/Library/Containers" 2>/dev/null | sort -hr | head -10

  sec "~/Library/Caches (top 10 — regenerable)"
  du -h -d 1 "$HOME/Library/Caches" 2>/dev/null | sort -hr | head -10

  sec "Xcode / CoreSimulator"
  du -sh "$HOME/Library/Developer" "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Library/Developer/CoreSimulator" 2>/dev/null
}

dev_scan() {
  sec "Dev caches (regenerable)"
  du -sh \
    "$HOME/.gradle" \
    "$HOME/.npm" \
    "$HOME/.yarn" \
    "$HOME/.cache" \
    "$HOME/.expo" \
    "$HOME/.android" \
    "$HOME/.cocoapods" 2>/dev/null
}

heavy_scan() {
  sec "Heavy / risky paths (may not exist)"
  du -sh \
    "$HOME/Library/Parallels" \
    "$HOME/Parallels" \
    "$HOME/Library/Nemu" \
    "$HOME/Library/Application Support/com.netease.mumu.nemux" \
    "$HOME/Library/Application Support/NoxAppPlayer" \
    "$HOME/Library/Developer/CoreSimulator" \
    "/Applications/Xcode.app" \
    "/tmp/eas-build-"* 2>/dev/null
}

df_section() {
  sec "Disk overview"
  df -h /
  df -h /System/Volumes/Data 2>/dev/null || true
}

if [ "${1:-}" = "--quick" ]; then
  df_section
  home_scan
  exit 0
fi

df_section
home_scan
lib_scan
dev_scan
heavy_scan

echo
bold "Done. Read-only — nothing was deleted. 扫描完成，未做任何删除。"
