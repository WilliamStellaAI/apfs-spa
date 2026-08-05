#!/usr/bin/env bash
#
# install.sh — symlink this skill into common Agent Skills directories
# 一份仓库，多 Agent 共用（Cursor / WorkBuddy / Codex / 通用 ~/.agents）
# 可选安装 Cursor beforeShellExecution hook（读 ledger 锁，拦截 rm）
#
# Usage:
#   ./scripts/install.sh              # skills + Cursor shell guard hook
#   ./scripts/install.sh --dry
#   ./scripts/install.sh --no-hooks   # skills only
#   ./scripts/install.sh --hooks-only
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="mac-storage-governance"
DRY=0
DO_SKILLS=1
DO_HOOKS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --dry) DRY=1; shift ;;
    --no-hooks) DO_HOOKS=0; shift ;;
    --hooks-only) DO_SKILLS=0; DO_HOOKS=1; shift ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

targets=(
  "$HOME/.cursor/skills/$NAME"
  "$HOME/.workbuddy/skills/$NAME"
  "$HOME/.agents/skills/$NAME"
  "$HOME/.codex/skills/$NAME"
)

say() { printf '%s\n' "$*"; }

say "Skill root: $ROOT"
say ""

if [ "$DO_SKILLS" = 1 ]; then
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
fi

if [ "$DO_HOOKS" = 1 ]; then
  HOOKS_JSON="$HOME/.cursor/hooks.json"
  SRC_HOOK_PY="$ROOT/scripts/cursor-hook-shell-guard.py"

  if [ "$DRY" = 1 ]; then
    say "[dry] merge beforeShellExecution → python3 $SRC_HOOK_PY into $HOOKS_JSON"
  else
    python3 - "$HOOKS_JSON" "$SRC_HOOK_PY" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
src = str(Path(sys.argv[2]).resolve())
entry = {
    "command": f"python3 {src}",
    "failClosed": True,
}
marker = "cursor-hook-shell-guard"

if path.exists():
    data = json.loads(path.read_text(encoding="utf-8"))
else:
    data = {"version": 1, "hooks": {}}

if not isinstance(data, dict):
    data = {"version": 1, "hooks": {}}
data.setdefault("version", 1)
hooks = data.setdefault("hooks", {})
lst = hooks.setdefault("beforeShellExecution", [])
lst = [
    h
    for h in lst
    if not (isinstance(h, dict) and marker in str(h.get("command") or ""))
]
lst.append(entry)
hooks["beforeShellExecution"] = lst
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"hooks.json updated: {path}")
print(f"guard command: python3 {src}")
PY
    say "Cursor hook installed (failClosed). Check Cursor Settings → Hooks if needed."
  fi
  say ""
fi

say "Manus: 控制台 Skills → 导入本 GitHub 仓库或上传 zip（云端沙箱≠你的 Mac 盘）。"
say "Done."
