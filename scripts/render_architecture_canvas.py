#!/usr/bin/env python3
"""Build mac-disk-architecture.canvas.tsx from scan.sh --json report.

Usage:
  python3 scripts/render_architecture_canvas.py \
    --report /tmp/apfs-spa.json \
    --out ~/.cursor/projects/<ws>/canvases/mac-disk-architecture.canvas.tsx
"""

from __future__ import annotations

import argparse
import json
import os
import re
import socket
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_MAP_PATH = ROOT / "scripts" / "bundle-apps.json"
BODY_TEMPLATE = ROOT / "scripts" / "templates" / "architecture-canvas.body.tsx"

SYSTEM_BUNDLES = {
    "com.apple.geod",
    "com.apple.mediaanalysisd",
    "com.apple.mobileAssetDesktop",
}

AS_TITLES = {
    "Cursor": ("Cursor 编辑器", "写代码用的 Cursor 本地数据。"),
    "Trae CN": ("Trae 编辑器", "Trae 的本地数据。"),
    "Telegram Desktop": ("Telegram", "聊天软件数据，删了可能丢本地缓存记录。"),
    "Google": ("Google 相关", "Chrome/Google 软件留下的数据。"),
    "Adobe": ("Adobe 软件", "Creative Cloud 等 Adobe 本地数据。"),
}

IMPORTS = '''import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Grid,
  H1,
  H2,
  H3,
  Pill,
  Row,
  Spacer,
  Stack,
  Stat,
  Table,
  Text,
  computeDAGLayout,
  useCanvasState,
  useHostTheme,
} from "cursor/canvas";

'''


def kib_h(kib: Any) -> str:
    if kib is None:
        return "—"
    b = int(kib) * 1024
    for unit, n in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if b >= n:
            return f"{b / n:.1f}{unit}"
    return f"{b}B"


def bytes_h(n: int) -> str:
    b = int(n)
    for unit, d in (("T", 1024**4), ("G", 1024**3), ("M", 1024**2), ("K", 1024)):
        if b >= d:
            return f"{b / d:.1f}{unit}"
    return f"{b}B"


def parse_date(s: Any) -> datetime | None:
    if not s:
        return None
    s = str(s).strip()
    for fmt in ("%Y-%m-%d %H:%M:%S %z", "%Y-%m-%dT%H:%M:%S%z", "%Y-%m-%d"):
        try:
            d = datetime.strptime(s[:26].replace("T", " ") if "T" in s and fmt.startswith("%Y-%m-%d %H") else s, fmt)
            if d.tzinfo is None:
                d = d.replace(tzinfo=timezone.utc)
            return d
        except ValueError:
            continue
    try:
        return datetime.strptime(s[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def unused_label(dt: datetime | None, open_now: bool, now: datetime) -> tuple[str, str, int | None]:
    if open_now:
        return "正在使用", "今天", 0
    if not dt:
        return "未探测到", "—", None
    days = (now - dt).days
    if days <= 0:
        return "今天用过", dt.strftime("%Y-%m-%d"), 0
    if days < 30:
        return f"约 {days} 天没用", dt.strftime("%Y-%m-%d"), days
    if days < 365:
        months = max(1, days // 30)
        return f"约 {months} 个月没用", dt.strftime("%Y-%m-%d"), days
    years = max(1, days // 365)
    return f"约 {years} 年没用", dt.strftime("%Y-%m-%d"), days


def category_of_advice(adv: str) -> str:
    if "不要" in adv:
        return "dont"
    if "可以清" in adv or adv == "保持":
        return "safe"
    if "残留" in adv:
        return "orphan"
    if "确认" in adv or "看看" in adv:
        return "ask"
    return "neutral"


def advice_for(tier: str, action: str, open_now: bool, force: str | None = None) -> str:
    if force:
        return force
    if open_now or action == "forbidden" or tier == "T4":
        return "不要删"
    if tier == "T1" or action == "safe_to_clean":
        return "可以清（会再下载）"
    if tier == "T3":
        return "先确认：多半是卸载残留"
    if tier == "T2":
        return "先确认：还在用不"
    return "先看看再决定"


def group_for(tier: str, action: str, open_now: bool, force: str | None = None) -> str:
    if force:
        return force
    if open_now or action == "forbidden" or tier == "T4":
        return "不要动"
    if tier == "T3":
        return "疑似卸载残留"
    if tier == "T2":
        return "先确认还在用不"
    if tier == "T1" or action == "safe_to_clean":
        return "可以清"
    return "先确认还在用不"


def load_bundles() -> dict[str, dict]:
    if BUNDLE_MAP_PATH.exists():
        return json.loads(BUNDLE_MAP_PATH.read_text(encoding="utf-8"))
    return {}


def bundle_meta(bundles: dict, bundle: str | None) -> dict:
    if not bundle:
        return {}
    info = dict(bundles.get(bundle) or {})
    if not info:
        # Team-ID-prefixed Containers: try stripped key
        stripped = re.sub(r"^[A-Z0-9]{10}\.", "", bundle)
        if stripped != bundle:
            info = dict(bundles.get(stripped) or {})
    if bundle in SYSTEM_BUNDLES:
        info["force_group"] = "不要动"
        info["force_advice"] = "不要删"
        info.setdefault("note", "系统组件，一般不要手动删")
    return info


def build_graph(report: dict, as_of: str | None = None, session: dict | None = None) -> dict:
    bundles = load_bundles()
    scanned = report.get("scanned_at") or ""
    now = parse_date(scanned) or datetime.now(timezone.utc)
    as_of = as_of or now.strftime("%Y-%m-%d")

    data = (report.get("disk") or {}).get("data") or (report.get("disk") or {}).get("root") or {}
    disk = {
        "size_h": kib_h(data.get("size_kib")),
        "used_h": kib_h(data.get("used_kib")),
        "avail_h": kib_h(data.get("avail_kib")),
        "capacity": data.get("capacity") or "—",
    }

    findings = list(report.get("findings") or [])
    home = report.get("home") or os.path.expanduser("~")

    containers: list[dict] = []
    app_support: list[dict] = []
    android: list[dict] = []
    caches: list[dict] = []
    other: list[dict] = []

    for f in findings:
        path = f.get("path") or ""
        if "/Containers/" in path:
            containers.append(f)
        elif "/Application Support/" in path:
            app_support.append(f)
        elif "/Android" in path or f.get("label") == "Android SDK":
            android.append(f)
        elif "/Caches/" in path or f.get("kind") == "cache":
            caches.append(f)
        else:
            other.append(f)

    def sum_bytes(items: list[dict]) -> int:
        return sum(int(x.get("bytes") or 0) for x in items)

    lib_bytes = sum_bytes(findings)
    home_bytes = max(lib_bytes, sum_bytes(findings))

    nodes: list[dict] = []
    edges: list[tuple[str, str]] = []

    nodes.append(
        {
            "id": "disk",
            "title": "整台 Mac 磁盘",
            "size": disk["size_h"],
            "hint": f"已用 {disk['used_h']} · 可用 {disk['avail_h']}",
            "kind": "root",
            "advice": "总览",
            "category": "neutral",
            "detail": "APFS 共享容量池。下面只展开占用大、清理收益高的分支。",
        }
    )
    nodes.append(
        {
            "id": "free",
            "title": "还能用的空间",
            "size": disk["avail_h"],
            "hint": "不用动",
            "kind": "free",
            "advice": "保持",
            "category": "safe",
            "detail": "当前空闲空间。",
        }
    )
    nodes.append(
        {
            "id": "used",
            "title": "已经占用的空间",
            "size": disk["used_h"],
            "hint": f"约 {disk['capacity']} 容量",
            "kind": "used",
            "advice": "往下看",
            "category": "neutral",
            "detail": "真正要治理的是这一块。我们优先往家目录里最大的几块下钻。",
        }
    )
    nodes.append(
        {
            "id": "home",
            "title": "你的用户文件夹",
            "size": bytes_h(home_bytes) if home_bytes else "—",
            "hint": "~/…",
            "kind": "home",
            "advice": "主战场",
            "category": "neutral",
            "detail": "用户数据几乎都在这里。系统文件我们不碰。命中项合计为扫描所见，非整盘家目录精确 du。",
        }
    )
    nodes.append(
        {
            "id": "lib",
            "title": "程序私有数据（Library）",
            "size": bytes_h(lib_bytes) if lib_bytes else "—",
            "hint": "通常是最大头",
            "kind": "lib",
            "advice": "重点下钻",
            "category": "ask",
            "detail": "应用沙盒、设置、缓存、开发工具数据都在这里。",
        }
    )
    edges += [("disk", "free"), ("disk", "used"), ("used", "home"), ("home", "lib")]

    folder_specs = [
        ("lib-Containers", "应用沙盒文件夹", "Containers", containers, "先看看再决定", "每个 Mac App 常有一个私有小房间。卸载 App 后，房间有时还在。"),
        ("lib-Application Support", "应用支持数据", "Application Support", app_support, "先确认：还在用不", "Cursor、Telegram 等软件的本地数据。"),
        ("lib-Android", "安卓开发工具包", "Android", android, "先确认：还在用不", "Android SDK。不做安卓开发可以考虑清掉。"),
        ("lib-Caches", "缓存文件夹", "Caches", caches, "可以清（会再下载）", "可再下载的缓存。清了一般会在下次使用时重新生成。"),
    ]
    for nid, title, hint, items, adv, detail in folder_specs:
        if not items and nid != "lib-Caches":
            # still show empty high-value folders only if we have siblings; skip empty
            continue
        if not items:
            continue
        nodes.append(
            {
                "id": nid,
                "title": title,
                "size": bytes_h(sum_bytes(items)),
                "hint": hint,
                "kind": "folder",
                "advice": adv,
                "category": category_of_advice(adv),
                "detail": detail,
                "path": f"~/Library/{hint}",
            }
        )
        edges.append(("lib", nid))

    def usage_fields(f: dict) -> tuple[str, str, int | None]:
        u = f.get("usage") or {}
        open_now = bool(u.get("open_now") or f.get("open_now"))
        mtime = parse_date((u.get("path_times") or {}).get("mtime"))
        ol = parse_date(u.get("owner_last_used"))
        return unused_label(ol or mtime, open_now, now)

    # container leaves (top 8)
    for f in sorted(containers, key=lambda x: int(x.get("bytes") or 0), reverse=True)[:8]:
        path = f.get("path") or ""
        bundle = path.split("/Containers/")[-1] if "/Containers/" in path else None
        meta = bundle_meta(bundles, bundle)
        title = meta.get("app") or (bundle or f.get("label") or "未知")
        open_now = bool((f.get("usage") or {}).get("open_now"))
        adv = advice_for(f.get("tier", ""), f.get("action", ""), open_now, meta.get("force_advice"))
        unused_txt, last_txt, days = usage_fields(f)
        nid = f"ct-{bundle or title}"
        nodes.append(
            {
                "id": nid,
                "title": title,
                "size": f.get("human") or bytes_h(int(f.get("bytes") or 0)),
                "hint": "沙盒数据",
                "kind": "app",
                "app": title,
                "bundle": bundle,
                "advice": adv,
                "category": category_of_advice(adv),
                "tier": f.get("tier"),
                "action": f.get("action"),
                "open_now": open_now,
                "detail": (meta.get("note") or "") + ("；当前检测到正在使用。" if open_now else ""),
                "path": path.replace(home, "~") if home and path.startswith(home) else path,
                "last_used": last_txt,
                "unused": unused_txt,
                "unused_days": days,
            }
        )
        if any(n["id"] == "lib-Containers" for n in nodes):
            edges.append(("lib-Containers", nid))

    for f in sorted(app_support, key=lambda x: int(x.get("bytes") or 0), reverse=True)[:6]:
        path = f.get("path") or ""
        name = path.split("/Application Support/")[-1] if "/Application Support/" in path else (f.get("label") or "app")
        title, detail = AS_TITLES.get(name, (name, "应用本地数据"))
        open_now = bool((f.get("usage") or {}).get("open_now"))
        adv = "不要删" if name == "Telegram Desktop" else advice_for(f.get("tier", ""), f.get("action", ""), open_now)
        unused_txt, last_txt, days = usage_fields(f)
        nid = f"as-{name}"
        nodes.append(
            {
                "id": nid,
                "title": title,
                "size": f.get("human") or bytes_h(int(f.get("bytes") or 0)),
                "hint": "应用数据",
                "kind": "app",
                "app": title,
                "advice": adv,
                "category": category_of_advice(adv),
                "tier": f.get("tier"),
                "action": f.get("action"),
                "detail": detail,
                "path": path.replace(home, "~") if home and path.startswith(home) else path,
                "last_used": last_txt,
                "unused": unused_txt,
                "unused_days": days,
            }
        )
        if any(n["id"] == "lib-Application Support" for n in nodes):
            edges.append(("lib-Application Support", nid))

    for f in android[:3]:
        path = f.get("path") or ""
        unused_txt, last_txt, days = usage_fields(f)
        adv = advice_for(f.get("tier", "T2"), f.get("action", "ask_first"), False)
        nodes.append(
            {
                "id": "android-sdk",
                "title": "Android SDK",
                "size": f.get("human") or bytes_h(int(f.get("bytes") or 0)),
                "hint": "开发工具",
                "kind": "tool",
                "app": "Android 开发环境",
                "advice": adv,
                "category": category_of_advice(adv),
                "tier": f.get("tier"),
                "action": f.get("action"),
                "detail": "编译安卓/RN 原生项目会用到。确定这台电脑不做安卓开发再清。",
                "path": path.replace(home, "~") if home and path.startswith(home) else "~/Library/Android/sdk",
                "last_used": last_txt,
                "unused": unused_txt,
                "unused_days": days,
            }
        )
        if any(n["id"] == "lib-Android" for n in nodes):
            edges.append(("lib-Android", "android-sdk"))

    checklist: list[dict] = []
    for f in findings:
        path = f.get("path") or ""
        bundle = path.split("/Containers/")[-1] if "/Containers/" in path else None
        meta = bundle_meta(bundles, bundle)
        open_now = bool((f.get("usage") or {}).get("open_now"))
        title = meta.get("app")
        if not title:
            if f.get("label") == "Android SDK":
                title = "Android 开发环境"
            else:
                title = (f.get("label") or "").replace("Container ", "") or (bundle or "未知")
        why = meta.get("note") or ""
        if open_now:
            why = "检测到程序正在使用这些文件"
        elif not why and f.get("tier") == "T3":
            why = "本机找不到对应已安装应用，更像卸载后还留着的数据"
        elif f.get("tier") == "T2":
            why = "体积大的开发工具，只有你确定不用才建议清"
        elif f.get("tier") == "T1":
            why = "可再下载的缓存，清了一般会在下次使用时重新生成"
        adv = advice_for(f.get("tier", ""), f.get("action", ""), open_now, meta.get("force_advice"))
        g = group_for(f.get("tier", ""), f.get("action", ""), open_now, meta.get("force_group"))
        unused_txt, last_txt, days = usage_fields(f)
        checklist.append(
            {
                "title": title,
                "size": f.get("human") or bytes_h(int(f.get("bytes") or 0)),
                "bytes": int(f.get("bytes") or 0),
                "advice": adv,
                "group": g,
                "category": category_of_advice(adv),
                "why": why,
                "bundle": bundle,
                "open_now": open_now,
                "last_used": last_txt,
                "unused": unused_txt,
                "unused_days": days,
            }
        )

    if not any(c["group"] == "可以清" for c in checklist) and caches:
        # already covered
        pass
    elif not any(c["group"] == "可以清" for c in checklist):
        # optional: leave empty; skill says omit empty sections — table just has fewer rows
        pass

    graph: dict[str, Any] = {
        "nodes": nodes,
        "edges": [{"from": a, "to": b} for a, b in edges],
        "disk": disk,
        "checklist": checklist,
        "asOf": as_of,
        "generated_by": "render_architecture_canvas.py",
        "host": socket.gethostname(),
    }
    if session:
        graph["session"] = session
    return graph


def render_tsx(graph: dict) -> str:
    body = BODY_TEMPLATE.read_text(encoding="utf-8")
    graph_js = "const GRAPH = " + json.dumps(graph, ensure_ascii=False, indent=2) + " as const;\n\n"
    return IMPORTS + graph_js + body


def _esc(s: str) -> str:
    return (
        str(s or "")
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _mermaid_id(nid: str) -> str:
    return re.sub(r"[^A-Za-z0-9_]", "_", nid)[:64] or "n"


def _cat_fill(cat: str) -> str:
    return {
        "dont": "#fecaca",
        "orphan": "#fed7aa",
        "ask": "#fde68a",
        "safe": "#bbf7d0",
        "neutral": "#e7e5e4",
    }.get(cat or "neutral", "#e7e5e4")


def render_mermaid(graph: dict) -> str:
    """Chat-safe architecture DAG for Codex / markdown hosts (no Cursor Canvas)."""
    nodes = {n["id"]: n for n in graph.get("nodes") or []}
    lines = [
        "```mermaid",
        "flowchart TD",
        "  %% apfs-spa architecture · 同 Canvas GRAPH · 勿改成条形图替代",
    ]
    for n in graph.get("nodes") or []:
        mid = _mermaid_id(n["id"])
        title = (n.get("title") or n["id"]).replace('"', "'")
        size = n.get("size") or ""
        advice = n.get("advice") or ""
        label = f"{title}<br/>{size}"
        if advice:
            label += f"<br/>{advice}"
        lines.append(f'  {mid}["{label}"]')
    for e in graph.get("edges") or []:
        a, b = e.get("from"), e.get("to")
        if a in nodes and b in nodes:
            lines.append(f"  {_mermaid_id(a)} --> {_mermaid_id(b)}")
    for n in graph.get("nodes") or []:
        mid = _mermaid_id(n["id"])
        fill = _cat_fill(n.get("category") or "neutral")
        lines.append(f"  style {mid} fill:{fill},stroke:#78716c,color:#1c1917")
    lines.append("```")
    lines.append("")
    lines.append("图例：红系=不要动 · 橙系=疑似残留 · 黄系=先确认 · 绿系=可以清")
    lines.append("")
    lines.append("### 清理建议清单（与图同源）")
    lines.append("")
    lines.append("| 名称 | 大小 | 建议 | 多久没用 / 最近使用 |")
    lines.append("|------|------|------|---------------------|")
    for c in graph.get("checklist") or []:
        name = (c.get("title") or "").replace("|", "/")
        why = (c.get("why") or "").replace("|", "/")
        if why:
            name = f"{name} — {why}"
        size = c.get("size") or "—"
        advice = c.get("advice") or c.get("group") or "—"
        unused = c.get("unused") or "—"
        last = c.get("last_used") or "—"
        lines.append(f"| {name} | {size} | {advice} | {unused} / {last} |")
    lines.append("")
    disk = graph.get("disk") or {}
    lines.append(
        f"磁盘：容量 {disk.get('size_h', '—')} · 已用 {disk.get('used_h', '—')} · "
        f"可用 {disk.get('avail_h', '—')} · 探测日 {graph.get('asOf', '—')}"
    )
    lines.append("")
    return "\n".join(lines) + "\n"


def render_html(graph: dict) -> str:
    """Browser-openable architecture page for non-Cursor hosts."""
    disk = graph.get("disk") or {}
    nodes = {n["id"]: n for n in graph.get("nodes") or []}
    children: dict[str, list[str]] = {}
    for e in graph.get("edges") or []:
        children.setdefault(e["from"], []).append(e["to"])

    def tree_html(nid: str, depth: int = 0) -> str:
        n = nodes.get(nid) or {"id": nid, "title": nid}
        cat = n.get("category") or "neutral"
        pad = 12 + depth * 18
        tip = _esc(n.get("detail") or n.get("path") or "")
        return (
            f'<div class="node cat-{_esc(cat)}" style="margin-left:{pad}px" title="{tip}">'
            f'<span class="dot"></span>'
            f'<strong>{_esc(n.get("title"))}</strong>'
            f' <span class="size">{_esc(n.get("size") or "—")}</span>'
            f' <span class="adv">{_esc(n.get("advice") or "")}</span>'
            f"</div>"
            + "".join(tree_html(c, depth + 1) for c in children.get(nid, []))
        )

    roots = [n["id"] for n in graph.get("nodes") or [] if n["id"] == "disk"]
    if not roots and nodes:
        roots = [next(iter(nodes))]

    rows = []
    for c in graph.get("checklist") or []:
        rows.append(
            "<tr>"
            f'<td>{_esc(c.get("title"))}<div class="sub">{_esc(c.get("why") or "")}</div></td>'
            f'<td class="num">{_esc(c.get("size") or "—")}</td>'
            f'<td>{_esc(c.get("advice") or c.get("group") or "—")}</td>'
            f'<td>{_esc(c.get("unused") or "—")} / {_esc(c.get("last_used") or "—")}</td>'
            "</tr>"
        )

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Mac 磁盘占用关系图 · apfs-spa</title>
<style>
  :root {{ --bg:#f6f4ef; --ink:#1c1917; --muted:#78716c; --card:#fffdf8; --line:#e7e0d5; }}
  body {{ margin:0; font:15px/1.5 "PingFang SC","Noto Sans SC",sans-serif; color:var(--ink);
    background:radial-gradient(900px 500px at 0% 0%,#e8f5f2,transparent 55%),var(--bg); }}
  .wrap {{ max-width:960px; margin:0 auto; padding:28px 20px 64px; }}
  h1 {{ font-size:26px; margin:0 0 8px; }}
  .muted {{ color:var(--muted); }}
  .stats {{ display:grid; grid-template-columns:repeat(3,1fr); gap:10px; margin:16px 0; }}
  .stat {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px; }}
  .stat .v {{ font-size:20px; font-weight:650; }}
  .stat .l {{ font-size:12px; color:var(--muted); }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:14px; padding:14px; margin:16px 0; }}
  .node {{ padding:6px 0; border-left:3px solid #a8a29e; padding-left:10px; margin:4px 0; }}
  .node .size {{ font-variant-numeric:tabular-nums; margin-left:8px; }}
  .node .adv {{ color:var(--muted); font-size:12px; margin-left:8px; }}
  .dot {{ display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:6px; background:#a8a29e; }}
  .cat-dont {{ border-left-color:#b91c1c; }} .cat-dont .dot {{ background:#b91c1c; }}
  .cat-orphan {{ border-left-color:#c2410c; }} .cat-orphan .dot {{ background:#c2410c; }}
  .cat-ask {{ border-left-color:#a16207; }} .cat-ask .dot {{ background:#a16207; }}
  .cat-safe {{ border-left-color:#15803d; }} .cat-safe .dot {{ background:#15803d; }}
  table {{ width:100%; border-collapse:collapse; font-size:13px; }}
  th,td {{ padding:8px; border-top:1px solid var(--line); text-align:left; vertical-align:top; }}
  th {{ color:var(--muted); }} td.num {{ text-align:right; white-space:nowrap; }}
  .sub {{ color:var(--muted); font-size:12px; }}
  .legend span {{ margin-right:12px; font-size:12px; color:var(--muted); }}
</style>
</head>
<body>
<div class="wrap">
  <h1>磁盘占用关系图</h1>
  <p class="muted">与 Cursor Canvas 同源数据。连线树表示「包含 / 属于」。探测日：{_esc(graph.get("asOf"))} · 主机：{_esc(graph.get("host"))}</p>
  <div class="stats">
    <div class="stat"><div class="v">{_esc(disk.get("size_h"))}</div><div class="l">整盘大约容量</div></div>
    <div class="stat"><div class="v">{_esc(disk.get("used_h"))}</div><div class="l">已经用掉</div></div>
    <div class="stat"><div class="v">{_esc(disk.get("avail_h"))}</div><div class="l">还能用</div></div>
  </div>
  <p class="legend">
    <span>● 不要动</span><span>● 疑似残留</span><span>● 先确认</span><span>● 可以清</span>
  </p>
  <div class="card">
    <h2 style="margin:0 0 10px;font-size:16px">占用结构（架构树）</h2>
    {"".join(tree_html(r) for r in roots)}
  </div>
  <div class="card">
    <h2 style="margin:0 0 10px;font-size:16px">清理建议清单</h2>
    <table>
      <thead><tr><th>名称</th><th>大小</th><th>建议</th><th>多久没用 / 最近使用</th></tr></thead>
      <tbody>
        {"".join(rows) or "<tr><td colspan=4 class=muted>暂无清单项</td></tr>"}
      </tbody>
    </table>
  </div>
  <p class="muted small">由 render_architecture_canvas.py 生成 · 非 Cursor 宿主请用本页或 Mermaid，勿把 .canvas.tsx 当聊天附件贴出。</p>
</div>
</body>
</html>
"""


def load_session(state_path: Path | None) -> dict | None:
    if not state_path or not state_path.exists():
        return None
    try:
        st = json.loads(state_path.read_text(encoding="utf-8"))
    except Exception:
        return None
    cleans = st.get("cleans") or []
    last = cleans[-1] if cleans else None
    return {
        "phase": st.get("phase"),
        "updated_at": st.get("updated_at"),
        "last_clean": last,
        "decision_count": len(st.get("decisions") or []),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="Render mac-disk-architecture Canvas / HTML / Mermaid from scan JSON")
    ap.add_argument("--report", required=True, help="scan.sh --json report path")
    ap.add_argument("--out", required=True, help="output .canvas.tsx path")
    ap.add_argument("--state", default=os.environ.get("APFS_SPA_STATE"), help="optional state.json for session strip")
    ap.add_argument("--graph-out", help="also write GRAPH json")
    ap.add_argument("--html-out", help="also write browser HTML architecture page")
    ap.add_argument("--mermaid-out", help="also write Mermaid+checklist markdown for chat hosts")
    args = ap.parse_args()

    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    session = load_session(Path(args.state) if args.state else None)
    graph = build_graph(report, session=session)
    tsx = render_tsx(graph)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(tsx, encoding="utf-8")
    print(out)

    html_out = Path(args.html_out) if args.html_out else out.with_suffix(".html")
    # .canvas.tsx → prefer sibling mac-disk-architecture.html not .canvas.html
    if not args.html_out and str(out).endswith(".canvas.tsx"):
        html_out = out.with_name(out.name.replace(".canvas.tsx", ".html"))
    html_out.parent.mkdir(parents=True, exist_ok=True)
    html_out.write_text(render_html(graph), encoding="utf-8")
    print(html_out)

    mermaid_out = Path(args.mermaid_out) if args.mermaid_out else None
    if not args.mermaid_out and str(out).endswith(".canvas.tsx"):
        mermaid_out = out.with_name(out.name.replace(".canvas.tsx", ".md"))
    elif not args.mermaid_out:
        mermaid_out = out.with_suffix(".md")
    mermaid_out.parent.mkdir(parents=True, exist_ok=True)
    mermaid_out.write_text(render_mermaid(graph), encoding="utf-8")
    print(mermaid_out)

    if args.graph_out:
        Path(args.graph_out).write_text(json.dumps(graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
