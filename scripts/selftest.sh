#!/usr/bin/env bash
#
# selftest.sh — harness regression for apfs-spa / mac-storage-governance
# 不碰真实用户数据：全部在临时 HOME 沙箱里跑。
#
# Usage:
#   ./scripts/selftest.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/scripts/scan.sh"
CLEAN="$ROOT/scripts/clean.sh"

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; }
assert_eq() {
  local name="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name (got=$got want=$want)"; fi
}
assert_file() {
  local name="$1" path="$2"
  if [ -e "$path" ]; then ok "$name"; else bad "$name (missing $path)"; fi
}
assert_gone() {
  local name="$1" path="$2"
  if [ ! -e "$path" ]; then ok "$name"; else bad "$name (still exists $path)"; fi
}

SANDBOX="$(mktemp -d -t apfs-spa-selftest)"
trap 'rm -rf "$SANDBOX"' EXIT

export APFS_SPA_HOME="$SANDBOX/home"
export APFS_SPA_QUARANTINE="$SANDBOX/quarantine"
mkdir -p \
  "$APFS_SPA_HOME/Library/Caches/CocoaPods" \
  "$APFS_SPA_HOME/.gradle/caches" \
  "$APFS_SPA_HOME/Library/Containers/com.tencent.xinWeChat" \
  "$APFS_SPA_HOME/Documents"

echo "pods-cache" > "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"
echo "gradle" > "$APFS_SPA_HOME/.gradle/caches/y.bin"
echo "wechat" > "$APFS_SPA_HOME/Library/Containers/com.tencent.xinWeChat/msg.db"
echo "doc" > "$APFS_SPA_HOME/Documents/keep-me.txt"

printf '\n== apfs-spa selftest ==\n'
printf 'sandbox: %s\n\n' "$SANDBOX"

# 1) JSON scan schema
json_out="$SANDBOX/report.json"
"$SCAN" --json --quick -o "$json_out" >/dev/null
if python3 -c '
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get("schema_version")==1
assert r.get("skill")=="mac-storage-governance"
assert r.get("read_only") is True
assert "findings" in r and "summary" in r and "disk" in r
# CocoaPods should be classified T1
labs=[f["label"] for f in r["findings"] if f["tier"]=="T1"]
assert any("CocoaPods" in x for x in labs), labs
# WeChat T4 forbidden
w=[f for f in r["findings"] if "WeChat" in f.get("label","")]
assert w and w[0]["action"]=="forbidden"
' "$json_out"; then
  ok "scan --json schema + tier labels"
else
  bad "scan --json schema + tier labels"
fi

# 2) dry-run must not move
"$CLEAN" --tier 1 >/dev/null
assert_file "dry-run keeps CocoaPods" "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"

# 3) quarantine round-trip
"$CLEAN" --tier 1 --yes >/dev/null
assert_gone "quarantine removes CocoaPods from home" "$APFS_SPA_HOME/Library/Caches/CocoaPods"
stamp="$(ls -1 "$APFS_SPA_QUARANTINE" | head -1)"
assert_file "quarantine stamp exists" "$APFS_SPA_QUARANTINE/$stamp/MANIFEST.tsv"
"$CLEAN" --restore "$stamp" >/dev/null
assert_file "restore brings CocoaPods back" "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"

# 4) T3 without --apps → exit 1
set +e
"$CLEAN" --tier 3 --yes >/dev/null 2>&1
ec=$?
set -e
assert_eq "T3 without --apps exits 1" "$ec" "1"

# 5) T4 without --yes → exit 1
set +e
"$CLEAN" --tier 4 --apps "com.example.foo" >/dev/null 2>&1
ec=$?
set -e
assert_eq "T4 without --yes exits 1" "$ec" "1"

# 6) red-line WeChat refused on T3 even with --yes
set +e
"$CLEAN" --tier 3 --yes --apps "com.tencent.xinWeChat" >/dev/null 2>&1
ec=$?
set -e
assert_eq "WeChat redline refused (exit 2)" "$ec" "2"
assert_file "WeChat sandbox untouched" "$APFS_SPA_HOME/Library/Containers/com.tencent.xinWeChat/msg.db"

# 7) Documents never targeted by T1
assert_file "Documents untouched" "$APFS_SPA_HOME/Documents/keep-me.txt"

# 8) --purge hard-deletes (still in sandbox only)
echo "z" > "$APFS_SPA_HOME/Library/Caches/CocoaPods/z.txt"
"$CLEAN" --tier 1 --yes --purge >/dev/null
assert_gone "purge removes CocoaPods" "$APFS_SPA_HOME/Library/Caches/CocoaPods"

printf '\nResults: %s passed, %s failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
