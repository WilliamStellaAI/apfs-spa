# Session handoff — apfs-spa / mac-storage-governance

Last updated: 2026-08-04

## What this skill is now

Executable local harness (not docs-only): **intro first** → scan → scripted Canvas → SQLite ledger (snapshots/actions/locks) → clean with hard gates → optional Cursor shell hook against `rm`.

## Paths (per-user, per-Mac)

| Item | Path |
|------|------|
| Skill / git root | `~/.cursor/skills/mac-storage-governance` (brand: apfs-spa) |
| Ledger DB | `~/.cache/apfs-spa/ledger.sqlite` |
| Snapshot archives | `~/.cache/apfs-spa/reports/` |
| State machine | `~/.cache/apfs-spa/state.json` |
| Quarantine | `~/.cache/apfs-spa-quarantine/<stamp>/` |
| Cursor user hook | `~/.cursor/hooks.json` → `cursor-hook-shell-guard.py` |
| Canvas (this workspace) | `~/.cursor/projects/Users-nirass-cursor-skills-mac-storage-governance/canvases/mac-disk-architecture.canvas.tsx` |

## Decisions locked in

- User-facing cleanup labels: 不要动 / 疑似卸载残留 / 先确认还在用不 / 可以清 (not raw T1–T4).
- Canvas is the default architecture deliverable; HTML optional.
- Locks and history live in SQLite and are enforced by `clean.sh` + Cursor hook — not by markdown memory.
- Default clean path is quarantine (restorable); `--purge` only on explicit request.
- System seed locks: WeChat/WeCom bundles + `Documents` prefix.
- **Persona:** APFS Spa 磁盘管家 — SKILL「对用户的开场」before scan/clean.

## Agent must

0. **First touch:** deliver capabilities + usage guide + flow intro, then ask 开扫 / 先锁 / 先看空间  
1. `state.sh resume-hint` + `ledger.sh status` (can run with/after intro)  
2. `scan.sh --json` then `render-architecture-canvas.sh` (do not hand-author full canvas)  
3. Wait for user confirm / `ledger.sh lock` before `clean.sh --yes`  
4. Never `rm` locked paths; use `clean.sh`  
5. If `mv` Containers fails: explain Full Disk Access; do not claim success  

## Not done yet

- CI canary matrix  
- Multi-machine policy packs  

## Secrets

None in this doc. Do not put signed URLs or credentials here.
