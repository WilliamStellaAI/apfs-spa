# Session handoff — apfs-spa / mac-storage-governance

Last updated: 2026-08-06

## What this skill is now

Executable local harness: intro → scan → Canvas / SVG HTML / Mermaid → SQLite ledger → clean with hard gates → optional Cursor shell hook.

## Paths (per-user, per-Mac)

| Item | Path |
|------|------|
| Skill / git root | `~/.cursor/skills/mac-storage-governance` (brand: apfs-spa) |
| Ledger DB | `~/.cache/apfs-spa/ledger.sqlite` |
| Snapshot archives | `~/.cache/apfs-spa/reports/` |
| State machine | `~/.cache/apfs-spa/state.json` |
| Quarantine | `~/.cache/apfs-spa-quarantine/<stamp>/` |
| Architecture outs | `.canvas.tsx` + SVG DAG `.html` + `.md`；预览 `http://127.0.0.1:8766/` |
| Cursor user hook | `~/.cursor/hooks.json` → `cursor-hook-shell-guard.py` |

## Decisions locked in

- User-facing labels: 不要动 / 疑似卸载残留 / 先确认还在用不 / 可以清  
- **Host presentation:** Cursor→Canvas；其它宿主→只贴可打开的预览网址；禁止主推 `.html` 路径；禁止条形图/缩进列表冒充节点图  
- HTML 须为 Canvas 同款 SVG 节点图（可点），不是缩进架构树  
- Locks in SQLite enforced by `clean.sh` + shell hook  
- Quarantine by default; purge only on explicit destroy  
- System locks: WeChat/WeCom + Documents  
- Persona intro before scan; quarantine UX in「隔离区与误判」  
- Container owner: metadata `application_bundle` → CFBundle（exact / strip Team ID / `owner_cf_bundles`）  

## Agent must

0. First touch: intro → ask 开扫 / 先锁 / 先看空间  
1. `resume-hint` + `ledger status` + list quarantine; remind if stamps exist  
2. Scan JSON → `render-architecture-canvas.sh` → Cursor 开 Canvas；其它只贴预览网址  
3. Before `--yes`: explain App-reset + space frees only after purge  
4. After quarantine: what / size / stamp / restore; never silent Done  
5. No purge without explicit「不要了/粉碎」  
6. No `rm` on locked paths; FDA note if Containers `mv` fails  

## 待拍板硬增强（未实现）

请读我.txt · purge 冷却期 · osascript 通知 · 隔离回执 · sessionStart 注入 · LaunchAgent  

Also not done: CI canary · multi-machine policies  

## Secrets

None.
