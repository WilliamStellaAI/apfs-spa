# APFS Spa — Mac Storage Governance

> 给 APFS 卷做一次「水疗」：先看清楚，再腾空间。  
> 品牌 **apfs-spa** · 技能名 `mac-storage-governance` · [Agent Skills](https://github.com/WilliamStellaAI/apfs-spa) 开放格式  
> 适配 Cursor / WorkBuddy / Codex 等**本机** Agent（Manus 云端沙箱 ≠ 你的 Mac 盘）

从真实事故提炼：本地 iOS 构建因 `No space left on device` 失败，分级清理数分钟内回收约 **80 GiB**，未动用户文档与在用 App 数据。

---

## 写给使用者：你怎么用它

会话里第一次用到本技能时，Agent 会以 **「APFS Spa 磁盘管家」** 自我介绍（能力 / 你可以怎么说 / 流程），**然后才开扫**。完整话术见 [`SKILL.md`](SKILL.md)「对用户的开场」。

### 你可以说

| 你说 | 会发生什么 |
|------|------------|
| 「扫一下磁盘」/「画个架构图」 | 只读扫描 + 出可交互关系图，**不删** |
| 「把某某锁上，别动」 | 写入治理账本；之后 `clean` / Cursor Hook 都会拦 |
| 「T1 缓存清掉」/「WPS、钉钉残留清掉」 | **你点头后**再隔离（默认可恢复） |
| 「恢复刚才那次」 | 按隔离时间戳还原 |
| 「磁盘还有多少」 | `df` 告诉你 |

### 整套流程

```text
管家自我介绍（若有未粉碎隔离区，开场必提）
    → 你说「开扫」
    → 扫描 + 占用关系图（Cursor=Canvas；Codex=HTML/Mermaid，勿贴 TSX）
    → 你决定：锁哪些 / 清哪些
    → 确认后 clean（默认进隔离区；App 可能像重置，空间暂不腾空）
    → 人话清单：时间戳 / 如何恢复；你点头后再粉碎
    → df 验收
```

**隔离 ≠ 腾空：** 文件还在 `~/.cache/apfs-spa-quarantine/<时间戳>/`。确认不要了再删 stamp / purge，可用空间才会明显上升。误判可 `--restore`。  
脚本级「请读我 / 冷却期禁 purge / 系统通知 / sessionStart 注入」等见 `SKILL.md`「待拍板的硬增强」（尚未全部落地）。

清理 **`~/Library/Containers`（卸掉的 App 沙盒）** 时，macOS 可能要求给 Cursor 开 **「完全磁盘访问」**；缓存类路径通常不用。

---

## 它能做什么（能力一览）

| 能力 | 说明 |
|------|------|
| **测量** | 每步前后 `df` 基线 |
| **分级扫描** | `scan.sh --json`（schema v2：tier / action / usage / deps） |
| **架构图** | `render-architecture-canvas.sh` → Cursor Canvas（可点节点、四色筛选、大小列、最近使用） |
| **风险分档** | T1 可再生缓存 → T2 工具链 → T3 疑似卸载残留 → T4 在用（默认禁止） |
| **治理账本** | SQLite：`snapshots` / `actions` / `locks`；`clean` 删前硬校验（命中锁 exit 3） |
| **人为上锁** | `ledger.sh lock`——叠在 AI 判断之上，不靠聊天记忆 |
| **默认可回滚** | `--yes` → 隔离区 + `MANIFEST.tsv`；`--purge` 才硬删 |
| **红线** | 微信/企微 + `Documents` 系统锁；另有 clean 红线闸门 |
| **Cursor Shell Guard** | `beforeShellExecution` 拦手写 `rm`/`mv`（读同一张锁表） |
| **跨会话** | `state.sh resume-hint`：接着上次进度 |
| **回归** | `selftest.sh`（沙箱，不碰真数据） |

对用户说话用白话四类：**不要动 / 疑似卸载残留 / 先确认还在用不 / 可以清**（对内才用 T1–T4）。

---

## 本机数据落在哪（每人每台 Mac 一份）

| 内容 | 路径 |
|------|------|
| 治理账本 | `~/.cache/apfs-spa/ledger.sqlite` |
| 扫描快照归档 | `~/.cache/apfs-spa/reports/snapshot-N.json` |
| 会话状态 | `~/.cache/apfs-spa/state.json` |
| 隔离区 | `~/.cache/apfs-spa-quarantine/<时间戳>/` |
| Cursor Hook | `~/.cursor/hooks.json` → `cursor-hook-shell-guard.py` |

别人 clone 本仓库跑 skill，**不会**读到你的锁与历史。

---

## 安装

```bash
git clone https://github.com/WilliamStellaAI/apfs-spa.git
cd apfs-spa
chmod +x scripts/*.sh scripts/*.py
./scripts/install.sh          # 多 Agent 软链 + 默认装 Cursor shell-guard
./scripts/install.sh --dry    # 只预览
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
| Manus | Skills → 导入 GitHub / zip（**云端盘 ≠ 你的 Mac**） |

装好后在 Cursor 里 @ 本技能或说「扫一下磁盘」；Agent 应按 `SKILL.md` **先介绍再开扫**。

---

## 命令速查（给人或 Agent）

```bash
SKILL_DIR="$HOME/.cursor/skills/mac-storage-governance"   # 或本仓库根目录

# 续作 / 账本
"$SKILL_DIR/scripts/state.sh" resume-hint
"$SKILL_DIR/scripts/ledger.sh" status
"$SKILL_DIR/scripts/ledger.sh" list-locks
"$SKILL_DIR/scripts/ledger.sh" history --snapshots

# 扫描 + 出图
"$SKILL_DIR/scripts/scan.sh" --json -o /tmp/apfs-spa.json
"$SKILL_DIR/scripts/render-architecture-canvas.sh" --report /tmp/apfs-spa.json

# 上锁（示例）
"$SKILL_DIR/scripts/ledger.sh" lock --type path \
  --target ~/Library/Caches/node-gyp --reason "编程编译缓存别清"

# 清理（默认 dry-run；加 --yes 才隔离）
"$SKILL_DIR/scripts/clean.sh" --tier 1
"$SKILL_DIR/scripts/clean.sh" --tier 1 --yes
"$SKILL_DIR/scripts/clean.sh" --tier 3 --yes --apps "com.example.LeftoverApp"
"$SKILL_DIR/scripts/clean.sh" --list-quarantine
"$SKILL_DIR/scripts/clean.sh" --restore 20260804-183000

# 验收
df -h /
"$SKILL_DIR/scripts/state.sh" record-verify --avail "$(df -h / | awk 'NR==2{print $4}')"
```

**退出码提示：** 锁拦截 → `3`；Containers 无完全磁盘访问、`mv` 失败 → `4`。

---

## 仓库结构

```
mac-storage-governance/          # GitHub 品牌目录名常为 apfs-spa
├── SKILL.md                     # Agent 契约：开场人设 + 流程 + Canvas/账本
├── README.md                    # 本文件（给人看的门面）
├── reference.md                 # JSON schema / GRAPH / 坑点
├── examples.md                  # 实战案例
├── docs/
│   ├── session-handoff.md       # 会话交接
│   └── mac-disk-architecture.html  # 可选离线架构图
├── scripts/
│   ├── scan.sh / clean.sh
│   ├── ledger.sh / ledger.py
│   ├── state.sh
│   ├── render-architecture-canvas.sh
│   ├── render_architecture_canvas.py
│   ├── templates/architecture-canvas.body.tsx
│   ├── cursor-hook-shell-guard.py
│   ├── install.sh / selftest.sh
│   └── bundle-apps.json
├── .cursor/hooks.json
└── LICENSE
```

---

## 架构图

- **同源三件套：** `render-architecture-canvas.sh` → `.canvas.tsx` + `.html` + `.md`（Mermaid）
- **Cursor：** 打开 Canvas（可点节点、四色筛选）；契约见 `SKILL.md`「架构图完整能力」
- **Codex / 其它：** `open` HTML，或把 `.md` 里的 Mermaid 贴进聊天；**不要**贴 TSX，**不要**只用条形图冒充架构图
- **静态样例：** `docs/mac-disk-architecture.html`（`?lang=zh`）；实扫以脚本新生成文件为准

---

## Harness 定位

可执行轻量 harness，不是「只写在 md 里让模型自觉」：

| 层 | 内容 |
|----|------|
| 闸门 | dry-run / 分档 / 红线 / ledger 锁 / Shell Guard |
| 观测 | `df` + JSON report + snapshots |
| 反馈 | quarantine + `--restore` + actions 表 |
| 呈现 | Canvas 生成器 |
| 续作 | `state.sh` |
| 回归 | `selftest.sh` |

尚未做 / 待拍板：隔离区「请读我」与冷却期禁 purge、系统通知、sessionStart 注入、CI 金丝雀、多机策略包（见 `SKILL.md`「待拍板的硬增强」）。

---

## Contributing

保持 `SKILL.md` 为 Agent 真源；README 面向人类；细节进 `reference.md` / `examples.md` / `docs/session-handoff.md`。改脚本后请跑 `./scripts/selftest.sh`。

## License

MIT — see [LICENSE](LICENSE).
