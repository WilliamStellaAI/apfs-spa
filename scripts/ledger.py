#!/usr/bin/env python3
"""
apfs-spa governance ledger — SQLite table of snapshots, actions, and user locks.

Locks are enforced by clean.sh (not by Agent reading markdown).
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any, Optional

SCHEMA = """
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  report_path TEXT,
  archive_path TEXT,
  avail_h TEXT,
  used_h TEXT,
  size_h TEXT,
  capacity TEXT,
  finding_count INTEGER,
  summary_json TEXT NOT NULL DEFAULT '{}',
  findings_json TEXT NOT NULL DEFAULT '[]'
);

CREATE TABLE IF NOT EXISTS actions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  kind TEXT NOT NULL,
  tier INTEGER,
  mode TEXT,
  stamp TEXT,
  paths_json TEXT NOT NULL DEFAULT '[]',
  result TEXT NOT NULL DEFAULT 'ok',
  detail_json TEXT NOT NULL DEFAULT '{}',
  avail_before TEXT,
  avail_after TEXT,
  snapshot_id INTEGER,
  FOREIGN KEY(snapshot_id) REFERENCES snapshots(id)
);

CREATE TABLE IF NOT EXISTS locks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target TEXT NOT NULL,
  scope TEXT NOT NULL DEFAULT 'forbid_clean',
  reason TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'user',
  active INTEGER NOT NULL DEFAULT 1,
  UNIQUE(target_type, target, scope)
);

CREATE INDEX IF NOT EXISTS idx_locks_active ON locks(active);
CREATE INDEX IF NOT EXISTS idx_actions_kind ON actions(kind);
CREATE INDEX IF NOT EXISTS idx_snapshots_created ON snapshots(created_at);
"""

DEFAULT_SYSTEM_LOCKS = [
    ("bundle", "com.tencent.xinWeChat", "forbid_clean", "系统默认红线：微信沙盒", "system"),
    ("bundle", "com.tencent.WeWorkMac", "forbid_clean", "系统默认红线：企业微信沙盒", "system"),
    ("bundle", "com.tencent.wwmapp", "forbid_clean", "系统默认红线：企业微信沙盒", "system"),
    ("prefix", "Documents", "forbid_clean", "系统默认：用户文档目录禁止脚本清理", "system"),
]


def now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def default_db_path() -> Path:
    base = os.environ.get("APFS_SPA_HOME") or os.path.expanduser("~")
    override = os.environ.get("APFS_SPA_LEDGER")
    if override:
        return Path(override)
    return Path(base) / ".cache" / "apfs-spa" / "ledger.sqlite"


def archive_dir(db_path: Path) -> Path:
    return db_path.parent / "reports"


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(db_path))
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)
    ver = con.execute("SELECT value FROM meta WHERE key='schema_version'").fetchone()
    if not ver:
        con.execute(
            "INSERT INTO meta(key, value) VALUES('schema_version', ?)", ("1",)
        )
        seed_system_locks(con)
        con.commit()
    return con


def seed_system_locks(con: sqlite3.Connection) -> None:
    ts = now()
    for target_type, target, scope, reason, source in DEFAULT_SYSTEM_LOCKS:
        con.execute(
            """
            INSERT OR IGNORE INTO locks(created_at, updated_at, target_type, target, scope, reason, source, active)
            VALUES(?,?,?,?,?,?,?,1)
            """,
            (ts, ts, target_type, target, scope, reason, source),
        )


def kib_h(kib: Any) -> Optional[str]:
    if kib is None:
        return None
    b = int(kib) * 1024
    for u, n in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if b >= n:
            return f"{b / n:.1f}{u}"
    return f"{b}B"


def expand_target(target: str, home: str) -> str:
    t = target.strip()
    if t.startswith("~/"):
        return str(Path(home) / t[2:])
    if t == "~":
        return home
    return t


def path_bundle(path: str) -> Optional[str]:
    marker = "/Library/Containers/"
    if marker in path:
        rest = path.split(marker, 1)[1]
        return rest.split("/", 1)[0]
    return None


def matching_locks(con: sqlite3.Connection, path: str, home: str) -> list[sqlite3.Row]:
    path = str(Path(path).expanduser())
    try:
        path = str(Path(path).resolve())
    except Exception:
        pass
    rows = con.execute(
        "SELECT * FROM locks WHERE active=1 AND scope IN ('forbid_clean','forbid_purge')"
    ).fetchall()
    hits = []
    bundle = path_bundle(path)
    docs = str(Path(home) / "Documents")
    for r in rows:
        ttype, target = r["target_type"], r["target"]
        if ttype == "path":
            t = expand_target(target, home)
            try:
                t = str(Path(t).resolve())
            except Exception:
                pass
            if path == t or path.startswith(t.rstrip("/") + "/"):
                hits.append(r)
        elif ttype == "prefix":
            # relative to home, e.g. Documents or Library/Containers/foo
            pref = expand_target(target if target.startswith("~") else f"~/{target.lstrip('/')}", home)
            try:
                pref = str(Path(pref).resolve())
            except Exception:
                pass
            if path == pref or path.startswith(pref.rstrip("/") + "/"):
                hits.append(r)
        elif ttype == "bundle":
            if bundle and bundle == target:
                hits.append(r)
            cont = str(Path(home) / "Library" / "Containers" / target)
            if path == cont or path.startswith(cont + "/"):
                hits.append(r)
        elif ttype == "glob":
            # simple suffix/prefix * support
            import fnmatch

            pat = expand_target(target, home)
            if fnmatch.fnmatch(path, pat):
                hits.append(r)
    # Documents system lock via prefix already; keep docs helper unused unless needed
    _ = docs
    return hits


def cmd_init(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    con.close()
    print(Path(args.db))
    return 0


def cmd_lock(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    ts = now()
    target_type = args.type
    target = args.target
    scope = args.scope
    reason = args.reason or ""
    source = args.source or "user"
    con.execute(
        """
        INSERT INTO locks(created_at, updated_at, target_type, target, scope, reason, source, active)
        VALUES(?,?,?,?,?,?,?,1)
        ON CONFLICT(target_type, target, scope) DO UPDATE SET
          active=1, updated_at=excluded.updated_at, reason=excluded.reason, source=excluded.source
        """,
        (ts, ts, target_type, target, scope, reason, source),
    )
    con.execute(
        """
        INSERT INTO actions(created_at, kind, result, detail_json)
        VALUES(?,?,?,?)
        """,
        (
            ts,
            "lock",
            "ok",
            json.dumps(
                {"target_type": target_type, "target": target, "scope": scope, "reason": reason},
                ensure_ascii=False,
            ),
        ),
    )
    con.commit()
    print(f"locked {target_type}:{target} scope={scope}")
    return 0


def cmd_unlock(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    ts = now()
    if args.id:
        cur = con.execute(
            "UPDATE locks SET active=0, updated_at=? WHERE id=? AND active=1",
            (ts, args.id),
        )
    else:
        cur = con.execute(
            """
            UPDATE locks SET active=0, updated_at=?
            WHERE active=1 AND target_type=? AND target=? AND (? IS NULL OR scope=?)
            """,
            (ts, args.type, args.target, args.scope, args.scope),
        )
    if cur.rowcount == 0:
        print("no matching active lock", file=sys.stderr)
        return 1
    con.execute(
        """
        INSERT INTO actions(created_at, kind, result, detail_json)
        VALUES(?,?,?,?)
        """,
        (
            ts,
            "unlock",
            "ok",
            json.dumps(
                {"id": args.id, "target_type": args.type, "target": args.target, "scope": args.scope},
                ensure_ascii=False,
            ),
        ),
    )
    con.commit()
    print(f"unlocked ({cur.rowcount})")
    return 0


def cmd_list_locks(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    if args.all:
        rows = con.execute("SELECT * FROM locks ORDER BY active DESC, id").fetchall()
    else:
        rows = con.execute(
            "SELECT * FROM locks WHERE active=1 ORDER BY source, id"
        ).fetchall()
    if args.json:
        print(json.dumps([dict(r) for r in rows], ensure_ascii=False, indent=2))
        return 0
    if not rows:
        print("(no locks)")
        return 0
    print(f"{'id':>4}  {'act':3}  {'type':7}  {'scope':12}  {'source':6}  target  reason")
    for r in rows:
        print(
            f"{r['id']:4d}  {'Y' if r['active'] else 'N':3}  {r['target_type']:7}  {r['scope']:12}  {r['source']:6}  {r['target']}  {r['reason']}"
        )
    return 0


def cmd_assert_unlocked(args: argparse.Namespace) -> int:
    """Exit 0 if path may be cleaned; exit 3 if locked. Machine-readable for clean.sh."""
    con = connect(Path(args.db))
    home = os.environ.get("APFS_SPA_HOME") or os.path.expanduser("~")
    path = args.path
    hits = matching_locks(con, path, home)
    if args.mode == "purge":
        hits = [h for h in hits if h["scope"] in ("forbid_clean", "forbid_purge")]
    else:
        hits = [h for h in hits if h["scope"] == "forbid_clean" or h["scope"] == "forbid_purge"]
    if not hits:
        return 0
    # record refused attempt when --record
    if args.record:
        con.execute(
            """
            INSERT INTO actions(created_at, kind, result, paths_json, detail_json)
            VALUES(?,?,?,?,?)
            """,
            (
                now(),
                "refused",
                "locked",
                json.dumps([path], ensure_ascii=False),
                json.dumps(
                    {
                        "locks": [
                            {
                                "id": h["id"],
                                "target_type": h["target_type"],
                                "target": h["target"],
                                "reason": h["reason"],
                            }
                            for h in hits
                        ]
                    },
                    ensure_ascii=False,
                ),
            ),
        )
        con.commit()
    for h in hits:
        print(
            f"LOCKED id={h['id']} {h['target_type']}:{h['target']} scope={h['scope']} reason={h['reason']}",
            file=sys.stderr,
        )
    return 3


def cmd_record_snapshot(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    report_path = Path(args.report)
    rep = json.loads(report_path.read_text(encoding="utf-8"))
    data = (rep.get("disk") or {}).get("data") or (rep.get("disk") or {}).get("root") or {}
    summary = rep.get("summary") or {}
    findings = rep.get("findings") or []
    # compact findings for table (drop huge holders lists)
    compact = []
    for f in findings:
        u = f.get("usage") or {}
        compact.append(
            {
                "tier": f.get("tier"),
                "action": f.get("action"),
                "label": f.get("label"),
                "path": f.get("path"),
                "bytes": f.get("bytes"),
                "human": f.get("human"),
                "open_now": u.get("open_now"),
                "owner_last_used": u.get("owner_last_used"),
            }
        )
    arch_dir = archive_dir(Path(args.db))
    arch_dir.mkdir(parents=True, exist_ok=True)
    ts = now()
    cur = con.execute(
        """
        INSERT INTO snapshots(created_at, report_path, avail_h, used_h, size_h, capacity,
                              finding_count, summary_json, findings_json)
        VALUES(?,?,?,?,?,?,?,?,?)
        """,
        (
            rep.get("scanned_at") or ts,
            str(report_path.resolve()),
            kib_h(data.get("avail_kib")),
            kib_h(data.get("used_kib")),
            kib_h(data.get("size_kib")),
            data.get("capacity"),
            summary.get("finding_count") or len(findings),
            json.dumps(summary, ensure_ascii=False),
            json.dumps(compact, ensure_ascii=False),
        ),
    )
    snap_id = cur.lastrowid
    arch = arch_dir / f"snapshot-{snap_id}.json"
    shutil.copy2(report_path, arch)
    con.execute("UPDATE snapshots SET archive_path=? WHERE id=?", (str(arch), snap_id))
    con.execute(
        """
        INSERT INTO actions(created_at, kind, result, detail_json, snapshot_id, avail_before)
        VALUES(?,?,?,?,?,?)
        """,
        (
            ts,
            "scan",
            "ok",
            json.dumps({"report_path": str(report_path.resolve()), "archive": str(arch)}, ensure_ascii=False),
            snap_id,
            kib_h(data.get("avail_kib")),
        ),
    )
    con.commit()
    print(snap_id)
    return 0


def cmd_record_action(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    detail = {}
    if args.detail_json:
        detail = json.loads(args.detail_json)
    paths = []
    if args.paths:
        paths = [p for p in args.paths.split("\n") if p]
    con.execute(
        """
        INSERT INTO actions(created_at, kind, tier, mode, stamp, paths_json, result,
                            detail_json, avail_before, avail_after, snapshot_id)
        VALUES(?,?,?,?,?,?,?,?,?,?,?)
        """,
        (
            now(),
            args.kind,
            int(args.tier) if args.tier not in (None, "") else None,
            args.mode,
            args.stamp,
            json.dumps(paths, ensure_ascii=False),
            args.result or "ok",
            json.dumps(detail, ensure_ascii=False),
            args.avail_before,
            args.avail_after,
            int(args.snapshot_id) if args.snapshot_id else None,
        ),
    )
    con.commit()
    print(con.execute("SELECT last_insert_rowid()").fetchone()[0])
    return 0


def cmd_history(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    limit = args.limit or 30
    if args.snapshots:
        rows = con.execute(
            "SELECT id, created_at, avail_h, used_h, finding_count, archive_path FROM snapshots ORDER BY id DESC LIMIT ?",
            (limit,),
        ).fetchall()
        if args.json:
            print(json.dumps([dict(r) for r in rows], ensure_ascii=False, indent=2))
            return 0
        print(f"{'id':>4}  created_at                 avail    used     findings  archive")
        for r in rows:
            print(
                f"{r['id']:4d}  {r['created_at']:<24}  {r['avail_h'] or '-':<7}  {r['used_h'] or '-':<7}  {r['finding_count'] or 0:<8}  {r['archive_path'] or ''}"
            )
        return 0
    rows = con.execute(
        """
        SELECT id, created_at, kind, tier, mode, stamp, result, avail_before, avail_after, detail_json
        FROM actions ORDER BY id DESC LIMIT ?
        """,
        (limit,),
    ).fetchall()
    if args.json:
        print(json.dumps([dict(r) for r in rows], ensure_ascii=False, indent=2))
        return 0
    print(f"{'id':>4}  created_at                 kind       result   tier  detail")
    for r in rows:
        print(
            f"{r['id']:4d}  {r['created_at']:<24}  {r['kind']:<10} {r['result']:<7}  {str(r['tier'] or '-'):<4}  {(r['detail_json'] or '')[:80]}"
        )
    return 0


def cmd_show_snapshot(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    r = con.execute("SELECT * FROM snapshots WHERE id=?", (args.id,)).fetchone()
    if not r:
        print("not found", file=sys.stderr)
        return 1
    if args.json:
        d = dict(r)
        d["findings"] = json.loads(d.pop("findings_json") or "[]")
        d["summary"] = json.loads(d.pop("summary_json") or "{}")
        print(json.dumps(d, ensure_ascii=False, indent=2))
        return 0
    print(f"snapshot #{r['id']}  {r['created_at']}")
    print(f"  disk: size={r['size_h']} used={r['used_h']} avail={r['avail_h']} ({r['capacity']})")
    print(f"  findings: {r['finding_count']}")
    print(f"  archive: {r['archive_path']}")
    print(f"  report:  {r['report_path']}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    con = connect(Path(args.db))
    snaps = con.execute("SELECT COUNT(*) FROM snapshots").fetchone()[0]
    acts = con.execute("SELECT COUNT(*) FROM actions").fetchone()[0]
    locks = con.execute("SELECT COUNT(*) FROM locks WHERE active=1").fetchone()[0]
    last = con.execute(
        "SELECT id, created_at, avail_h, finding_count FROM snapshots ORDER BY id DESC LIMIT 1"
    ).fetchone()
    out = {
        "db": str(Path(args.db)),
        "snapshots": snaps,
        "actions": acts,
        "active_locks": locks,
        "last_snapshot": dict(last) if last else None,
    }
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        print(f"ledger: {out['db']}")
        print(f"snapshots: {snaps}  actions: {acts}  active_locks: {locks}")
        if last:
            print(
                f"last_snapshot: #{last['id']} {last['created_at']} avail={last['avail_h']} findings={last['finding_count']}"
            )
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="apfs-spa governance ledger")
    p.add_argument("--db", default=str(default_db_path()), help="sqlite path")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("init", help="create db + seed system locks")
    s.set_defaults(func=cmd_init)

    s = sub.add_parser("status", help="ledger summary")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_status)

    s = sub.add_parser("lock", help="add/activate a human lock")
    s.add_argument("--type", choices=["path", "bundle", "prefix", "glob"], required=True)
    s.add_argument("--target", required=True)
    s.add_argument("--scope", default="forbid_clean", choices=["forbid_clean", "forbid_purge", "ask_always"])
    s.add_argument("--reason", default="")
    s.add_argument("--source", default="user")
    s.set_defaults(func=cmd_lock)

    s = sub.add_parser("unlock", help="deactivate a lock")
    s.add_argument("--id", type=int)
    s.add_argument("--type", choices=["path", "bundle", "prefix", "glob"])
    s.add_argument("--target")
    s.add_argument("--scope")
    s.set_defaults(func=cmd_unlock)

    s = sub.add_parser("list-locks", help="list locks")
    s.add_argument("--all", action="store_true")
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_list_locks)

    s = sub.add_parser("assert-unlocked", help="exit 3 if path is locked (for clean.sh)")
    s.add_argument("--path", required=True)
    s.add_argument("--mode", default="quarantine", choices=["quarantine", "purge", "dry-run"])
    s.add_argument("--record", action="store_true", help="write refused action row")
    s.set_defaults(func=cmd_assert_unlocked)

    s = sub.add_parser("record-snapshot", help="archive a scan JSON into snapshots table")
    s.add_argument("--report", required=True)
    s.set_defaults(func=cmd_record_snapshot)

    s = sub.add_parser("record-action", help="append an action/result row")
    s.add_argument("--kind", required=True)
    s.add_argument("--tier")
    s.add_argument("--mode")
    s.add_argument("--stamp")
    s.add_argument("--paths", help="newline-separated paths")
    s.add_argument("--result", default="ok")
    s.add_argument("--detail-json")
    s.add_argument("--avail-before")
    s.add_argument("--avail-after")
    s.add_argument("--snapshot-id")
    s.set_defaults(func=cmd_record_action)

    s = sub.add_parser("history", help="list actions or snapshots")
    s.add_argument("--snapshots", action="store_true")
    s.add_argument("--limit", type=int, default=30)
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_history)

    s = sub.add_parser("show-snapshot", help="show one snapshot")
    s.add_argument("--id", type=int, required=True)
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_show_snapshot)

    return p


def main(argv: Optional[list[str]] = None) -> int:
    # Python 3.8 compat: subparsers required=True needs 3.7+ ok
    p = build_parser()
    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
