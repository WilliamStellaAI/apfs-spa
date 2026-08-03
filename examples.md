# Examples 实战案例

## Case: iOS local build blocked by a full disk (0 → 78 GiB)

Context: `eas-cli build --local` for an iOS preview package died at `React-Core-prebuilt` with:

```
write: No space left on device
```

Maven and Hermes had finished downloading; the disk simply had nowhere to put the prebuilt React-Core. `df -h /` showed `Avail ≈ 0`.

### Step 1 — Baseline & first safe pass

```bash
df -h /                              # 0 avail (full)
rm -rf ~/Library/Caches/CocoaPods
rm -rf ~/Library/Caches/ReactNative
rm -rf /tmp/eas-build-*
df -h /                              # Avail → 16 Gi
```

### Step 2 — Find the elephants

```bash
du -h -d 1 ~ | sort -hr | head -25
# 133G /Users/nirass
# 123G /Users/nirass/Library

du -h -d 1 ~/Library | sort -hr | head -20
# 65G  Application Support
# 36G  Containers
# 4.7G Nemu
# 4.6G Parallels
```

### Step 3 — Tier-2 cleanup: unused Android emulators

User confirmed they don't use Android emulators on this Mac:

```bash
rm -rf ~/Library/Application\ Support/com.netease.mumu.nemux   # 24G
rm -rf ~/Library/Application\ Support/NoxAppPlayer            # 9.2G
rm -rf ~/Library/Nemu                                        # 4.7G
df -h /                              # Avail → 64 Gi
```

### Step 4 — Tier-3: sandbox of an uninstalled app

WeCom was uninstalled, but its sandbox survived:

```bash
setopt nonomatch
du -sh ~/Library/Containers/com.tencent.WeWorkMac ...          # 14G still there!
rm -rf ~/Library/Containers/com.tencent.WeWorkMac
rm -rf ~/Library/Containers/com.tencent.wwmapp
rm -rf ~/Library/Group\ Containers/88L2Q4487U.com.tencent.WeWorkMac*
df -h /                              # Avail → 78 Gi
```

### Step 5 — Optional: Parallels leftovers

```bash
rm -rf ~/Library/Parallels ~/Library/Preferences/com.parallels*   # 4.6G
df -h /                              # ~82–83 Gi
```

### Result

| Stage | Avail |
|-------|-------|
| Start (build failing) | 0 |
| After caches | 16 Gi |
| After emulators | 64 Gi |
| After WeCom sandbox | 78 Gi |
| After Parallels | ~83 Gi |

**~78–83 Gi reclaimed, ~13% capacity, no user data touched, iOS build then succeeded.**

Key insights transferred to the skill:
1. Measure before/after every step — the biggest hog was not the build cache.
2. Uninstall ≠ data gone (WeCom 14G survived).
3. zsh glob with no match aborts the whole command (`setopt nonomatch`).
4. Never touch in-use WeChat/WeCom sandboxes.
