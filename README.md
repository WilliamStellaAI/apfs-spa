# APFS Spa — Mac Storage Governance

> 中英双语。诊断 → 分级 → 安全清理（默认可回滚隔离），绝不擅自碰用户数据。  
> 给 APFS 卷做一次「水疗」：把空间安全地还给你。  
> **Agent Skills 开放格式** — 适配 Cursor / WorkBuddy / Codex / Manus（格式）等本机或兼容宿主。

从真实事故提炼：本地 iOS 构建因 `No space left on device` 失败，分级清理在数分钟内回收约 **80 GiB**，未动用户文档与在用 App 数据。

## 它能做什么

- **先测量**：每步前后 `df` 基线。
- **分级扫描**：人类可读 + **`scan.sh --json`** 机器可读报告（tier / action / bytes）。
- **风险分档**：T1 可再生缓存 → T2 模拟器 → T3 已卸载 App 沙盒 → T4 在用数据（默认禁止）。
- **默认可回滚**：`clean.sh --yes` → `~/.cache/apfs-spa-quarantine/<时间戳>/` + `MANIFEST.tsv`；`--purge` 才硬删。
- **红线闸门**：微信/企微 bundle id 即使 `--tier 3/4 --yes` 也会拒绝（除非显式 `APFS_SPA_ALLOW_REDLINE=1`）。
- **回归**：`scripts/selftest.sh` 在临时 HOME 沙箱跑通隔离/恢复/拒绝路径。
- **多 Agent 安装**：`scripts/install.sh`。

## 结构

```
mac-storage-governance/   # repo brand: apfs-spa
├── SKILL.md
├── reference.md
├── examples.md
├── scripts/
│   ├── scan.sh           # 只读扫描；--json 输出 harness 报告
│   ├── clean.sh          # dry-run / quarantine / purge / --restore
│   ├── install.sh        # 多 Agent 软链
│   └── selftest.sh       # 沙箱回归
├── LICENSE
└── README.md
```

## 安装（多 Agent）

```bash
git clone https://github.com/WilliamStellaAI/apfs-spa.git ~/src/apfs-spa
cd ~/src/apfs-spa
chmod +x scripts/*.sh
./scripts/install.sh          # 预览加 --dry
./scripts/selftest.sh         # 应全部 PASS
```

| 宿主 | 个人技能目录 |
|------|----------------|
| Cursor | `~/.cursor/skills/mac-storage-governance` |
| WorkBuddy | `~/.workbuddy/skills/mac-storage-governance` |
| Codex（推荐） | `~/.agents/skills/mac-storage-governance` |
| Codex（兼容） | `~/.codex/skills/mac-storage-governance` |
| Manus | Skills → 导入 GitHub 或上传 zip（**云端盘 ≠ 你的 Mac**） |

## 使用

```bash
./scripts/scan.sh --json
./scripts/scan.sh --json -o /tmp/apfs-spa.json

./scripts/clean.sh --tier 1
./scripts/clean.sh --tier 1 --yes
./scripts/clean.sh --list-quarantine
./scripts/clean.sh --restore 20260803-170000

./scripts/clean.sh --tier 2 --yes
./scripts/clean.sh --tier 3 --yes --apps "com.example.LeftoverApp"
```

**红线**：在用微信/企微沙盒、Documents、项目代码 —— 默认不碰。

## Harness 定位

这是一个 **可执行的轻量 harness**：闸门（dry-run / 分档 / 红线）、观测（`df` + JSON report）、反馈（隔离可 `--restore`）、回归（`selftest.sh`）。  
目标是让任意本机 Agent 按同一套契约干活，而不是绑死某一家 IDE。尚未做的：跨会话状态机、CI 金丝雀矩阵、多机策略包。

## Contributing

保持 `SKILL.md` 精练；细节进 `reference.md` / `examples.md`。改脚本后请跑 `./scripts/selftest.sh`。

## License

MIT — see [LICENSE](LICENSE).
