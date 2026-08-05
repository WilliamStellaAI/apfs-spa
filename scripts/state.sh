#!/usr/bin/env bash
#
# state.sh — cross-session state machine for apfs-spa
# 跨会话状态：记住上次扫到哪、画了哪张图、隔了哪次、你点过什么。
#
# Usage:
#   ./scripts/state.sh status [--json]
#   ./scripts/state.sh resume-hint
#   ./scripts/state.sh reset
#   ./scripts/state.sh path
#   ./scripts/state.sh record-scan --report /path/to/report.json
#   ./scripts/state.sh record-canvas --path /path/to/*.canvas.tsx
#   ./scripts/state.sh record-decision --approve-tier 1
#   ./scripts/state.sh record-decision --note "先不动微信"
#   ./scripts/state.sh record-decision --skip-path "~/Library/..."
#   ./scripts/state.sh record-clean --tier 1 --mode quarantine --stamp STAMP \
#       --avail-before 70G --avail-after 75G
#   ./scripts/state.sh record-verify --avail 75G
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${APFS_SPA_HOME:-$HOME}"
export APFS_SPA_STATE="${APFS_SPA_STATE:-$BASE/.cache/apfs-spa/state.json}"

exec python3 - "$ROOT" "$@" <<'PY'
import json, os, socket, sys, time
from pathlib import Path

ROOT = Path(sys.argv[1])
argv = sys.argv[2:]
STATE_PATH = Path(os.environ["APFS_SPA_STATE"])
STATE_PATH.parent.mkdir(parents=True, exist_ok=True)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def kib_h(k):
    if k is None:
        return None
    b = int(k) * 1024
    for u, n in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if b >= n:
            return f"{b / n:.1f}{u}"
    return f"{b}B"


def empty():
    return {
        "schema_version": 1,
        "skill": "mac-storage-governance",
        "brand": "apfs-spa",
        "updated_at": now(),
        "phase": "idle",
        "host": {
            "hostname": socket.gethostname(),
            "home": os.environ.get("APFS_SPA_HOME") or os.path.expanduser("~"),
        },
        "last_scan": None,
        "last_canvas": None,
        "decisions": [],
        "cleans": [],
        "history": [],
    }


def load():
    if not STATE_PATH.exists():
        return empty()
    return json.loads(STATE_PATH.read_text(encoding="utf-8"))


def save(state):
    state["updated_at"] = now()
    state.setdefault("host", {})
    state["host"]["hostname"] = socket.gethostname()
    state["host"]["home"] = os.environ.get("APFS_SPA_HOME") or os.path.expanduser("~")
    hist = state.setdefault("history", [])
    state["history"] = hist[-50:]
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return STATE_PATH


def push_hist(state, event, detail):
    state.setdefault("history", []).append({"at": now(), "event": event, "detail": detail})


def usage():
    text = (ROOT / "scripts" / "state.sh").read_text(encoding="utf-8")
    lines = []
    for line in text.splitlines()[1:]:
        if line.startswith("#") or line.strip() == "":
            lines.append(line)
        else:
            break
    print("\n".join(lines))


def cmd_status(args):
    st = load()
    if args and args[0] == "--json":
        print(json.dumps(st, ensure_ascii=False, indent=2))
        return
    print(f"state: {STATE_PATH}")
    print(f"phase: {st.get('phase')}")
    print(f"updated: {st.get('updated_at')}")
    ls = st.get("last_scan") or {}
    if ls:
        disk = ls.get("disk") or {}
        print(
            f"last_scan: {ls.get('at')}  avail={disk.get('avail_h', '?')}  findings={ls.get('finding_count', '?')}"
        )
        print(f"  report: {ls.get('report_path')}")
    else:
        print("last_scan: (none)")
    lc = st.get("last_canvas") or {}
    if lc:
        print(f"last_canvas: {lc.get('at')}")
        print(f"  path: {lc.get('path')}")
    else:
        print("last_canvas: (none)")
    cleans = st.get("cleans") or []
    if cleans:
        c = cleans[-1]
        print(
            f"last_clean: tier={c.get('tier')} mode={c.get('mode')} stamp={c.get('stamp')}  {c.get('avail_before')} → {c.get('avail_after')}"
        )
    else:
        print("last_clean: (none)")
    print(f"decisions: {len(st.get('decisions') or [])}  history: {len(st.get('history') or [])}")


def cmd_resume_hint(_args):
    st = load()
    phase = st.get("phase") or "idle"
    ls = st.get("last_scan") or {}
    lc = st.get("last_canvas") or {}
    cleans = st.get("cleans") or []
    lines = [f"跨会话状态：phase={phase}"]
    if phase == "idle":
        lines.append(
            "尚未有扫描记录。建议：scan.sh --json → render-architecture-canvas.sh → 等用户确认。"
        )
    elif phase in ("scanned", "presented", "awaiting_confirm"):
        disk = ls.get("disk") or {}
        lines.append(
            f"上次扫描 {ls.get('at')}，当时还能用约 {disk.get('avail_h', '?')}，命中 {ls.get('finding_count', '?')} 项。"
        )
        if lc.get("path"):
            lines.append(f"已有架构图：{lc['path']} — 可先打开给用户看，问要不要接着清。")
        else:
            lines.append("有扫描无架构图：用 render-architecture-canvas.sh --report <上次报告> 重建。")
        lines.append("不要默认重复清已处理项；先 status / 问用户。")
    elif phase == "cleaned":
        c = cleans[-1] if cleans else {}
        lines.append(
            f"上次已清理 tier={c.get('tier')} mode={c.get('mode')} stamp={c.get('stamp')}。"
        )
        lines.append(
            f"空间 {c.get('avail_before')} → {c.get('avail_after')}。建议 df 验收后 record-verify，或问是否继续下一批。"
        )
    elif phase == "verified":
        lines.append(
            "上次治理已验收。若磁盘又紧，重新 scan；若要回滚，用 clean.sh --list-quarantine / --restore。"
        )
    else:
        lines.append(f"未知 phase={phase}，建议 state.sh status --json 人工查看。")
    print("\n".join(lines))


def parse_kv(args):
    out = {}
    i = 0
    while i < len(args):
        k = args[i]
        if not k.startswith("--"):
            raise SystemExit(f"unknown: {k}")
        if i + 1 >= len(args):
            raise SystemExit(f"missing value for {k}")
        out[k[2:].replace("-", "_")] = args[i + 1]
        i += 2
    return out


def abs_path(p):
    return str(Path(p).expanduser().resolve())


def cmd_record_scan(args):
    kv = parse_kv(args)
    report = kv.get("report")
    if not report or not Path(report).exists():
        raise SystemExit("need --report FILE")
    report_path = abs_path(report)
    rep = json.loads(Path(report_path).read_text(encoding="utf-8"))
    data = (rep.get("disk") or {}).get("data") or (rep.get("disk") or {}).get("root") or {}
    summary = rep.get("summary") or {}
    st = load()
    st["last_scan"] = {
        "at": rep.get("scanned_at") or now(),
        "report_path": report_path,
        "disk": {
            "avail_h": kib_h(data.get("avail_kib")),
            "used_h": kib_h(data.get("used_kib")),
            "size_h": kib_h(data.get("size_kib")),
            "capacity": data.get("capacity"),
        },
        "finding_count": summary.get("finding_count"),
        "summary": {
            "t1_human": summary.get("t1_human"),
            "t2_human": summary.get("t2_human"),
            "t3_human": summary.get("t3_human"),
            "t4_human": summary.get("t4_human"),
            "open_now_count": summary.get("open_now_count"),
        },
    }
    st["phase"] = "scanned"
    push_hist(st, "scan", {"report_path": report_path, "finding_count": summary.get("finding_count")})
    save(st)
    print(f"recorded scan → {STATE_PATH}")


def cmd_record_canvas(args):
    kv = parse_kv(args)
    path = kv.get("path")
    if not path:
        raise SystemExit("need --path FILE")
    p = abs_path(path) if Path(path).parent.exists() else path
    st = load()
    st["last_canvas"] = {"at": now(), "path": p}
    st["phase"] = "awaiting_confirm"
    push_hist(st, "canvas", {"path": p})
    save(st)
    print(f"recorded canvas → {STATE_PATH}")


def cmd_record_decision(args):
    kv = parse_kv(args)
    st = load()
    dec = {"at": now()}
    if "approve_tier" in kv:
        dec["action"] = "approve_tier"
        dec["tier"] = int(kv["approve_tier"])
    elif "skip_path" in kv:
        dec["action"] = "skip_path"
        dec["path"] = kv["skip_path"]
    else:
        dec["action"] = "note"
        dec["note"] = kv.get("note") or ""
    st.setdefault("decisions", []).append(dec)
    st["decisions"] = st["decisions"][-30:]
    if st.get("phase") in ("scanned", "presented", "awaiting_confirm", "idle"):
        st["phase"] = "awaiting_confirm"
    push_hist(st, "decision", dec)
    save(st)
    print(f"recorded decision → {STATE_PATH}")


def cmd_record_clean(args):
    kv = parse_kv(args)
    entry = {
        "at": now(),
        "tier": int(kv["tier"]) if kv.get("tier") not in (None, "") else None,
        "mode": kv.get("mode"),
        "stamp": kv.get("stamp"),
        "avail_before": kv.get("avail_before"),
        "avail_after": kv.get("avail_after"),
    }
    st = load()
    st.setdefault("cleans", []).append(entry)
    st["cleans"] = st["cleans"][-30:]
    st["phase"] = "cleaned"
    push_hist(st, "clean", entry)
    save(st)
    print(f"recorded clean → {STATE_PATH}")


def cmd_record_verify(args):
    kv = parse_kv(args)
    st = load()
    st["phase"] = "verified"
    push_hist(st, "verify", {"avail": kv.get("avail")})
    save(st)
    print(f"recorded verify → {STATE_PATH}")


def main():
    if not argv:
        cmd_status([])
        return
    cmd = argv[0]
    args = argv[1:]
    if cmd in ("-h", "--help"):
        usage()
        return
    if cmd == "status":
        cmd_status(args)
    elif cmd == "resume-hint":
        cmd_resume_hint(args)
    elif cmd == "reset":
        save(empty())
        print(f"reset → {STATE_PATH}")
    elif cmd == "path":
        print(STATE_PATH)
    elif cmd == "record-scan":
        cmd_record_scan(args)
    elif cmd == "record-canvas":
        cmd_record_canvas(args)
    elif cmd == "record-decision":
        cmd_record_decision(args)
    elif cmd == "record-clean":
        cmd_record_clean(args)
    elif cmd == "record-verify":
        cmd_record_verify(args)
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        usage()
        raise SystemExit(1)


if __name__ == "__main__":
    main()
PY
