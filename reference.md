# Mac Storage Governance — Reference 参考手册

Deep-dive knowledge that does not fit in SKILL.md. Read when you hit an unusual case or need exact commands.

## APFS / `df` semantics 磁盘语义

- macOS shows APFS **snapshots** in "About This Mac → Storage" — the Finder bar can disagree with terminal numbers by tens of GB. `df` on `/System/Volumes/Data` is the authoritative number.
- `df -h /` shows the system volume; on modern macOS the data volume is usually the near-total of all usage. Always check both.
- "System Data" in the Storage UI often includes hidden caches (`~/Library/...`) — not just OS files.

## The elephants in order 常见大户（按出现频率）

| Rank | Path | Typical size | Class |
|------|------|--------------|-------|
| 1 | `~/Library/Application Support/<emulator>` — MuMu `com.netease.mumu.nemux`, Nox, Nemu | 5–25G each | T2 |
| 2 | `~/Library/Containers/com.tencent.xinWeChat` | 10–15G | T4 (in use) |
| 3 | `~/Library/Containers/com.tencent.WeWorkMac` | 10–14G | T3 if app uninstalled, else T4 |
| 4 | `~/Library/Application Support/<IDE>` — Trae CN, Cursor caches | 1–4G each | T1/T2 |
| 5 | `~/Library/Parallels` + `~/Parallels` (VM files) | 2–50G | T4 |
| 6 | `~/Library/Developer/CoreSimulator` | 1–10G | T2 |
| 7 | `~/.gradle/caches` | 1–2G | T1 |
| 8 | `~/Library/Containers/com.kingsoft.wpsoffice.mac` | 1–3G | T4/T3 |
| 9 | DingTalk `5ZSL2CJU2T.com.dingtalk.mac*` containers | <1G each | T3/T4 |
| 10 | `~/Library/Caches/<app>` — Lark, Google, Doubao, browser caches | 1–8G total | T1 |

## App uninstall ≠ data gone 卸载不删数据

Sandbox data lives in `~/Library/Containers/<bundle-id>` and **survives uninstall**. To find leftover sandboxes after uninstalling an app:

```bash
# enable zsh glob so no-match doesn't abort the whole command
setopt nonomatch

du -sh \
  ~/Library/Containers/com.tencent.WeWorkMac \
  ~/Library/Containers/com.tencent.wwmapp \
  ~/Library/Group\ Containers/*[Ww]e[Ww]ork* \
  ~/Library/Application\ Support/*[Ww]e[Ww]ork* 2>/dev/null
```

Cleaning an uninstalled app's containers is T3 — safe and high-yield.

## zsh glob no-match trap（高频踩坑）

```bash
rm -rf ~/x/*foo*        # if no match: "no matches found" → WHOLE command aborts
```

Fix: `setopt nonomatch` at the top, or quote with explicit globs, or use `find`.

## Simulator / emulator cleanup 模拟器清理

```bash
# MuMu (Netease) — quit app first
rm -rf ~/Library/Application\ Support/com.netease.mumu.nemux   # ~24G
rm -rf ~/Library/Nemu
# Nox
rm -rf ~/Library/Application\ Support/NoxAppPlayer             # ~9G
```

## Xcode / CoreSimulator 清理

```bash
xcrun simctl delete unavailable        # delete runtimes/device of unavailable sims
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport
```

## Parallels cleanup 虚拟机清理

If the user does not use Parallels:

```bash
# confirm where VM files are first
du -sh ~/Library/Parallels ~/Parallels ~/Library/Application\ Support/Parallels 2>/dev/null

rm -rf ~/Library/Parallels
rm -rf ~/Library/Preferences/com.parallels*
rm -rf ~/Library/Caches/com.parallels*
rm -rf ~/Parallels
```

## Verifying a cleanup actually worked 验证清没清掉

```bash
du -sh <path> 2>&1          # "No such file or directory" = gone
df -h /                     # expect Avail to jump by roughly the freed amount
```

If `Avail` did not move, the real hog is elsewhere — rescan, don't delete more blindly.

## Typical gains 典型收益

- CocoaPods + ReactNative caches: several GB, instantly reclaimable, re-downloaded next build.
- Unused Android emulators: 15–35G.
- Uninstalled app sandboxes: 10–15G per app.
- Browser/IM caches (Lark, Google, Doubao): 5–8G total.

## Do NOT touch（红线）

- In-use WeChat/WeCom containers — use their in-app "clear cache".
- User Documents / Desktop / Downloads content.
- Any project code or `.git`.
- System files; anything under `/System` (except nothing — just don't).

## Quarantine / rollback 隔离与回滚

`clean.sh --yes` (without `--purge`) moves targets to:

```text
~/.cache/apfs-spa-quarantine/<YYYYMMDD-HHMMSS>/<relative-path>
```

并写入 `MANIFEST.tsv`（`original_path<TAB>rel`）。

```bash
./scripts/clean.sh --list-quarantine
./scripts/clean.sh --restore 20260803-170511   # stamp from list
```

- Collisions: if the original path already exists again, restore **skips** that item (no overwrite).
- T1 caches: even after `--purge`, next build usually re-downloads — soft rollback.
- Override roots: `APFS_SPA_HOME`, `APFS_SPA_QUARANTINE`（仅自测/高级用途）。
- Red line: `com.tencent.xinWeChat` / `com.tencent.WeWorkMac` / `com.tencent.wwmapp` → exit 2 unless `APFS_SPA_ALLOW_REDLINE=1`.

## JSON report schema（scan.sh --json）

```json
{
  "skill": "mac-storage-governance",
  "schema_version": 1,
  "read_only": true,
  "disk": { "root": {}, "data": {} },
  "summary": { "t1_bytes": 0, "t2_bytes": 0, "t3_bytes": 0, "t4_bytes": 0 },
  "findings": [
    { "tier": "T1", "action": "safe_to_clean", "label": "CocoaPods", "path": "...", "bytes": 0, "human": "1.1G" }
  ],
  "agent_hint": "..."
}
```

`action`: `safe_to_clean` | `ask_first` | `forbidden`.

## Multi-agent install paths

| Host | Path |
|------|------|
| Cursor | `~/.cursor/skills/mac-storage-governance` |
| WorkBuddy | `~/.workbuddy/skills/mac-storage-governance` |
| Codex | `~/.agents/skills/mac-storage-governance` (also `~/.codex/skills`) |
| Generic | `~/.agents/skills/mac-storage-governance` |
| Manus | Upload / GitHub import — cloud VM disk ≠ user Mac |

Use `./scripts/install.sh` to symlink one clone into the local hosts above.

Regression: `./scripts/selftest.sh`.
