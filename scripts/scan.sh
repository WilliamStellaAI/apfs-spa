#!/usr/bin/env bash
#
# scan.sh — read-only disk usage scan for macOS
# 只读扫描：定位磁盘占用大户，不做任何删除。
#
# Usage:
#   ./scan.sh              # full human-readable scan
#   ./scan.sh --quick      # df + home tier-1
#   ./scan.sh --json       # machine-readable JSON on stdout (harness)
#   ./scan.sh --json --quick
#   ./scan.sh --json -o /tmp/apfs-spa-report.json
#
set -u

MODE=full
JSON=0
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --quick) MODE=quick; shift ;;
    --json)  JSON=1; shift ;;
    -o|--output) OUT="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) echo "unknown: $1" >&2; exit 1 ;;
  esac
done

BASE="${APFS_SPA_HOME:-$HOME}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
sec() { echo; bold "── $1 ──"; }

home_scan() {
  sec "Home first level (du -h -d 1 ~)"
  du -h -d 1 "$BASE" 2>/dev/null | sort -hr | head -25
}

lib_scan() {
  sec "~/Library breakdown"
  du -h -d 1 "$BASE/Library" 2>/dev/null | sort -hr | head -20

  sec "~/Library/Application Support (top 15)"
  du -h -d 1 "$BASE/Library/Application Support" 2>/dev/null | sort -hr | head -15

  sec "~/Library/Containers (top 10 — app sandboxes)"
  du -h -d 1 "$BASE/Library/Containers" 2>/dev/null | sort -hr | head -10

  sec "~/Library/Caches (top 10 — regenerable)"
  du -h -d 1 "$BASE/Library/Caches" 2>/dev/null | sort -hr | head -10

  sec "Xcode / CoreSimulator"
  du -sh "$BASE/Library/Developer" "$BASE/Library/Developer/Xcode/DerivedData" "$BASE/Library/Developer/CoreSimulator" 2>/dev/null
}

dev_scan() {
  sec "Dev caches (regenerable)"
  du -sh \
    "$BASE/.gradle" \
    "$BASE/.npm" \
    "$BASE/.yarn" \
    "$BASE/.cache" \
    "$BASE/.expo" \
    "$BASE/.android" \
    "$BASE/.cocoapods" 2>/dev/null
}

heavy_scan() {
  sec "Heavy / risky paths (may not exist)"
  # shellcheck disable=SC2086
  du -sh \
    "$BASE/Library/Parallels" \
    "$BASE/Parallels" \
    "$BASE/Library/Nemu" \
    "$BASE/Library/Application Support/com.netease.mumu.nemux" \
    "$BASE/Library/Application Support/NoxAppPlayer" \
    "$BASE/Library/Developer/CoreSimulator" \
    "/Applications/Xcode.app" \
    /tmp/eas-build-* 2>/dev/null
}

df_section() {
  sec "Disk overview"
  df -h /
  df -h /System/Volumes/Data 2>/dev/null || true
}

# --- JSON harness report ---------------------------------------------------

json_scan() {
  local tmp
  tmp="$(mktemp -t apfs-spa-scan)"
  # TSV: tier \t action \t label \t path
  # action: safe_to_clean | ask_first | forbidden | info
  {
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "CocoaPods" "$BASE/Library/Caches/CocoaPods"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "ReactNative" "$BASE/Library/Caches/ReactNative"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Gradle caches" "$BASE/.gradle/caches"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "npm _cacache" "$BASE/.npm/_cacache"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Yarn cache" "$BASE/Library/Caches/Yarn"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Xcode DerivedData" "$BASE/Library/Developer/Xcode/DerivedData"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Homebrew cache" "$BASE/Library/Caches/Homebrew"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "node-gyp" "$BASE/Library/Caches/node-gyp"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Cursor ShipIt" "$BASE/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Trae CN cache" "$BASE/Library/Caches/Trae CN"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Trae ShipIt" "$BASE/Library/Caches/cn.trae.app.ShipIt"
    printf '%s\t%s\t%s\t%s\n' T1 safe_to_clean "Antigravity updater" "$BASE/Library/Caches/antigravity-updater"
    printf '%s\t%s\t%s\t%s\n' T2 ask_first "MuMu / Nemu" "$BASE/Library/Application Support/com.netease.mumu.nemux"
    printf '%s\t%s\t%s\t%s\n' T2 ask_first "Nemu" "$BASE/Library/Nemu"
    printf '%s\t%s\t%s\t%s\n' T2 ask_first "Nox" "$BASE/Library/Application Support/NoxAppPlayer"
    printf '%s\t%s\t%s\t%s\n' T2 ask_first "CoreSimulator" "$BASE/Library/Developer/CoreSimulator"
    printf '%s\t%s\t%s\t%s\n' T2 ask_first "Android SDK" "$BASE/Library/Android/sdk"
    printf '%s\t%s\t%s\t%s\n' T4 forbidden "WeChat sandbox" "$BASE/Library/Containers/com.tencent.xinWeChat"
    printf '%s\t%s\t%s\t%s\n' T4 forbidden "WeCom sandbox" "$BASE/Library/Containers/com.tencent.WeWorkMac"
    printf '%s\t%s\t%s\t%s\n' T4 forbidden "Parallels VMs" "$BASE/Library/Parallels"
    printf '%s\t%s\t%s\t%s\n' T4 forbidden "Parallels home" "$BASE/Parallels"
  } > "$tmp.catalog"

  # Measure existing catalog paths → findings TSV: tier action label path bytes
  : > "$tmp.findings"
  while IFS=$'\t' read -r tier action label path; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then
      bytes=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
      [ -n "$bytes" ] || bytes=0
      printf '%s\t%s\t%s\t%s\t%s\n' "$tier" "$action" "$label" "$path" "$bytes" >> "$tmp.findings"
    fi
  done < "$tmp.catalog"

  # Top containers not already listed (heuristic T3/T4)
  if [ "$MODE" = full ] && [ -d "$BASE/Library/Containers" ]; then
    du -sk "$BASE/Library/Containers"/* 2>/dev/null | sort -nr | head -12 | while read -r kb path; do
      base=$(basename "$path")
      case "$base" in
        com.tencent.xinWeChat|com.tencent.WeWorkMac|com.tencent.wwmapp) continue ;;
      esac
      # skip if tiny
      [ "${kb:-0}" -lt 102400 ] && continue   # <100MB
      bytes=$((kb * 1024))
      printf '%s\t%s\t%s\t%s\t%s\n' "T3" "ask_first" "Container $base" "$path" "$bytes"
    done >> "$tmp.findings"
  fi

  # eas-build temps
  shopt -s nullglob 2>/dev/null || true
  for p in /tmp/eas-build-*; do
    [ -e "$p" ] || continue
    bytes=$(du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}')
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "EAS tmp" "$p" "${bytes:-0}" >> "$tmp.findings"
  done

  # Disk via df -k (portable-ish on macOS)
  df_root=$(df -k / | awk 'NR==2{printf "{\"filesystem\":%s,\"size_kib\":%s,\"used_kib\":%s,\"avail_kib\":%s,\"capacity\":\"%s\"}", "\""$1"\"", $2, $3, $4, $5}')
  df_data="{}"
  if df -k /System/Volumes/Data >/dev/null 2>&1; then
    df_data=$(df -k /System/Volumes/Data | awk 'NR==2{printf "{\"filesystem\":%s,\"size_kib\":%s,\"used_kib\":%s,\"avail_kib\":%s,\"capacity\":\"%s\"}", "\""$1"\"", $2, $3, $4, $5}')
  fi

  export APFS_SPA_FINDINGS="$tmp.findings"
  export APFS_SPA_DF_ROOT="$df_root"
  export APFS_SPA_DF_DATA="$df_data"
  export APFS_SPA_MODE="$MODE"
  export APFS_SPA_BASE="$BASE"

  python3 - <<'PY'
import json, os, time, sys

findings_path = os.environ["APFS_SPA_FINDINGS"]
findings = []
sums = {"T1": 0, "T2": 0, "T3": 0, "T4": 0}

with open(findings_path, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        tier, action, label, path, bytes_s = parts[0], parts[1], parts[2], parts[3], parts[4]
        try:
            b = int(bytes_s)
        except ValueError:
            b = 0
        findings.append({
            "tier": tier,
            "action": action,
            "label": label,
            "path": path,
            "bytes": b,
        })
        if tier in sums:
            sums[tier] += b

findings.sort(key=lambda x: x["bytes"], reverse=True)

def hum(n):
    for unit, div in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if n >= div:
            return f"{n/div:.1f}{unit}"
    return f"{n}B"

for item in findings:
    item["human"] = hum(item["bytes"])

report = {
    "skill": "mac-storage-governance",
    "brand": "apfs-spa",
    "schema_version": 1,
    "scanned_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "mode": os.environ.get("APFS_SPA_MODE", "full"),
    "home": os.environ.get("APFS_SPA_BASE", ""),
    "read_only": True,
    "disk": {
        "root": json.loads(os.environ["APFS_SPA_DF_ROOT"]),
        "data": json.loads(os.environ["APFS_SPA_DF_DATA"]),
    },
    "summary": {
        "t1_bytes": sums["T1"],
        "t2_bytes": sums["T2"],
        "t3_bytes": sums["T3"],
        "t4_bytes": sums["T4"],
        "t1_human": hum(sums["T1"]),
        "t2_human": hum(sums["T2"]),
        "t3_human": hum(sums["T3"]),
        "t4_human": hum(sums["T4"]),
        "finding_count": len(findings),
    },
    "findings": findings,
    "agent_hint": "Present findings as a table (path/human/tier/action). Only clean tiers the user confirms. Prefer clean.sh --tier 1 --yes (quarantine).",
}

text = json.dumps(report, ensure_ascii=False, indent=2)
out = os.environ.get("APFS_SPA_OUT", "")
if out:
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text)
        fh.write("\n")
print(text)
PY

  rm -f "$tmp" "$tmp.catalog" "$tmp.findings"
}

if [ "$JSON" = 1 ]; then
  if [ -n "$OUT" ]; then
    export APFS_SPA_OUT="$OUT"
  fi
  json_scan
  exit 0
fi

if [ "$MODE" = quick ]; then
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
bold "Tip: ./scan.sh --json  for machine-readable harness report."
