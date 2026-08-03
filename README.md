# APFS Spa — Mac Storage Governance Cursor Skill

> 中英双语 / Bilingual. Diagnose, prioritize, and safely reclaim disk space on macOS.
> macOS 磁盘治理 skill：诊断 → 分级 → 安全清理，绝不误删用户数据。
> 给 APFS 卷做一次「水疗」：把空间安全地还给你。

A reusable [Cursor Agent Skill](https://docs.cursor.com/agent/skills) distilled from a real
emergency: an iOS local build died with `No space left on device` on a Mac with 0 bytes free,
and tiered cleanup recovered **~80 GiB** in minutes without touching user data.

## What it does 它能做什么

- **Measure first**: `df` baseline before and after every step.
- **Tiered scan**: `du` from home down to `~/Library/Application Support`, `Containers`, caches.
- **Risk classification**: T1 regenerable caches → T2 emulators/simulators → T3 sandboxes of
  uninstalled apps → T4 in-use app data (forbidden by default).
- **Safe automation**: `scan.sh` (read-only) + `clean.sh` (dry-run by default, `--yes` to act).
- **Knowledge transfer**: the pitfalls that actually bite — APFS snapshot semantics, app uninstall
  not removing sandbox data, zsh glob no-match aborting commands, and reclaimable build caches.

## Layout 结构

```
mac-storage-governance/
├── SKILL.md          # main instructions (bilingual) — the skill entry point
├── reference.md      # deep reference: paths, sizes, red lines
├── examples.md       # real walkthrough 0 → 78 GiB
├── scripts/
│   ├── scan.sh       # read-only tiered scan
│   └── clean.sh      # tiered cleanup, dry-run default
├── LICENSE           # MIT
└── README.md
```

## Install 安装

```bash
# clone anywhere, then symlink into your personal skills dir
git clone https://github.com/WilliamStellaAI/apfs-spa.git ~/.cursor/skills/mac-storage-governance
```

Or copy the folder into a project's `.cursor/skills/`. The skill's `name` is
`mac-storage-governance` (descriptive); the repo brand is `apfs-spa`.

## Usage 使用

```bash
# scan only (safe)
./scripts/scan.sh
./scripts/scan.sh --quick

# dry-run preview of T1 (regenerable dev caches)
./scripts/clean.sh --tier 1

# actually clean T1
./scripts/clean.sh --tier 1 --yes

# T2 (emulators/simulators) — confirm the user doesn't need them first
./scripts/clean.sh --tier 2 --yes

# T3 — sandboxes of already-uninstalled apps (explicit bundle ids)
./scripts/clean.sh --tier 3 --yes --apps "com.tencent.WeWorkMac com.tencent.wwmapp"
```

**Red lines**: in-use WeChat/WeCom sandboxes, user Documents, project code — never touched.

## Contributing 参与

PRs welcome. The skill deliberately keeps `SKILL.md` under 500 lines with progressive
disclosure into `reference.md` / `examples.md` for agent context efficiency.

## License

MIT — see [LICENSE](LICENSE).
