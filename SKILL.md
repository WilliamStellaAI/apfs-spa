---
name: mac-storage-governance
description: >-
  Diagnose, prioritize, and safely reclaim disk space on macOS. Use when the
  user reports "No space left on device", a disk is nearly full, a build fails
  with disk errors, or they ask to clean up storage / free up space / 扫一下磁盘
  / 磁盘治理 on a Mac. Works with any local Agent Skills host (Cursor, WorkBuddy,
  Codex, etc.). macOS 磁盘治理：诊断、分级清理、安全回收空间。
---

# Mac Storage Governance 磁盘治理

## 我是谁（先读这段）

用大白话说：我是一个 **只帮你在 Mac 上找空间、按风险分级、再动手清理** 的流程说明书 + 小脚本。  
品牌名 **apfs-spa**（给 APFS 卷做一次「水疗」），技能名 `mac-storage-governance`。

| 维度 | 说明 |
|------|------|
| **能力** | 测剩余空间 → 扫出大户 → 按 T1–T4 分级 → 默认预览、确认后再清 → 每步用 `df` 验收 |
| **边界** | 只管 **本机 macOS 用户目录里可再生的缓存 / 明确不用的模拟器 / 已卸载 App 残留**。不管 Windows/Linux，也不替你清 iCloud/相册/项目源码 |
| **适用** | 磁盘告急、本地 iOS/Android 构建失败、`No space left`、或你说「扫一下磁盘 / 腾点空间」 |
| **风险** | T1 几乎无风险（下次构建会再下）；T2+ 会丢本地数据，**必须你点头**；在用微信/企微等沙盒 **默认禁止删** |
| **误删回滚** | 脚本默认把东西 **挪到隔离区**（不是立刻粉碎）。T1 也可靠重新下载恢复；隔离区可整份搬回。详见下方「回滚」 |

**给 Agent 的硬规则：** 先只读扫描 → 用表格按风险汇报 → **等用户选定档位再清理** → 每步前后打 `df`。不要自作主张清 T2+。

### 回滚怎么做（若误删）

1. **默认安全路径**：`scripts/clean.sh` 把目标 `mv` 到  
   `~/.cache/apfs-spa-quarantine/<时间戳>/`，并写 `MANIFEST.tsv`（原路径 ↔ 隔离相对路径），**不是**直接 `rm -rf`。
2. **恢复**：`./scripts/clean.sh --restore <时间戳>`（`--list-quarantine` 可查）。冲突路径会 skip，不覆盖。
3. **T1 可再生缓存**：即使硬删了，下次 `pod install` / gradle / npm 构建也会重新拉，一般不用慌。
4. **真正粉碎**：只有用户明确要求时才用 `clean.sh --purge`（跳过隔离、直接删除）。
5. **隔离区打扫**：确认无误后可删旧时间戳目录。
6. **Time Machine**：若用户开了时间机器，系统级恢复仍可用——本 skill 不替代备份。

### 多 Agent 适配（不只 Cursor）

本仓库遵循开放的 **Agent Skills** 形态：`SKILL.md` + `scripts/` + 参考文档。  
**在本机有 Shell 的 Agent** 才能真正治理你这块 Mac 盘：

| 宿主 | 安装位置（个人技能） | 备注 |
|------|----------------------|------|
| Cursor | `~/.cursor/skills/mac-storage-governance/` | 也可放项目 `.cursor/skills/` |
| WorkBuddy | `~/.workbuddy/skills/mac-storage-governance/` | 同 SKILL.md 约定 |
| Codex | `~/.agents/skills/mac-storage-governance/` 或 `~/.codex/skills/` | 官方推荐 `~/.agents/skills`；也支持 `.agents/skills` |
| 通用 | `~/.agents/skills/mac-storage-governance/` | 一份目录，多工具可 symlink |
| Manus | 控制台 Skills → 上传 zip / 导入 GitHub | **格式兼容**；若跑在云端 Linux 沙箱，扫的是沙箱盘，**不是你的 Mac**——本 skill 的价值主要在本机 Agent |

一键软链：在仓库根目录执行 `./scripts/install.sh`（见 README）。

脚本路径请用 **本 skill 目录的绝对路径**（Agent 读到 `SKILL.md` 后可知目录），例如：

```bash
SKILL_DIR="…/mac-storage-governance"   # 由已加载的 SKILL.md 路径推导
"$SKILL_DIR/scripts/scan.sh" --json    # 优先：机器可读报告（harness）
"$SKILL_DIR/scripts/clean.sh" --tier 1
"$SKILL_DIR/scripts/clean.sh" --tier 1 --yes
"$SKILL_DIR/scripts/selftest.sh"       # 回归（临时沙箱，不碰真数据）
```

**推荐 Agent 流程：** `scan.sh --json` → 把 `findings` 做成表格给用户 → 等确认 → `clean.sh --tier N --yes` → 再 `df` / 可选再扫一眼 JSON。

---

## Workflow 流程

### 1. Measure first 先测量，再动手

```bash
df -h /                       # overall: used / available / capacity
df -h /System/Volumes/Data    # the real data volume (APFS snapshots hide usage)
```

**Baseline is required** — record `Avail` before anything, and after each step.

### 2. Tiered scan 分级扫描

Always read-only first. **Prefer the JSON harness report** when available:

```bash
./scripts/scan.sh --json                 # stdout
./scripts/scan.sh --json -o /tmp/apfs-spa.json
```

Human-readable fallback:

```bash
# Tier 1 — home directory first level
du -h -d 1 ~ 2>/dev/null | sort -hr | head -25

# Tier 2 — ~/Library breakdown (often 100G+ on dev machines)
du -h -d 1 ~/Library 2>/dev/null | sort -hr | head -20
```

The two elephants on macOS are almost always:

| Path | Typical culprit |
|------|-----------------|
| `~/Library/Application Support` | IDEs, Android emulators (MuMu/Nox/Nemu), Parallels, Trae, Cursor data |
| `~/Library/Containers` | App sandboxes — **WeChat 微信 / WeCom 企微 / WPS / DingTalk** etc. |

Drill further with:

```bash
du -h -d 1 ~/Library/Application\ Support 2>/dev/null | sort -hr | head -15
du -h -d 1 ~/Library/Containers 2>/dev/null | sort -hr | head -10
```

For a full list, run `scripts/scan.sh`.

### 3. Classify by risk 分级归类

| Tier | What | Safe? |
|------|------|-------|
| **T1 safe** | Regenerable caches: CocoaPods, ReactNative, npm/yarn/pip/gradle caches, Xcode DerivedData, IDE updater/ShipIt caches, Homebrew cache, `/tmp/eas-build-*`, `.expo` | ✅ Always safe, re-downloaded on demand |
| **T2 heavy** | Simulators / emulators (MuMu, Nox, Nemu), CoreSimulator runtimes, old Xcode, unused IDE data | ✅ Safe if the user no longer needs them — **ask first** |
| **T3 app sandbox** | `~/Library/Containers/*` for **uninstalled** apps | ⚠️ Safe for uninstalled apps; **never** delete sandbox data of apps still in use |
| **T4 risky** | WeChat/WeCom **in-use** containers, Documents, VM files of active Parallels | 🚫 Never delete without explicit user confirmation |

**Key rule:** deleting an app does **not** remove its sandbox data — `~/Library/Containers/<bundle-id>` often survives and can be the biggest single item (10–14G each).

向用户汇报时用简洁表格：路径 / 大小 / 风险档 / 建议动作。然后问：**清哪一档？**

### 4. Clean in priority order 按收益清理

For each item: print its size, confirm with the user (or require `--yes`), quarantine (or delete), then **re-run `df -h /` to confirm the gain**. See `scripts/clean.sh`.

Prefer the script over hand-rolled `rm`:

```bash
./scripts/clean.sh --tier 1           # dry-run
./scripts/clean.sh --tier 1 --yes     # move into quarantine
./scripts/clean.sh --tier 1 --yes --purge   # only if user insists on hard delete
```

Example T3 (only for apps the user has **uninstalled**):

```bash
./scripts/clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac"
```

### 5. Build-related space 构建缓存说明

Local iOS/Android builds eat tens of GB. Almost all of it is reclaimable:

| Cache | Path | Reclaim after build |
|-------|------|---------------------|
| RN / Hermes prebuilts | `~/Library/Caches/ReactNative` | ✅ yes |
| CocoaPods | `~/Library/Caches/CocoaPods`, project `ios/Pods` | ✅ yes |
| EAS local | `/tmp/eas-build-*` | ✅ yes |
| Gradle | `~/.gradle/caches` | ✅ yes |
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | ✅ yes |

**They re-download on next build** — this is the #1 safe target for developers.

## Safety Rules 安全规则（必须遵守）

1. **Never** wipe the `~/Library/Containers` of apps the user still uses (esp. WeChat/WeCom). Use the app's built-in cache clearing instead.
2. **Never** delete files the user cannot re-download or regenerate (Documents, Photos, projects) — even in "storage full" emergencies.
3. **Never** delete a whole app's `Application Support` unless the user confirms they no longer use that app.
4. **Measure after every step.** A cleanup that doesn't move `Avail` wasn't the real hog.
5. **zsh glob pitfall**: `*foo*` with no match aborts the **whole command**. Use `setopt nonomatch` first, or list explicit paths.
6. Always confirm the user wants **what** to be removed — never decide for them.
7. Prefer **quarantine** over hard delete; only `--purge` when the user explicitly asks to permanently remove.

## When to stop 验收标准

Stop when `Avail` is comfortably above the target (e.g. build needs ~20G+, general use ~10%+ free), or the user says "enough".

## Additional resources 补充资料

- Common pitfalls & deeper reference: [reference.md](reference.md)
- Real-world walkthrough (0 → 78 GiB): [examples.md](examples.md)
- Automation: `scripts/scan.sh` (`--json` harness report), `scripts/clean.sh` (dry-run / quarantine / purge + WeChat redline), `scripts/install.sh`, `scripts/selftest.sh`
