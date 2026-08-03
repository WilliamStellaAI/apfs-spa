#!/usr/bin/env bash
#
# install.sh — symlink this skill into common Agent Skills directories
# 一份仓库，多 Agent 共用（Cursor / WorkBuddy / Codex / 通用 ~/.agents）
#
# Usage:
#   ./scripts/install.sh           # create/update symlinks
#   ./scripts/install.sh --dry     # show targets only
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="mac-storage-governance"
DRY=0
[ "${1:-}" = "--dry" ] && DRY=1

targets=(
  "$HOME/.cursor/skills/$NAME"
  "$HOME/.workbuddy/skills/$NAME"
  "$HOME/.agents/skills/$NAME"
  "$HOME/.codex/skills/$NAME"
)

say() { printf '%s\n' "$*"; }

say "Skill root: $ROOT"
say ""

for dest in "${targets[@]}"; do
  parent="$(dirname "$dest")"
  if [ "$DRY" = 1 ]; then
    say "[dry] $dest  →  $ROOT"
    continue
  fi
  mkdir -p "$parent"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ]; then
      current="$(readlink "$dest")"
      if [ "$current" = "$ROOT" ]; then
        say "ok (already): $dest"
        continue
      fi
      rm "$dest"
    elif [ "$dest" -ef "$ROOT" ]; then
      say "ok (same dir): $dest"
      continue
    else
      say "skip (exists, not symlink): $dest"
      say "  → move it aside or remove, then re-run"
      continue
    fi
  fi
  ln -sfn "$ROOT" "$dest"
  say "linked: $dest  →  $ROOT"
done

say ""
say "Manus: 控制台 Skills → 导入本 GitHub 仓库或上传 zip（云端沙箱≠你的 Mac 盘）。"
say "Done."
