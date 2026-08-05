#!/usr/bin/env python3
"""
Cursor beforeShellExecution hook: block destructive shell when target hits ledger locks.

Input (stdin JSON): { "command": "...", ... }
Output (stdout JSON): { "permission": "allow"|"deny"|"ask", "user_message"?: "...", "agent_message"?: "..." }

Fail policy:
  - Non-destructive commands → allow (even if ledger missing)
  - Destructive + locked path → deny
  - Destructive + ledger unreadable → deny (fail closed on delete-like cmds)
  - Official apfs-spa scripts (clean/ledger/selftest/scan/render/state) → allow
    (clean.sh has its own ledger gate)
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

try:
    import ledger as ledger_mod
except Exception:
    ledger_mod = None  # type: ignore

# Official skill entrypoints — clean.sh enforces ledger itself
ALLOW_SCRIPT_RE = re.compile(
    r"(mac-storage-governance|apfs-spa).*/scripts/"
    r"(clean|ledger|selftest|scan|state|render-architecture-canvas|render_architecture_canvas|install|cursor-hook-shell-guard)"
    r"(\.sh|\.py)?\b"
)

DESTRUCTIVE_RE = re.compile(
    r"(?:^|[;&|]\s*|\n\s*)(?:sudo\s+)?(?:"
    r"rm\b|unlink\b|shred\b|srm\b|"
    r"gomi\b|"  # uncommon
    r"find\b[^|&;\n]*\s-(?:delete|exec\s+rm\b)"
    r")",
    re.IGNORECASE,
)

# mv can relocate locked trees; treat as destructive when present with paths
MV_RE = re.compile(r"(?:^|[;&|]\s*|\n\s*)(?:sudo\s+)?mv\b", re.IGNORECASE)

FLAG_ONLY = re.compile(r"^-[a-zA-Z0-9.-]+$")


def emit(permission: str, user_message: str = "", agent_message: str = "") -> int:
    out = {"permission": permission}
    if user_message:
        out["user_message"] = user_message
    if agent_message:
        out["agent_message"] = agent_message
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    return 0


def read_input() -> dict:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"command": raw.strip()}


def is_official_script(cmd: str) -> bool:
    return bool(ALLOW_SCRIPT_RE.search(cmd))


def is_destructive(cmd: str) -> bool:
    if DESTRUCTIVE_RE.search(cmd):
        return True
    if MV_RE.search(cmd):
        return True
    return False


def extract_paths(cmd: str) -> list[str]:
    """Best-effort path tokens from a shell command line."""
    paths: list[str] = []
    # Split on shell operators for simpler pieces
    chunks = re.split(r"[;&|\n]", cmd)
    for chunk in chunks:
        chunk = chunk.strip()
        if not chunk:
            continue
        try:
            tokens = shlex.split(chunk, posix=True)
        except ValueError:
            tokens = chunk.split()
        # drop leading env assignments
        while tokens and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[0]):
            tokens = tokens[1:]
        if not tokens:
            continue
        # skip command name and common wrappers
        i = 0
        while i < len(tokens) and tokens[i] in (
            "sudo",
            "command",
            "builtin",
            "nice",
            "nohup",
            "env",
            "time",
        ):
            i += 1
        if i < len(tokens):
            i += 1  # skip binary
        for t in tokens[i:]:
            if FLAG_ONLY.match(t):
                continue
            if t in ("--",):
                continue
            # likely path-ish
            if (
                t.startswith("/")
                or t.startswith("~")
                or t.startswith("./")
                or t.startswith("../")
                or "/" in t
            ):
                paths.append(t)
    # also catch bare ~/... via regex if shlex missed
    for m in re.finditer(r"(?:^|[\s\"'])(~?/?(?:Users|home|Library|Documents|var|tmp)/[^\s\"';]+)", cmd):
        paths.append(m.group(1).rstrip("\"';"))
    # dedupe preserve order
    seen = set()
    out = []
    for p in paths:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def expand_path(p: str, home: str) -> str:
    p = p.strip().strip("\"'")
    if p.startswith("~/"):
        p = str(Path(home) / p[2:])
    elif p == "~":
        p = home
    try:
        return str(Path(p).expanduser().resolve())
    except Exception:
        return str(Path(p).expanduser())


def check_locks(paths: list[str]) -> list[dict]:
    home = os.environ.get("APFS_SPA_HOME") or os.path.expanduser("~")
    db = Path(os.environ.get("APFS_SPA_LEDGER") or ledger_mod.default_db_path())
    if ledger_mod is None:
        raise RuntimeError("ledger module unavailable")
    if not db.exists():
        # init so system locks apply
        con = ledger_mod.connect(db)
        con.close()
    con = ledger_mod.connect(db)
    hits = []
    for p in paths:
        ep = expand_path(p, home)
        matched = ledger_mod.matching_locks(con, ep, home)
        for row in matched:
            hits.append(
                {
                    "path": ep,
                    "lock_id": row["id"],
                    "target_type": row["target_type"],
                    "target": row["target"],
                    "reason": row["reason"],
                    "scope": row["scope"],
                }
            )
        # also check unresolved token against matching_locks
        if ep != p:
            matched2 = ledger_mod.matching_locks(con, p, home)
            for row in matched2:
                hits.append(
                    {
                        "path": p,
                        "lock_id": row["id"],
                        "target_type": row["target_type"],
                        "target": row["target"],
                        "reason": row["reason"],
                        "scope": row["scope"],
                    }
                )
    con.close()
    # unique by lock_id+path
    uniq = []
    seen = set()
    for h in hits:
        key = (h["lock_id"], h["path"])
        if key not in seen:
            seen.add(key)
            uniq.append(h)
    return uniq


def main() -> int:
    data = read_input()
    cmd = (data.get("command") or data.get("command_line") or "").strip()
    if not cmd:
        return emit("allow")

    if is_official_script(cmd):
        return emit("allow")

    if not is_destructive(cmd):
        return emit("allow")

    paths = extract_paths(cmd)
    if not paths:
        # destructive but no parseable path — ask user (safer than silent allow)
        return emit(
            "ask",
            user_message="检测到可能的删除/移动命令，但无法解析路径。请确认是否继续。",
            agent_message="Destructive shell without clear paths; ask user. Prefer scripts/clean.sh.",
        )

    try:
        hits = check_locks(paths)
    except Exception as e:
        return emit(
            "deny",
            user_message=f"无法读取 apfs-spa 治理账本，已拦截可能的删除命令。({e})",
            agent_message="Ledger unreadable; fail-closed on destructive shell. Do not rm; use clean.sh after fixing ledger.",
        )

    if not hits:
        return emit("allow")

    # record refused in ledger
    try:
        db = Path(os.environ.get("APFS_SPA_LEDGER") or ledger_mod.default_db_path())
        con = ledger_mod.connect(db)
        con.execute(
            """
            INSERT INTO actions(created_at, kind, result, paths_json, detail_json)
            VALUES(?,?,?,?,?)
            """,
            (
                ledger_mod.now(),
                "hook_refused",
                "locked",
                json.dumps(paths, ensure_ascii=False),
                json.dumps({"command": cmd[:500], "hits": hits}, ensure_ascii=False),
            ),
        )
        con.commit()
        con.close()
    except Exception:
        pass

    lines = [f"- {h['path']} ← lock#{h['lock_id']} {h['target_type']}:{h['target']} ({h['reason']})" for h in hits[:6]]
    msg = "apfs-spa ledger 锁拦截了该 Shell 删除/移动：\n" + "\n".join(lines)
    msg += "\n解锁：./scripts/ledger.sh unlock --id <id>；清理请用 clean.sh（仍受锁约束）。"
    return emit(
        "deny",
        user_message=msg,
        agent_message="Shell blocked by ledger lock. Do not retry rm. Unlock only if user explicitly asks, then prefer clean.sh.",
    )


if __name__ == "__main__":
    raise SystemExit(main())
