---
name: mac-storage-governance
description: >-
  Diagnose, prioritize, and safely reclaim disk space on macOS. Use when the
  user reports "No space left on device", a disk is nearly full, a build fails
  with disk errors, or they ask to clean up storage / free up space on a Mac.
  macOS 磁盘治理：诊断、分级清理、安全回收空间。
---

# Mac Storage Governance 磁盘治理

Systematically reclaim disk space on macOS **without touching user data**.
Every step is measured (`df` before/after) and reversible when possible.

## Workflow 流程

### 1. Measure first 先测量，再动手

```bash
df -h /                       # overall: used / available / capacity
df -h /System/Volumes/Data    # the real data volume (APFS snapshots hide usage)
```

**Baseline is required** — record `Avail` before anything, and after each step.

### 2. Tiered scan 分级扫描

Always read-only first. Start wide, then drill into the two biggest Mac space hogs.

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
| **T1 safe** | Regenerable caches: CocoaPods, ReactNative, npm/yarn/pip/gradle caches, Xcode DerivedData, `/tmp/eas-build-*`, `.expo` | ✅ Always safe, re-downloaded on demand |
| **T2 heavy** | Simulators / emulators (MuMu, Nox, Nemu), CoreSimulator runtimes, old Xcode, unused IDE data | ✅ Safe if the user no longer needs them — **ask first** |
| **T3 app sandbox** | `~/Library/Containers/*` for **uninstalled** apps | ⚠️ Safe for uninstalled apps; **never** delete sandbox data of apps still in use |
| **T4 risky** | WeChat/WeCom **in-use** containers, Documents, VM files of active Parallels | 🚫 Never delete without explicit user confirmation |

**Key rule:** deleting an app does **not** remove its sandbox data — `~/Library/Containers/<bundle-id>` often survives and can be the biggest single item (10–14G each).

### 4. Clean in priority order 按收益清理

For each item: print its size, confirm with the user (or require `--yes`), delete, then **re-run `df -h /` to confirm the gain**. See `scripts/clean.sh`.

Example T1 cleanup:

```bash
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/Library/Caches/ReactNative
rm -rf /tmp/eas-build-*          # EAS local build temp
```

Example T3 (only for apps the user has **uninstalled**):

```bash
rm -rf ~/Library/Containers/com.tencent.WeWorkMac    # 14G class
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

1. **Never** `rm -rf` the `~/Library/Containers` of apps the user still uses (esp. WeChat/WeCom). Use the app's built-in cache clearing instead.
2. **Never** delete files the user cannot re-download or regenerate (Documents, Photos, projects) — even in "storage full" emergencies.
3. **Never** delete a whole app's `Application Support` unless the user confirms they no longer use that app.
4. **Measure after every step.** A cleanup that doesn't move `Avail` wasn't the real hog.
5. **zsh glob pitfall**: `*foo*` with no match aborts the **whole command**. Use `setopt nonomatch` first, or list explicit paths.
6. Always confirm the user wants **what** to be removed — never decide for them.

## When to stop 验收标准

Stop when `Avail` is comfortably above the target (e.g. build needs ~20G+, general use ~10%+ free), or the user says "enough".

## Additional resources 补充资料

- Common pitfalls & deeper reference: [reference.md](reference.md)
- Real-world walkthrough (0 → 78 GiB): [examples.md](examples.md)
- Automation: `scripts/scan.sh` (read-only) and `scripts/clean.sh` (tiered, dry-run default)
