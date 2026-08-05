type Cat = "dont" | "orphan" | "ask" | "safe" | "neutral";
type GNode = (typeof GRAPH.nodes)[number] & {
  category?: Cat;
  last_used?: string;
  unused?: string;
  unused_days?: number | null;
  app?: string;
  bundle?: string;
  path?: string;
  open_now?: boolean;
  detail?: string;
  hint?: string;
  tier?: string;
  action?: string;
};
type CheckItem = (typeof GRAPH.checklist)[number] & {
  category?: Cat;
  last_used?: string;
  unused?: string;
  unused_days?: number | null;
  bytes?: number;
};

const GROUP_META: {
  id: string;
  label: string;
  cat: Cat;
  blurb: string;
}[] = [
  { id: "不要动", label: "不要动", cat: "dont", blurb: "正在用或很重要，别删" },
  {
    id: "疑似卸载残留",
    label: "疑似卸载残留",
    cat: "orphan",
    blurb: "找不到应用了，但仍占空间",
  },
  {
    id: "先确认还在用不",
    label: "先确认还在用不",
    cat: "ask",
    blurb: "工具/数据还大，先问一句",
  },
  { id: "可以清", label: "可以清", cat: "safe", blurb: "缓存类，清了通常会再下载" },
];

function catColor(theme: ReturnType<typeof useHostTheme>, cat: Cat | string | undefined) {
  const c = theme.category;
  switch (cat) {
    case "dont":
      return c.red;
    case "orphan":
      return c.orange;
    case "ask":
      return c.yellow;
    case "safe":
      return c.green;
    default:
      return c.cyan;
  }
}

function CatBadge({
  label,
  cat,
  compact,
}: {
  label: string;
  cat: Cat | string | undefined;
  compact?: boolean;
}) {
  const theme = useHostTheme();
  const color = catColor(theme, cat);
  return (
    <span
      style={{
        display: "inline-block",
        maxWidth: compact ? "100%" : undefined,
        padding: compact ? "1px 6px" : "2px 8px",
        borderRadius: 999,
        border: `1px solid ${color}`,
        color,
        background: theme.fill.tertiary,
        fontSize: compact ? 10 : 11,
        fontWeight: 600,
        lineHeight: 1.35,
        whiteSpace: "nowrap",
        overflow: "hidden",
        textOverflow: "ellipsis",
      }}
      title={label}
    >
      {label}
    </span>
  );
}

function rowToneFor(cat: Cat | string | undefined): "danger" | "warning" | "info" | "success" | "neutral" {
  switch (cat) {
    case "dont":
      return "danger";
    case "orphan":
      return "warning";
    case "ask":
      return "info";
    case "safe":
      return "success";
    default:
      return "neutral";
  }
}

export default function MacDiskArchitectureGraph() {
  const theme = useHostTheme();
  const [selectedId, setSelectedId] = useCanvasState<string | null>("selectedNode", "lib");
  const [filter, setFilter] = useCanvasState<string>("checklistFilter", "全部");

  const NW = 152;
  const NH = 78;
  const layout = computeDAGLayout({
    nodes: GRAPH.nodes.map((n) => ({ id: n.id })),
    edges: GRAPH.edges.map((e) => ({ from: e.from, to: e.to })),
    direction: "vertical",
    nodeWidth: NW,
    nodeHeight: NH,
    rankGap: 56,
    nodeGap: 18,
    padding: 16,
  });

  const byId = Object.fromEntries(GRAPH.nodes.map((n) => [n.id, n])) as Record<string, GNode>;
  const selected = selectedId ? byId[selectedId] : null;

  const checklist = GRAPH.checklist as CheckItem[];
  const visible =
    filter === "全部" ? checklist : checklist.filter((it) => it.group === filter);

  const counts = Object.fromEntries(
    GROUP_META.map((g) => [g.id, checklist.filter((it) => it.group === g.id).length]),
  ) as Record<string, number>;

  const tableRows = visible.map((it) => [
    <Stack key="t" gap={2}>
      <Text weight="semibold">{it.title}</Text>
      <Text size="small" tone="tertiary">
        {it.why || "—"}
        {it.open_now ? "（当前正在运行）" : ""}
      </Text>
    </Stack>,
    <Text key="s" weight="bold" style={{ fontSize: 18, letterSpacing: "-0.02em" }}>
      {it.size}
    </Text>,
    <Stack key="u" gap={2}>
      <Text weight="semibold">{it.unused || "未探测到"}</Text>
      <Text size="small" tone="tertiary">
        最近：{it.last_used || "—"}
      </Text>
    </Stack>,
    <CatBadge key="a" label={it.advice} cat={it.category} />,
  ]);

  const tableTones = visible.map((it) => rowToneFor(it.category));

  return (
    <Stack gap={18} style={{ padding: 20, maxWidth: 1220 }}>
      <Stack gap={6}>
        <H1>磁盘占用关系图</H1>
        <Text tone="secondary">
          不扫遍每一个文件。先看整盘顶层，再只往「占用大、清了收益高、相对安全」的分支下钻。
          点击节点查看说明；连线表示「包含 / 属于」关系。探测日：{GRAPH.asOf || "—"}。
        </Text>
      </Stack>

      <Grid columns={4} gap={12}>
        <Stat value={GRAPH.disk.size_h} label="整盘大约容量" />
        <Stat value={GRAPH.disk.used_h} label="已经用掉" tone="warning" />
        <Stat value={GRAPH.disk.avail_h} label="还能用" tone="success" />
        <Stat value="点节点下钻" label="查看方式" tone="info" />
      </Grid>

      {"session" in GRAPH && (GRAPH as { session?: { phase?: string; last_clean?: { stamp?: string; avail_before?: string; avail_after?: string } } }).session ? (
        <Callout tone="neutral" title="跨会话续作">
          阶段：
          {String((GRAPH as { session?: { phase?: string } }).session?.phase || "—")}
          。Agent 可用 state.sh status / resume-hint 接着上次进度。
        </Callout>
      ) : null}

      <Callout tone="info" title="怎么看这张图">
        从上往下：整盘 → 已用 → 你的文件夹 → 程序私有数据 → 具体应用。彩色标签可点选筛选清单：
        红「不要动」、橙「疑似残留」、黄「先确认」、绿「可以清」。架构图节点下方同色标签。
      </Callout>

      <Row gap={8} wrap>
        {GROUP_META.map((g) => (
          <span key={g.id} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            <span
              style={{
                width: 8,
                height: 8,
                borderRadius: 99,
                background: catColor(theme, g.cat),
              }}
            />
            <Text size="small" tone="secondary">
              {g.label}
            </Text>
          </span>
        ))}
      </Row>

      <Card>
        <CardHeader>占用结构（可点击）</CardHeader>
        <CardBody>
          <div
            style={{
              position: "relative",
              width: layout.width,
              height: layout.height,
              maxWidth: "100%",
              overflow: "auto",
              border: `1px solid ${theme.stroke.tertiary}`,
              borderRadius: 8,
              background: theme.bg.editor,
            }}
          >
            <svg
              width={layout.width}
              height={layout.height}
              style={{ position: "absolute", inset: 0, pointerEvents: "none" }}
            >
              {layout.edges.map((e, i) => (
                <line
                  key={i}
                  x1={e.sourceX}
                  y1={e.sourceY}
                  x2={e.targetX}
                  y2={e.targetY}
                  stroke={theme.stroke.secondary}
                  strokeWidth={1.5}
                />
              ))}
            </svg>

            {layout.nodes.map((ln) => {
              const n = byId[ln.id];
              if (!n) return null;
              const active = selectedId === n.id;
              const cat = (n.category || "neutral") as Cat;
              const accent = catColor(theme, cat);
              const bg =
                n.kind === "root"
                  ? theme.accent.primary
                  : active
                    ? theme.fill.secondary
                    : theme.bg.elevated;
              const fg = n.kind === "root" ? theme.text.onAccent : theme.text.primary;
              return (
                <button
                  key={n.id}
                  type="button"
                  onClick={() => setSelectedId(n.id)}
                  style={{
                    position: "absolute",
                    left: ln.x,
                    top: ln.y,
                    width: NW,
                    height: NH,
                    margin: 0,
                    padding: "7px 9px",
                    borderRadius: 10,
                    border: active
                      ? `2px solid ${theme.accent.primary}`
                      : `1px solid ${theme.stroke.secondary}`,
                    borderLeft: n.kind === "root" ? undefined : `3px solid ${accent}`,
                    background: bg,
                    color: fg,
                    cursor: "pointer",
                    textAlign: "left",
                    display: "flex",
                    flexDirection: "column",
                    justifyContent: "center",
                    gap: 3,
                  }}
                >
                  <div
                    style={{
                      fontSize: 12,
                      fontWeight: 650,
                      lineHeight: 1.2,
                      overflow: "hidden",
                      textOverflow: "ellipsis",
                      whiteSpace: "nowrap",
                    }}
                  >
                    {n.title}
                  </div>
                  <div style={{ fontSize: 13, fontWeight: 700 }}>{n.size}</div>
                  {n.kind === "root" ? (
                    <div style={{ fontSize: 10, opacity: 0.85 }}>{n.advice}</div>
                  ) : (
                    <CatBadge label={n.advice} cat={cat} compact />
                  )}
                </button>
              );
            })}
          </div>
          <Spacer height={10} />
          <Text size="small" tone="secondary">
            节点左侧色条 + 底部彩色标签：红不要动 / 橙疑似残留 / 黄先确认 / 绿可以清。
          </Text>
        </CardBody>
      </Card>

      {selected ? (
        <Card>
          <CardHeader
            trailing={<CatBadge label={selected.advice} cat={selected.category as Cat} />}
          >
            {selected.title}
          </CardHeader>
          <CardBody>
            <Grid columns={4} gap={10}>
              <Stack gap={4}>
                <Text size="small" tone="secondary">
                  大小
                </Text>
                <Text weight="bold" style={{ fontSize: 20 }}>
                  {selected.size}
                </Text>
              </Stack>
              <Stack gap={4}>
                <Text size="small" tone="secondary">
                  多久没用
                </Text>
                <Text weight="semibold">
                  {"unused" in selected && selected.unused ? String(selected.unused) : "—"}
                </Text>
              </Stack>
              <Stack gap={4}>
                <Text size="small" tone="secondary">
                  最近使用
                </Text>
                <Text weight="semibold">
                  {"last_used" in selected && selected.last_used
                    ? String(selected.last_used)
                    : "—"}
                </Text>
              </Stack>
              <Stack gap={4}>
                <Text size="small" tone="secondary">
                  来自哪个应用
                </Text>
                <Text weight="semibold">
                  {"app" in selected && selected.app
                    ? String(selected.app)
                    : "—（目录层，不是单个应用）"}
                </Text>
              </Stack>
            </Grid>
            <Spacer height={10} />
            <Text>{selected.detail || "暂无更多说明。"}</Text>
            {"path" in selected && selected.path ? (
              <>
                <Spacer height={8} />
                <Text size="small" tone="tertiary">
                  位置：{String(selected.path)}
                </Text>
              </>
            ) : null}
            {"bundle" in selected && selected.bundle ? (
              <Text size="small" tone="tertiary">
                系统内部编号：{String(selected.bundle)}
              </Text>
            ) : null}
            {"open_now" in selected && selected.open_now ? (
              <>
                <Spacer height={8} />
                <Callout tone="danger" title="正在使用">
                  有程序正打开这些文件。现在删除可能导致聊天/软件异常。
                </Callout>
              </>
            ) : null}
          </CardBody>
        </Card>
      ) : null}

      <Divider />

      <Stack gap={8}>
        <H2>清理建议清单</H2>
        <Text tone="secondary" size="small">
          标签可切换：点分类只看该类；再点「全部」恢复。大小单独放大一列；「多久没用 /
          最近使用」来自应用最近使用日（优先）或文件夹修改时间（次选，弱信号）。
        </Text>
      </Stack>

      <Row gap={8} wrap>
        <Pill size="sm" active={filter === "全部"} onClick={() => setFilter("全部")}>
          全部 · {checklist.length}
        </Pill>
        {GROUP_META.map((g) => (
          <Pill
            key={g.id}
            size="sm"
            active={filter === g.id}
            onClick={() => setFilter(g.id)}
            leadingContent={
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: 99,
                  background: catColor(theme, g.cat),
                  display: "inline-block",
                }}
              />
            }
          >
            {g.label} · {counts[g.id] || 0}
          </Pill>
        ))}
      </Row>

      {filter !== "全部" ? (
        <Text size="small" tone="secondary">
          当前筛选：{filter} — {GROUP_META.find((g) => g.id === filter)?.blurb}
        </Text>
      ) : null}

      <Table
        headers={["名称 / 说明", "大小", "多久没用 / 最近使用", "建议"]}
        columnAlign={["left", "right", "left", "left"]}
        rows={tableRows}
        rowTone={tableTones}
        stickyHeader
        striped
      />

      <H3>用词说明</H3>
      <Text size="small" tone="secondary">
        「应用沙盒」= 系统给每个 App 的私人文件夹，卸载后有时不会自动清空。「最近使用」优先看对应 App
        的最近打开日；若只有文件夹修改时间，可能偏旧或被后台刷新误导。「系统内部编号」=
        用来认出沙盒属于谁。画图不会穷尽每一个小文件：顶层清楚，再优先下钻收益最高的大块。
      </Text>
    </Stack>
  );
}
