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

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
  # TSV: tier \t action \t label \t path \t kind
  # kind: cache|emulator|sdk|container|vm|tmp
  {
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "CocoaPods" "$BASE/Library/Caches/CocoaPods" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "ReactNative" "$BASE/Library/Caches/ReactNative" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Gradle caches" "$BASE/.gradle/caches" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "npm _cacache" "$BASE/.npm/_cacache" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Yarn cache" "$BASE/Library/Caches/Yarn" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Xcode DerivedData" "$BASE/Library/Developer/Xcode/DerivedData" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Homebrew cache" "$BASE/Library/Caches/Homebrew" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "node-gyp" "$BASE/Library/Caches/node-gyp" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Cursor ShipIt" "$BASE/Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Trae CN cache" "$BASE/Library/Caches/Trae CN" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Trae ShipIt" "$BASE/Library/Caches/cn.trae.app.ShipIt" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "Antigravity updater" "$BASE/Library/Caches/antigravity-updater" cache
    printf '%s\t%s\t%s\t%s\t%s\n' T2 ask_first "MuMu / Nemu" "$BASE/Library/Application Support/com.netease.mumu.nemux" emulator
    printf '%s\t%s\t%s\t%s\t%s\n' T2 ask_first "Nemu" "$BASE/Library/Nemu" emulator
    printf '%s\t%s\t%s\t%s\t%s\n' T2 ask_first "Nox" "$BASE/Library/Application Support/NoxAppPlayer" emulator
    printf '%s\t%s\t%s\t%s\t%s\n' T2 ask_first "CoreSimulator" "$BASE/Library/Developer/CoreSimulator" emulator
    printf '%s\t%s\t%s\t%s\t%s\n' T2 ask_first "Android SDK" "$BASE/Library/Android/sdk" sdk
    printf '%s\t%s\t%s\t%s\t%s\n' T4 forbidden "WeChat sandbox" "$BASE/Library/Containers/com.tencent.xinWeChat" container
    printf '%s\t%s\t%s\t%s\t%s\n' T4 forbidden "WeCom sandbox" "$BASE/Library/Containers/com.tencent.WeWorkMac" container
    # Provisional T3 — enricher promotes to T4 when owner app still installed
    # (DingTalk: container id ≠ CFBundleIdentifier; see container_owner resolution)
    printf '%s\t%s\t%s\t%s\t%s\n' T3 ask_first "DingTalk sandbox" "$BASE/Library/Containers/5ZSL2CJU2T.com.dingtalk.mac" container
    printf '%s\t%s\t%s\t%s\t%s\n' T3 ask_first "DingTalk live" "$BASE/Library/Containers/5ZSL2CJU2T.com.dingtalk.mac.tblive" container
    printf '%s\t%s\t%s\t%s\t%s\n' T4 forbidden "Parallels VMs" "$BASE/Library/Parallels" vm
    printf '%s\t%s\t%s\t%s\t%s\n' T4 forbidden "Parallels home" "$BASE/Parallels" vm
  } > "$tmp.catalog"

  : > "$tmp.findings"
  while IFS=$'\t' read -r tier action label path kind; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ]; then
      bytes=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')
      [ -n "$bytes" ] || bytes=0
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tier" "$action" "$label" "$path" "$bytes" "$kind" >> "$tmp.findings"
    fi
  done < "$tmp.catalog"

  # Top containers not already listed
  if [ "$MODE" = full ] && [ -d "$BASE/Library/Containers" ]; then
    du -sk "$BASE/Library/Containers"/* 2>/dev/null | sort -nr | head -12 | while read -r kb path; do
      base=$(basename "$path")
      case "$base" in
        com.tencent.xinWeChat|com.tencent.WeWorkMac|com.tencent.wwmapp|5ZSL2CJU2T.com.dingtalk.mac|5ZSL2CJU2T.com.dingtalk.mac.tblive) continue ;;
      esac
      [ "${kb:-0}" -lt 102400 ] && continue
      bytes=$((kb * 1024))
      # provisional T3; enricher may promote to T4 if app still installed/in use
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "T3" "ask_first" "Container $base" "$path" "$bytes" container
    done >> "$tmp.findings"
  fi

  shopt -s nullglob 2>/dev/null || true
  for p in /tmp/eas-build-*; do
    [ -e "$p" ] || continue
    bytes=$(du -sk "$p" 2>/dev/null | awk '{print $1 * 1024}')
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' T1 safe_to_clean "EAS tmp" "$p" "${bytes:-0}" tmp
  done >> "$tmp.findings"

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
  export APFS_SPA_SKIP_LSOF="${APFS_SPA_SKIP_LSOF:-0}"
  export APFS_SPA_BUNDLE_MAP="${APFS_SPA_BUNDLE_MAP:-$ROOT/scripts/bundle-apps.json}"

  python3 - <<'PY'
import json, os, re, time, subprocess, plistlib
from datetime import datetime, timezone, timedelta
from pathlib import Path

FINDINGS_PATH = os.environ["APFS_SPA_FINDINGS"]
SKIP_LSOF = os.environ.get("APFS_SPA_SKIP_LSOF", "0") == "1"
RECENT_DAYS = 90
# Apple Team ID prefix on Containers / Group Containers: 10 alnum + '.'
TEAM_ID_PREFIX = re.compile(r"^[A-Z0-9]{10}\.")
BUNDLE_MAP_PATH = Path(os.environ.get("APFS_SPA_BUNDLE_MAP", ""))

def run(cmd, timeout=5):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or ""), (r.stderr or "")
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return 1, "", ""

def hum(n):
    for unit, div in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if n >= div:
            return f"{n/div:.1f}{unit}"
    return f"{n}B"

def parse_mdls_date(s):
    s = (s or "").strip()
    if not s or s == "(null)":
        return None
    # mdls: 2026-08-03 09:25:38 +0000
    for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            continue
    return None

def mdls_keys(path, keys):
    if not path or not Path(path).exists():
        return {}
    cmd = ["mdls"] + [x for k in keys for x in ("-name", k)] + [path]
    code, out, _ = run(cmd, timeout=8)
    result = {}
    if code != 0:
        return result
    for line in out.splitlines():
        if " = " not in line:
            continue
        k, v = line.split(" = ", 1)
        k, v = k.strip(), v.strip()
        if v == "(null)":
            result[k] = None
        elif v.isdigit():
            result[k] = int(v)
        else:
            result[k] = v.strip('"')
    return result

def path_timestamps(path):
    try:
        st = os.stat(path, follow_symlinks=False)
        def fmt(ts):
            return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")
        return {
            "mtime": fmt(st.st_mtime),
            "ctime": fmt(st.st_ctime),
            "birth": fmt(getattr(st, "st_birthtime", st.st_ctime)),
            "note": "path timestamps are weak signals; prefer owner_app last_used / open_now",
        }
    except OSError:
        return {}

def bundle_id_from_container(path):
    p = Path(path)
    parts = p.parts
    try:
        i = parts.index("Containers")
        return parts[i + 1]
    except (ValueError, IndexError):
        return None

def strip_team_id(cid):
    if not cid:
        return cid
    return TEAM_ID_PREFIX.sub("", cid, count=1)

def load_bundle_map():
    try:
        if BUNDLE_MAP_PATH.is_file():
            return json.loads(BUNDLE_MAP_PATH.read_text(encoding="utf-8"))
    except Exception:
        pass
    return {}

def alias_cf_bundles(container_id):
    """Known CFBundleIdentifier aliases when container folder ≠ Info.plist id."""
    m = load_bundle_map()
    out = []
    for key in (container_id, strip_team_id(container_id)):
        if not key:
            continue
        info = m.get(key) or {}
        for b in info.get("owner_cf_bundles") or []:
            if b and b not in out:
                out.append(b)
    return out

def container_dir(path):
    """Resolve .../Containers/<id> from a container path."""
    p = Path(path)
    parts = list(p.parts)
    try:
        i = parts.index("Containers")
        return Path(*parts[: i + 2])
    except (ValueError, IndexError):
        return p

def app_from_container_metadata(container_path):
    """
    Authoritative owner path from containermanagerd metadata.
    DingTalk etc.: folder id / signing id ≠ CFBundleIdentifier in Info.plist,
    but Parameters.application_bundle still points at the .app.
    """
    cdir = container_dir(container_path)
    meta = cdir / ".com.apple.containermanagerd.metadata.plist"
    if not meta.is_file():
        return None, None
    try:
        with open(meta, "rb") as fh:
            pl = plistlib.load(fh)
        info = pl.get("MCMMetadataInfo") or {}
        params = (info.get("SandboxProfileDataValidationInfo") or {}).get("Parameters") or {}
        app = params.get("application_bundle")
        meta_bid = params.get("application_bundle_id")
        if app and Path(app).exists():
            return str(Path(app)), meta_bid
    except Exception:
        pass
    return None, None

def find_app_by_cf_bundle(bundle_id):
    if not bundle_id:
        return None
    code, out, _ = run(
        ["mdfind", f"kMDItemCFBundleIdentifier == '{bundle_id}'"],
        timeout=10,
    )
    for line in out.splitlines():
        line = line.strip()
        if line.endswith(".app") and Path(line).exists():
            return line
    # Fallback: scan common app dirs (+ BASE/Applications for selftest)
    roots = [
        Path("/Applications"),
        Path.home() / "Applications",
        Path(os.environ.get("APFS_SPA_BASE", "")) / "Applications",
    ]
    for root in roots:
        if not root.is_dir():
            continue
        for info in root.glob("*.app/Contents/Info.plist"):
            try:
                with open(info, "rb") as fh:
                    pl = plistlib.load(fh)
                if pl.get("CFBundleIdentifier") == bundle_id:
                    return str(info.parent.parent)
            except Exception:
                continue
    return None

def find_app_for_bundle(bundle_id, container_path=None):
    """
    Resolve installed owner .app for a Containers/<id> folder.
    Order: containermanagerd metadata → CFBundleIdentifier candidates
    (exact folder, Team-ID-stripped, bundle-apps.json aliases) via mdfind / Info.plist.
    Returns (app_path_or_None, how).
    """
    if container_path:
        app, _meta_bid = app_from_container_metadata(container_path)
        if app:
            return app, "container_metadata"
    candidates = []
    for c in (bundle_id, strip_team_id(bundle_id), *alias_cf_bundles(bundle_id)):
        if c and c not in candidates:
            candidates.append(c)
    for cand in candidates:
        app = find_app_by_cf_bundle(cand)
        if app:
            if cand == bundle_id:
                how = "cf_bundle"
            elif cand == strip_team_id(bundle_id):
                how = "cf_bundle_stripped_team_id"
            else:
                how = "cf_bundle_alias"
            return app, how
    return None, None

def app_executable(app_path):
    info = Path(app_path) / "Contents" / "Info.plist"
    try:
        with open(info, "rb") as fh:
            pl = plistlib.load(fh)
        return pl.get("CFBundleExecutable")
    except Exception:
        return None

def process_holding_path(path, exec_name=None):
    holders = []
    if SKIP_LSOF:
        # cheap: pgrep by executable name only
        if exec_name:
            code, out, _ = run(["pgrep", "-lf", exec_name], timeout=3)
            for line in out.splitlines()[:5]:
                holders.append(line.strip())
        return holders
    # lsof on the directory node (cwd / open handles); timeout + head
    code, out, _ = run(["lsof", path], timeout=4)
    seen = set()
    for line in out.splitlines()[1:]:
        cols = line.split()
        if len(cols) < 2:
            continue
        key = f"{cols[0]}:{cols[1]}"
        if key in seen:
            continue
        seen.add(key)
        holders.append(f"{cols[0]}(pid {cols[1]})")
        if len(holders) >= 5:
            break
    if not holders and exec_name:
        code, out, _ = run(["pgrep", "-lf", exec_name], timeout=3)
        for line in out.splitlines()[:3]:
            holders.append(line.strip())
    return holders

def deps_for(kind, label, owner_app, bundle_id):
    if kind == "cache" or kind == "tmp":
        return {
            "kind": kind,
            "upstream": ["build toolchain / package manager"],
            "downstream": ["next build will re-download"],
            "regen": True,
        }
    if kind == "sdk":
        return {
            "kind": "sdk",
            "upstream": ["Android Studio / cmdline-tools"],
            "downstream": ["Android/RN native builds referencing ANDROID_HOME or sdk.dir"],
            "regen": False,
        }
    if kind == "emulator":
        return {
            "kind": "emulator",
            "upstream": ["Xcode / emulator apps"],
            "downstream": ["iOS/Android local runs"],
            "regen": False,
        }
    if kind == "vm":
        return {
            "kind": "vm",
            "upstream": ["Parallels Desktop"],
            "downstream": ["guest OS disk images"],
            "regen": False,
        }
    # container
    up = []
    if owner_app:
        up.append(owner_app)
    elif bundle_id:
        up.append(bundle_id)
    return {
        "kind": "app_sandbox",
        "upstream": up or ["unknown app"],
        "downstream": ["app user data / cache inside sandbox"],
        "regen": False,
        "bundle_id": bundle_id,
    }

def enrich(item):
    path = item["path"]
    kind = item.pop("kind", "unknown")
    tier0, action0 = item["tier"], item["action"]
    reasons = []

    usage = {
        "open_now": False,
        "holders": [],
        "owner_app": None,
        "owner_installed": False,
        "owner_last_used": None,
        "owner_use_count": None,
        "path_times": path_timestamps(path),
    }
    bundle_id = None
    exec_name = None

    if kind == "container" or "/Containers/" in path:
        kind = "container"
        bundle_id = bundle_id_from_container(path)
        app, how = find_app_for_bundle(bundle_id, container_path=path)
        if app:
            usage["owner_app"] = app
            usage["owner_installed"] = True
            usage["owner_match"] = how
            meta = mdls_keys(app, ["kMDItemLastUsedDate", "kMDItemUseCount"])
            usage["owner_last_used"] = meta.get("kMDItemLastUsedDate")
            usage["owner_use_count"] = meta.get("kMDItemUseCount")
            exec_name = app_executable(app)
        holders = process_holding_path(path, exec_name)
        usage["holders"] = holders
        usage["open_now"] = bool(holders)
    elif kind == "sdk":
        # Android Studio as soft owner
        for cand in ("/Applications/Android Studio.app", str(Path.home() / "Applications/Android Studio.app")):
            if Path(cand).exists():
                usage["owner_app"] = cand
                usage["owner_installed"] = True
                meta = mdls_keys(cand, ["kMDItemLastUsedDate", "kMDItemUseCount"])
                usage["owner_last_used"] = meta.get("kMDItemLastUsedDate")
                usage["owner_use_count"] = meta.get("kMDItemUseCount")
                break
        holders = process_holding_path(path)
        usage["holders"] = holders
        usage["open_now"] = bool(holders)
    else:
        holders = process_holding_path(path)
        usage["holders"] = holders
        usage["open_now"] = bool(holders)

    # Reclassify
    tier, action, confidence = tier0, action0, "medium"
    if usage["open_now"]:
        tier, action, confidence = "T4", "forbidden", "high"
        reasons.append("open_now: process holds path")
    elif kind == "container":
        if usage["owner_installed"]:
            last = parse_mdls_date(usage.get("owner_last_used") or "")
            recent = False
            if last is not None:
                # normalize tz
                if last.tzinfo is None:
                    last = last.replace(tzinfo=timezone.utc)
                recent = last >= datetime.now(timezone.utc) - timedelta(days=RECENT_DAYS)
            used = bool(usage.get("owner_use_count")) or recent or last is not None
            if used or recent:
                tier, action, confidence = "T4", "forbidden", "high"
                reasons.append("owner_app installed and has use evidence")
            else:
                tier, action, confidence = "T4", "ask_first", "medium"
                reasons.append("owner_app installed but no clear recent use")
        else:
            tier, action, confidence = "T3", "ask_first", "medium"
            reasons.append("no owner_app found — possible leftover sandbox")
    elif tier0 == "T1":
        confidence = "high"
        reasons.append("catalog regenerable cache")
    elif tier0 == "T2":
        confidence = "medium"
        reasons.append("large toolchain/emulator — confirm unused")
    elif tier0 == "T4":
        confidence = "high"
        reasons.append("catalog red-line path")

    item["tier"] = tier
    item["action"] = action
    item["kind"] = kind
    item["usage"] = usage
    item["deps"] = deps_for(kind, item["label"], usage.get("owner_app"), bundle_id)
    item["confidence"] = confidence
    item["classify_reasons"] = reasons
    item["tier_original"] = tier0
    return item

# Load findings
raw = []
with open(FINDINGS_PATH, encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) < 6:
            # backward: tier action label path bytes
            if len(parts) < 5:
                continue
            tier, action, label, path, bytes_s = parts[:5]
            kind = "unknown"
        else:
            tier, action, label, path, bytes_s, kind = parts[:6]
        try:
            b = int(bytes_s)
        except ValueError:
            b = 0
        raw.append({
            "tier": tier,
            "action": action,
            "label": label,
            "path": path,
            "bytes": b,
            "kind": kind,
        })

findings = [enrich(x) for x in raw]
findings.sort(key=lambda x: x["bytes"], reverse=True)
for item in findings:
    item["human"] = hum(item["bytes"])

sums = {"T1": 0, "T2": 0, "T3": 0, "T4": 0}
for item in findings:
    if item["tier"] in sums:
        sums[item["tier"]] += item["bytes"]

report = {
    "skill": "mac-storage-governance",
    "brand": "apfs-spa",
    "schema_version": 2,
    "scanned_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "mode": os.environ.get("APFS_SPA_MODE", "full"),
    "home": os.environ.get("APFS_SPA_BASE", ""),
    "read_only": True,
    "evidence_notes": [
        "owner_app LastUsedDate/use_count beat path mtime for usage trajectory",
        "open_now from lsof/pgrep forces T4 forbidden",
        "container owner: prefer containermanagerd application_bundle; then CFBundleIdentifier (exact / Team-ID-stripped / bundle-apps.json aliases)",
        "container without installed owner_app stays T3 ask_first (orphan candidate)",
        "deps are ownership/regen templates, not full call graphs",
    ],
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
        "promoted_to_t4": sum(1 for x in findings if x.get("tier_original") == "T3" and x["tier"] == "T4"),
        "open_now_count": sum(1 for x in findings if x.get("usage", {}).get("open_now")),
    },
    "findings": findings,
    "agent_hint": "Show table: human/tier/action/confidence/open_now/owner_app/reasons. Never auto-clean ask_first/forbidden. Prefer clean.sh --tier 1 --yes.",
}

text = json.dumps(report, ensure_ascii=False, indent=2)
out = os.environ.get("APFS_SPA_OUT", "")
if out:
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")
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
bold "Tip: ./scan.sh --json  for machine-readable harness report (schema v2 + usage/deps)."
