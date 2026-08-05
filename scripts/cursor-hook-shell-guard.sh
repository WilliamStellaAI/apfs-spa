#!/usr/bin/env bash
#
# cursor-hook-shell-guard.sh — Cursor beforeShellExecution entrypoint
# Reads hook JSON from stdin, writes permission JSON to stdout.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/cursor-hook-shell-guard.py"
