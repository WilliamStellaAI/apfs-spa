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
export APFS_SPA_SKIP_LSOF=1
export APFS_SPA_STATE="$SANDBOX/state.json"
export APFS_SPA_LEDGER="$SANDBOX/ledger.sqlite"
mkdir -p \
  "$APFS_SPA_HOME/Library/Caches/CocoaPods" \
  "$APFS_SPA_HOME/.gradle/caches" \
  "$APFS_SPA_HOME/Library/Containers/com.tencent.xinWeChat" \
  "$APFS_SPA_HOME/Library/Containers/5ZSL2CJU2T.com.dingtalk.mac/Data" \
  "$APFS_SPA_HOME/Applications/DingTalk.app/Contents" \
  "$APFS_SPA_HOME/Documents"

echo "pods-cache" > "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"
echo "gradle" > "$APFS_SPA_HOME/.gradle/caches/y.bin"
echo "wechat" > "$APFS_SPA_HOME/Library/Containers/com.tencent.xinWeChat/msg.db"
echo "dingtalk-data" > "$APFS_SPA_HOME/Library/Containers/5ZSL2CJU2T.com.dingtalk.mac/Data/chat.db"
echo "doc" > "$APFS_SPA_HOME/Documents/keep-me.txt"

# DingTalk-style mismatch: container folder ≠ CFBundleIdentifier; metadata points at .app
DT_APP="$APFS_SPA_HOME/Applications/DingTalk.app"
DT_CONT="$APFS_SPA_HOME/Library/Containers/5ZSL2CJU2T.com.dingtalk.mac"
python3 - "$DT_APP" "$DT_CONT" <<'PY'
import plistlib, sys
from pathlib import Path
app, cont = Path(sys.argv[1]), Path(sys.argv[2])
info = app / "Contents" / "Info.plist"
with open(info, "wb") as f:
    plistlib.dump({
        "CFBundleIdentifier": "com.alibaba.DingTalkMac",
        "CFBundleExecutable": "DingTalk",
        "CFBundleName": "DingTalk",
    }, f)
meta = {
    "MCMMetadataIdentifier": "5ZSL2CJU2T.com.dingtalk.mac",
    "MCMMetadataInfo": {
        "SandboxProfileDataValidationInfo": {
            "Parameters": {
                "application_bundle": str(app),
                "application_bundle_id": "5ZSL2CJU2T.com.dingtalk.mac",
            }
        }
    },
}
with open(cont / ".com.apple.containermanagerd.metadata.plist", "wb") as f:
    plistlib.dump(meta, f)
PY

printf '\n== apfs-spa selftest ==\n'
printf 'sandbox: %s\n\n' "$SANDBOX"

# 1) JSON scan schema
json_out="$SANDBOX/report.json"
"$SCAN" --json --quick -o "$json_out" >/dev/null
if python3 -c '
import json,sys
r=json.load(open(sys.argv[1]))
assert r.get("schema_version")==2
assert r.get("skill")=="mac-storage-governance"
assert r.get("read_only") is True
assert "findings" in r and "summary" in r and "disk" in r
# CocoaPods should be classified T1
labs=[f["label"] for f in r["findings"] if f["tier"]=="T1"]
assert any("CocoaPods" in x for x in labs), labs
# findings carry usage/deps in schema v2
f0=r["findings"][0]
assert "usage" in f0 and "deps" in f0 and "confidence" in f0
# WeChat: catalog T4; in sandbox usually no real app → still present
w=[f for f in r["findings"] if "WeChat" in f.get("label","")]
assert w
assert w[0]["action"] in ("forbidden", "ask_first")
# DingTalk: container id ≠ CFBundleIdentifier; must still find owner via metadata
d=[f for f in r["findings"] if "DingTalk" in f.get("label","")]
assert d, "DingTalk sandbox missing from findings"
assert d[0]["usage"].get("owner_installed") is True, d[0].get("usage")
assert d[0]["tier"] == "T4", (d[0]["tier"], d[0].get("classify_reasons"))
assert d[0]["usage"].get("owner_match") == "container_metadata", d[0].get("usage")
' "$json_out"; then
  ok "scan --json schema + tier labels"
else
  bad "scan --json schema + tier labels"
fi

# 1b) without metadata, alias CFBundle still finds DingTalk (Team-ID folder ≠ plist id)
rm -f "$DT_CONT/.com.apple.containermanagerd.metadata.plist"
json_alias="$SANDBOX/report-alias.json"
"$SCAN" --json --quick -o "$json_alias" >/dev/null
if python3 -c '
import json,sys
r=json.load(open(sys.argv[1]))
d=[f for f in r["findings"] if "DingTalk" in f.get("label","")]
assert d and d[0]["usage"].get("owner_installed") is True
assert d[0]["tier"] == "T4"
assert d[0]["usage"].get("owner_match") == "cf_bundle_alias", d[0].get("usage")
' "$json_alias"; then
  ok "DingTalk owner via CFBundle alias when metadata missing"
else
  bad "DingTalk owner via CFBundle alias when metadata missing"
fi
# restore metadata for later scans that may touch home fixtures
python3 - "$DT_APP" "$DT_CONT" <<'PY'
import plistlib, sys
from pathlib import Path
app, cont = Path(sys.argv[1]), Path(sys.argv[2])
meta = {
    "MCMMetadataIdentifier": "5ZSL2CJU2T.com.dingtalk.mac",
    "MCMMetadataInfo": {
        "SandboxProfileDataValidationInfo": {
            "Parameters": {
                "application_bundle": str(app),
                "application_bundle_id": "5ZSL2CJU2T.com.dingtalk.mac",
            }
        }
    },
}
with open(cont / ".com.apple.containermanagerd.metadata.plist", "wb") as f:
    plistlib.dump(meta, f)
PY

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

# 9) cross-session state recorded clean
STATE="$ROOT/scripts/state.sh"
if python3 -c '
import json,sys
s=json.load(open(sys.argv[1]))
assert s.get("schema_version")==1
assert s.get("phase")=="cleaned"
assert s.get("cleans")
' "$APFS_SPA_STATE"; then
  ok "state records clean phase"
else
  bad "state records clean phase"
fi

# 10) render canvas from JSON (+ html + mermaid for non-Cursor hosts)
RENDER="$ROOT/scripts/render-architecture-canvas.sh"
canvas_out="$SANDBOX/mac-disk-architecture.canvas.tsx"
"$RENDER" --report "$json_out" --out "$canvas_out" --no-state --no-open >/dev/null
html_out="$SANDBOX/mac-disk-architecture.html"
md_out="$SANDBOX/mac-disk-architecture.md"
if python3 -c '
from pathlib import Path
import sys
p=Path(sys.argv[1])
t=p.read_text()
assert "const GRAPH" in t
assert "export default function" in t
assert "清理建议清单" in t
assert "不要动" in t
h=Path(sys.argv[2]).read_text()
assert "占用结构（可点击）" in h and "<svg" in h and "g class=\"n\"" in h
assert "架构树" not in h
m=Path(sys.argv[3]).read_text()
assert "```mermaid" in m and "flowchart TD" in m
assert "清理建议清单" in m
' "$canvas_out" "$html_out" "$md_out"; then
  ok "render-architecture-canvas emits tsx+html(DAG)+mermaid"
else
  bad "render-architecture-canvas emits tsx+html(DAG)+mermaid"
fi

# 11) state scan+canvas+resume
"$STATE" reset >/dev/null
"$STATE" record-scan --report "$json_out" >/dev/null
"$STATE" record-canvas --path "$canvas_out" >/dev/null
phase="$("$STATE" status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["phase"])')"
assert_eq "state phase awaiting_confirm" "$phase" "awaiting_confirm"
hint="$("$STATE" resume-hint)"
case "$hint" in
  *跨会话状态*) ok "resume-hint speaks Chinese" ;;
  *) bad "resume-hint speaks Chinese" ;;
esac

# 12) ledger snapshot recorded by render
LEDGER="$ROOT/scripts/ledger.sh"
snaps="$("$LEDGER" --db "$APFS_SPA_LEDGER" history --snapshots --json | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
if [ "$snaps" -ge 1 ]; then ok "ledger has architecture snapshot"; else bad "ledger has architecture snapshot"; fi

# 13) human lock blocks clean even for T1 (script gate, not MD)
mkdir -p "$APFS_SPA_HOME/Library/Caches/CocoaPods"
echo "locked-pods" > "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"
"$LEDGER" --db "$APFS_SPA_LEDGER" lock --type path \
  --target "$APFS_SPA_HOME/Library/Caches/CocoaPods" \
  --reason "selftest human lock" >/dev/null
set +e
"$CLEAN" --tier 1 --yes >/dev/null 2>&1
ec=$?
set -e
assert_eq "ledger lock refuses clean (exit 3)" "$ec" "3"
assert_file "locked CocoaPods untouched" "$APFS_SPA_HOME/Library/Caches/CocoaPods/x.txt"

# 14) unlock then clean works again
"$LEDGER" --db "$APFS_SPA_LEDGER" unlock --type path \
  --target "$APFS_SPA_HOME/Library/Caches/CocoaPods" >/dev/null
"$CLEAN" --tier 1 --yes >/dev/null
assert_gone "unlocked CocoaPods quarantined" "$APFS_SPA_HOME/Library/Caches/CocoaPods"

# 15) system WeChat lock present in table
if "$LEDGER" --db "$APFS_SPA_LEDGER" list-locks --json | python3 -c '
import json,sys
rows=json.load(sys.stdin)
assert any(r["target"]=="com.tencent.xinWeChat" and r["active"]==1 for r in rows)
'; then
  ok "system WeChat lock seeded in ledger"
else
  bad "system WeChat lock seeded in ledger"
fi

# 16) Cursor shell-guard hook denies rm on locked path
GUARD="$ROOT/scripts/cursor-hook-shell-guard.sh"
locked_dir="$APFS_SPA_HOME/Library/Caches/HookDemo"
mkdir -p "$locked_dir"
"$LEDGER" --db "$APFS_SPA_LEDGER" lock --type path --target "$locked_dir" --reason "hook demo" >/dev/null
perm="$(printf '%s' "{\"command\":\"rm -rf $locked_dir\"}" | APFS_SPA_LEDGER="$APFS_SPA_LEDGER" APFS_SPA_HOME="$APFS_SPA_HOME" "$GUARD" | python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])')"
assert_eq "shell-guard denies rm on locked path" "$perm" "deny"

perm2="$(printf '%s' '{"command":"df -h /"}' | APFS_SPA_LEDGER="$APFS_SPA_LEDGER" APFS_SPA_HOME="$APFS_SPA_HOME" "$GUARD" | python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])')"
assert_eq "shell-guard allows df" "$perm2" "allow"

perm3="$(printf '%s' "{\"command\":\"$CLEAN --tier 1\"}" | APFS_SPA_LEDGER="$APFS_SPA_LEDGER" APFS_SPA_HOME="$APFS_SPA_HOME" "$GUARD" | python3 -c 'import json,sys; print(json.load(sys.stdin)["permission"])')"
assert_eq "shell-guard allows clean.sh" "$perm3" "allow"

printf '\nResults: %s passed, %s failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
