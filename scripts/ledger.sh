#!/usr/bin/env bash
#
# ledger.sh — 治理账本（SQLite）：架构快照 / 行为结果 / 人为上锁
# 清理前由 clean.sh 强制调用 assert-unlocked；不是给 AI 读的 md 约定。
#
# Usage:
#   ./scripts/ledger.sh status
#   ./scripts/ledger.sh list-locks
#   ./scripts/ledger.sh lock --type bundle --target com.example.app --reason "我还要用"
#   ./scripts/ledger.sh lock --type path --target ~/Library/Application\ Support/Cursor --reason "别动"
#   ./scripts/ledger.sh lock --type prefix --target Documents --reason "文档"
#   ./scripts/ledger.sh unlock --id 4
#   ./scripts/ledger.sh history
#   ./scripts/ledger.sh history --snapshots
#   ./scripts/ledger.sh record-snapshot --report /tmp/apfs-spa.json
#   ./scripts/ledger.sh assert-unlocked --path ~/Library/Caches/CocoaPods
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/ledger.py" "$@"
