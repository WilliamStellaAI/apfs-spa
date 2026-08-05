# APFS Spa — Mac Storage Governance

> 中英双语。诊断 → 分级 → 安全清理（默认可回滚隔离），绝不擅自碰用户数据。  
> 给 APFS 卷做一次「水疗」：把空间安全地还给你。  
> **Agent Skills 开放格式** — 适配 Cursor / WorkBuddy / Codex / Manus（格式）等本机或兼容宿主。  
> **对人：** 会话首次使用时先以「磁盘管家」自我介绍（能力 / 用法 / 流程），再开扫。详见 `SKILL.md`「对用户的开场」。

从真实事故提炼：本地 iOS 构建因 `No space left on device` 失败，分级清理在数分钟内回收约 **80 GiB**，未动用户文档与在用 App 数据。

## 它能做什么

- **先测量**：每步前后 `df` 基线。
- **分级扫描**：人类可读 + **`scan.sh --json`** 机器可读报告（tier / action / bytes）。
- **风险分档**：T1 可再生缓存 → T2 模拟器 → T3 已卸载 App 沙盒 → T4 在用数据（默认禁止）。
- **默认可回滚**：`clean.sh --yes` → `~/.cache/apfs-spa-quarantine/<时间戳>/` + `MANIFEST.tsv`；`--purge` 才硬删。
- **红线闸门**：微信/企微 bundle id 即使 `--tier 3/4 --yes` 也会拒绝（除非显式 `APFS_SPA_ALLOW_REDLINE=1`）。
- **治理账本（SQLite）**：每次架构快照 + 行为结果 + **人为上锁**；`clean.sh` 删除前硬校验，命中锁 exit 3（不靠 AI 读 md）。
- **Cursor Shell Guard**：`beforeShellExecution` hook 读同一张锁表，拦截 Agent 手写的 `rm`/`mv`（`install.sh` 默认安装）。
- **跨会话状态**：`state.sh` 记住扫描 / Canvas / 决策 / 隔离；新会话先 `resume-hint`。
- **Canvas 脚本化**：`render-architecture-canvas.sh` 从 JSON 生成架构图并写入 ledger 快照。
- **回归**：`scripts/selftest.sh` 在临时 HOME 沙箱跑通隔离/恢复/拒绝/状态/渲染/锁闸门/shell-guard。
- **多 Agent 安装**：`scripts/install.sh`（含 Cursor hook）。

## 结构

```
mac-storage-governance/   # repo brand: apfs-spa
├── SKILL.md
├── reference.md
├── examples.md
├── scripts/
│   ├── scan.sh                      # 只读扫描；--json 输出 harness 报告
│   ├── clean.sh                     # dry-run / quarantine / purge / --restore
│   ├── ledger.sh / ledger.py            # SQLite 治理账本（快照/行为/锁）
│   ├── cursor-hook-shell-guard.py/.sh   # Cursor beforeShellExecution 拦 rm
│   ├── state.sh                         # 跨会话状态机
│   ├── render-architecture-canvas.sh
│   ├── render_architecture_canvas.py
│   ├── templates/architecture-canvas.body.tsx
│   ├── install.sh                       # 多 Agent 软链 + Cursor hook
│   └── selftest.sh                      # 沙箱回归
├── .cursor/hooks.json                   # 本仓库作工作区时的 hook
├── LICENSE
└── README.md
```

## 安装（多 Agent）

```bash
./scripts/install.sh          # 预览加 --dry；默认同时装 Cursor shell-guard hook
./scripts/install.sh --no-hooks
./scripts/install.sh --hooks-only
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
./scripts/scan.sh --json -o /tmp/apfs-spa.json
./scripts/render-architecture-canvas.sh --report /tmp/apfs-spa.json
./scripts/ledger.sh status
./scripts/ledger.sh history --snapshots
./scripts/ledger.sh list-locks
./scripts/ledger.sh lock --type path --target ~/Library/Application\ Support/Cursor --reason "别动"
./scripts/state.sh resume-hint

./scripts/clean.sh --tier 1
./scripts/clean.sh --tier 1 --yes
./scripts/clean.sh --list-quarantine
./scripts/clean.sh --restore 20260803-170000

./scripts/clean.sh --tier 2 --yes
./scripts/clean.sh --tier 3 --yes --apps "com.example.LeftoverApp"
./scripts/state.sh record-verify --avail "$(df -h / | awk 'NR==2{print $4}')"
```

**红线**：在用微信/企微沙盒、Documents、项目代码 —— 默认不碰（ledger 系统锁 + clean 红线双重闸门）。

## 架构图（优先 Canvas）

Agent 扫描后应交付 **可交互 Cursor Canvas**（节点关系图 + 四色可筛选清理清单 + 大小列 + 最近使用），契约见 `SKILL.md`「架构图完整能力」。

可选离线 HTML（中/英，默认跟随浏览器语言）：

```bash
open docs/mac-disk-architecture.html
# 或强制语言：docs/mac-disk-architecture.html?lang=zh
```

## Harness 定位

这是一个 **可执行的轻量 harness**：闸门（dry-run / 分档 / 红线 / **ledger 人为锁**）、观测（`df` + JSON report + **snapshots 表**）、反馈（隔离可 `--restore` + **actions 表**）、呈现（`render-architecture-canvas`）、跨会话（`state.sh`）、回归（`selftest.sh`）。  
目标是让任意本机 Agent 按同一套契约干活，而不是绑死某一家 IDE。尚未做的：CI 金丝雀矩阵、多机策略包。

## Contributing

保持 `SKILL.md` 精练；细节进 `reference.md` / `examples.md`。改脚本后请跑 `./scripts/selftest.sh`。

## License

MIT — see [LICENSE](LICENSE).
