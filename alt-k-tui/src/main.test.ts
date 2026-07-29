import { describe, expect, test } from "bun:test"
import { buildTreeRows, defaultExpandedLineageSessions, normalizeReportedState, sessionState, stateWithSeen, structuredSearch } from "./model"
import type { DetailRow, SessionRow, Target, TreeRow } from "./model"
import { inlineSummary, inlineSummaryWidth, jumpFooterAction, prefixedLabelWidth, treePrefix, usesNeutralStateGlyph, visibleInlineSummary } from "./presentation"

const sessionTarget = (session: string): Target => ({ type: "tmux_session", session })
const windowTarget = (session: string, suffix: string): Target => ({ type: "tmux_window", session, windowId: `@${suffix}`, pane: `%${suffix}` })

const detail = (session: string, title: string, suffix: string, state: TreeRow["state"] = "unknown", kind = "window"): DetailRow => ({
  kind,
  status: kind === "window" ? "zsh" : state,
  detail: "",
  title,
  age: "1m",
  state,
  target: windowTarget(session, suffix),
  completionKey: `window:@${suffix}`,
  updatedAt: Number.parseInt(suffix, 10) || 0,
})

const session = (name: string, options: Partial<SessionRow> & { details?: SessionRow["details"] } = {}): SessionRow => ({
  name,
  path: options.path ?? `/tmp/${name}`,
  branch: options.branch ?? name,
  flags: options.flags ?? "clean",
  markers: options.markers ?? [],
  age: options.age ?? "1m",
  recency: options.recency ?? 100,
  target: options.target ?? sessionTarget(name),
  details: options.details ?? [detail(name, `${name}-window`, `${name}-1`)],
  searchText: options.searchText ?? "",
  workspaceId: options.workspaceId,
  parentWorkspaceId: options.parentWorkspaceId,
  childWorkspaceCount: options.childWorkspaceCount,
  lineageLabel: options.lineageLabel,
  lineageSearchText: options.lineageSearchText,
  activitySource: options.activitySource,
  frecency: options.frecency,
})

const labeledRows = (rows: TreeRow[]) => rows.map((row) => `${row.depth}:${row.detail ? row.detail.title : row.session.name}`)
const sessionRows = (rows: TreeRow[]) => rows.filter((row) => !row.detail)
const rowFor = (rows: TreeRow[], name: string) => rows.find((row) => !row.detail && row.session.name === name)

describe("agent state", () => {
  test("normalizes legacy report names", () => {
    expect(normalizeReportedState("running")).toBe("working")
    expect(normalizeReportedState("attention")).toBe("blocked")
    expect(normalizeReportedState("done", "session_start")).toBe("idle")
  })

  test("acknowledges only the observed completion generation", () => {
    expect(stateWithSeen("done", 200, 0)).toBe("done")
    expect(stateWithSeen("done", 200, 200)).toBe("idle")
    expect(stateWithSeen("done", 300, 200)).toBe("done")
    expect(stateWithSeen("blocked", 300, 400)).toBe("blocked")
  })

  test("aggregates by actionable state precedence", () => {
    const aggregate = session("aggregate")
    aggregate.details = (["unknown", "idle", "done", "working", "blocked"] as const).map((state, index) => ({ ...detail("aggregate", `detail-${index}`, `agg-${index}`), state }))
    expect(sessionState(aggregate)).toBe("blocked")
    aggregate.details.pop()
    expect(sessionState(aggregate)).toBe("working")
    aggregate.details.pop()
    expect(sessionState(aggregate)).toBe("done")
  })
})

describe("structured search", () => {
  test("does not span a single term across field boundaries", () => {
    expect(structuredSearch([
      { text: "zsh", weight: 20 },
      { text: "false-positive", weight: 20 },
      { text: "root", weight: 20 },
    ], "z-root")).toBeUndefined()
  })

  test("keeps fuzzy abbreviations useful within a field", () => {
    expect(structuredSearch([{ text: "z-root", weight: 20 }], "zr")?.score).toBeGreaterThan(0)
  })
})

describe("session tree", () => {
  const groupedSessions = [
    session("y-root", { workspaceId: "y", lineageSearchText: "y root", recency: 500 }),
    session("b-child", { workspaceId: "b", parentWorkspaceId: "a", lineageSearchText: "b a", recency: 490 }),
    session("a-root", { workspaceId: "a", childWorkspaceCount: 2, lineageLabel: "⇣2", lineageSearchText: "a child-count-2", recency: 480 }),
    session("d-grandchild", { workspaceId: "d", parentWorkspaceId: "c", lineageSearchText: "d c a", recency: 470, details: [detail("d-grandchild", "deep-window", "41", "done")] }),
    session("c-child", { workspaceId: "c", parentWorkspaceId: "a", childWorkspaceCount: 1, lineageLabel: "⇣1", lineageSearchText: "c a", recency: 460 }),
    session("z-root", { workspaceId: "z", lineageSearchText: "z root", recency: 450 }),
  ]

  test("renders recursive hierarchy with separate lineage and detail expansion", () => {
    const rows = buildTreeRows(groupedSessions, "", {
      expandedLineageSessions: new Set(groupedSessions.map((row) => row.name)),
      expandedDetailSessions: new Set(groupedSessions.map((row) => row.name)),
    })
    expect(labeledRows(rows)).toEqual([
      "0:y-root",
      "1:y-root-window",
      "0:a-root",
      "1:a-root-window",
      "1:b-child",
      "2:b-child-window",
      "1:c-child",
      "2:c-child-window",
      "2:d-grandchild",
      "3:deep-window",
      "0:z-root",
      "1:z-root-window",
    ])
    expect(sessionRows(rows).map((row) => [row.session.name, row.depth, row.detail])).toEqual([
      ["y-root", 0, undefined],
      ["a-root", 0, undefined],
      ["b-child", 1, undefined],
      ["c-child", 1, undefined],
      ["d-grandchild", 2, undefined],
      ["z-root", 0, undefined],
    ])
    expect(rows.find((row) => !row.detail && row.session.name === "d-grandchild")?.target).toEqual(sessionTarget("d-grandchild"))
    expect(rows.find((row) => row.detail?.title === "deep-window")?.target).toEqual(windowTarget("d-grandchild", "41"))
  })

  test("keeps bottom-up ordering while each lineage subtree stays contiguous", () => {
    const expanded = new Set(groupedSessions.map((row) => row.name))
    const rows = buildTreeRows(groupedSessions, "", { expandedLineageSessions: expanded, expandedDetailSessions: expanded, bottomUp: true })
    expect(labeledRows(rows)).toEqual([
      "1:y-root-window",
      "0:y-root",
      "3:deep-window",
      "2:d-grandchild",
      "2:c-child-window",
      "1:c-child",
      "2:b-child-window",
      "1:b-child",
      "1:a-root-window",
      "0:a-root",
      "1:z-root-window",
      "0:z-root",
    ])
  })

  test("collapsing lineage hides descendants while leaving compact session rows", () => {
    const rows = buildTreeRows(groupedSessions, "", {
      expandedLineageSessions: new Set(["y-root", "z-root"]),
      expandedDetailSessions: new Set(),
    })
    expect(labeledRows(rows)).toEqual([
      "0:y-root",
      "0:a-root",
      "0:z-root",
    ])
    expect(rowFor(rows, "a-root")?.expandable).toBe(true)
    expect(rowFor(rows, "a-root")?.expanded).toBe(false)
    expect(rowFor(rows, "a-root")?.detailsExpandable).toBe(true)
    expect(rowFor(rows, "a-root")?.detailsExpanded).toBe(false)
  })

  test("defaults expand only small lineage subtrees, not leaf details", () => {
    expect(defaultExpandedLineageSessions(groupedSessions)).toEqual(new Set(["a-root", "c-child"]))

    const crowded = [
      session("crowded-root", { workspaceId: "crowded", childWorkspaceCount: 3, details: [detail("crowded-root", "crowded-window", "51")] }),
      session("child-one", { workspaceId: "crowded-1", parentWorkspaceId: "crowded" }),
      session("child-two", { workspaceId: "crowded-2", parentWorkspaceId: "crowded" }),
      session("child-three", { workspaceId: "crowded-3", parentWorkspaceId: "crowded" }),
    ]
    expect(defaultExpandedLineageSessions(crowded)).toEqual(new Set(["crowded-root"]))
    expect(defaultExpandedLineageSessions([session("leaf")])).toEqual(new Set())
  })

  test("explicit detail expansion is independent from lineage expansion", () => {
    const rows = buildTreeRows(groupedSessions, "", {
      expandedLineageSessions: new Set(["a-root", "c-child"]),
      expandedDetailSessions: new Set(["d-grandchild"]),
    })
    expect(labeledRows(rows)).toEqual([
      "0:y-root",
      "0:a-root",
      "1:b-child",
      "1:c-child",
      "2:d-grandchild",
      "3:deep-window",
      "0:z-root",
    ])
    expect(rowFor(rows, "b-child")?.expandable).toBe(false)
    expect(rowFor(rows, "b-child")?.detailsExpandable).toBe(true)
    expect(rowFor(rows, "d-grandchild")?.detailsExpanded).toBe(true)
  })

  test("retains complete ancestor context for descendant detail matches", () => {
    const rows = buildTreeRows(groupedSessions, "deep")
    expect(labeledRows(rows)).toEqual([
      "0:a-root",
      "1:c-child",
      "2:d-grandchild",
      "3:deep-window",
    ])
    expect(rowFor(rows, "a-root")?.expanded).toBe(true)
    expect(rowFor(rows, "c-child")?.expanded).toBe(true)
    expect(rowFor(rows, "d-grandchild")?.detailsExpanded).toBe(false)
  })

  test("a matching session exposes lineage context without exploding every detail row", () => {
    const rows = buildTreeRows(groupedSessions, "a child-count-2")
    expect(labeledRows(rows)).toEqual([
      "0:a-root",
      "1:b-child",
      "1:c-child",
      "2:d-grandchild",
    ])
    expect(rows[0]?.searchText).toContain("child-count-2")
  })

  test("keeps hyphenated terms inside a single field while preserving fuzzy abbreviations", () => {
    const falsePositive = session("false-positive", {
      branch: "root",
      details: [detail("false-positive", "shell", "71")],
    })
    const rows = buildTreeRows([groupedSessions.at(-1)!, falsePositive], "z-root")
    expect(sessionRows(rows).map((row) => row.session.name)).toEqual(["z-root"])
    expect(sessionRows(buildTreeRows([groupedSessions.at(-1)!, falsePositive], "zr")).map((row) => row.session.name)).toEqual(["z-root"])
  })

  test("non-empty queries keep only directly matching detail rows even after explicit expansion", () => {
    const rows = buildTreeRows([
      session("root", { workspaceId: "root", details: [detail("root", "root-main", "81"), detail("root", "root-log", "82")] }),
      session("child", { workspaceId: "child", parentWorkspaceId: "root", details: [detail("child", "exact-hit", "83"), detail("child", "unrelated-log", "84")] }),
    ], "exact-hit", {
      expandedLineageSessions: new Set(["root"]),
      expandedDetailSessions: new Set(["root", "child"]),
    })
    expect(labeledRows(rows)).toEqual([
      "0:root",
      "1:child",
      "2:exact-hit",
    ])
  })

  test("keeps aggregate state from descendants hidden by filtering", () => {
    const root = session("state-root", { workspaceId: "state-root", details: [detail("state-root", "root-idle", "61", "idle")] })
    const visible = session("visible-child", { workspaceId: "visible", parentWorkspaceId: "state-root", details: [detail("visible-child", "visible-ready", "62", "done")] })
    const hidden = session("hidden-child", { workspaceId: "hidden", parentWorkspaceId: "state-root", details: [detail("hidden-child", "hidden-blocked", "63", "blocked")] })
    const rows = buildTreeRows([root, visible, hidden], "visible-child")
    expect(rowFor(rows, "state-root")?.state).toBe("blocked")
  })

  test("treats orphaned parents as roots", () => {
    const orphan = session("orphan", { workspaceId: "orphan", parentWorkspaceId: "missing" })
    const rows = buildTreeRows([orphan, session("plain")], "")
    expect(sessionRows(rows).map((row) => row.session.name)).toEqual(["orphan", "plain"])
    expect(rowFor(rows, "orphan")?.parentSessionKey).toBeUndefined()
  })

  test("breaks stale cycles defensively instead of duplicating rows", () => {
    const a = session("cycle-a", { workspaceId: "cycle-a", parentWorkspaceId: "cycle-b" })
    const b = session("cycle-b", { workspaceId: "cycle-b", parentWorkspaceId: "cycle-a" })
    const rows = buildTreeRows([a, b], "")
    expect(sessionRows(rows).map((row) => row.session.name)).toEqual(["cycle-a", "cycle-b"])
    expect(rows.filter((row) => !row.detail)).toHaveLength(2)
  })

  test("preserves ungrouped sessions as compact roots until details are explicitly expanded", () => {
    const flat = [session("flat-one"), session("flat-two")]
    expect(labeledRows(buildTreeRows(flat, ""))).toEqual([
      "0:flat-one",
      "0:flat-two",
    ])
    expect(labeledRows(buildTreeRows(flat, "", { expandedDetailSessions: new Set(["flat-one", "flat-two"]) }))).toEqual([
      "0:flat-one",
      "1:flat-one-window",
      "0:flat-two",
      "1:flat-two-window",
    ])
  })
})

describe("presentation helpers", () => {
  test("uses neutral state glyphs when no agent state applies", () => {
    const plainSession = rowFor(buildTreeRows([session("plain")], ""), "plain")!
    const directorySession = session("directory", {
      target: { type: "directory", path: "/tmp/directory" },
      details: [{ ...detail("directory", "/tmp/directory", "00", "unknown", "directory"), target: { type: "directory", path: "/tmp/directory" } }],
    })
    const directoryRow = rowFor(buildTreeRows([directorySession], ""), "directory")!
    const unknownAgent = rowFor(buildTreeRows([session("agent", { details: [detail("agent", "pi", "01", "unknown", "pi")] })], ""), "agent")!

    expect(usesNeutralStateGlyph(plainSession)).toBe(true)
    expect(usesNeutralStateGlyph(directoryRow)).toBe(true)
    expect(usesNeutralStateGlyph(unknownAgent)).toBe(false)
  })

  test("uses session-only connectors and subdued detail bullets", () => {
    const rows = buildTreeRows([
      session("root", { workspaceId: "root", details: [detail("root", "main", "01") ] }),
      session("child", { workspaceId: "child", parentWorkspaceId: "root", details: [detail("child", "main", "02"), detail("child", "pi", "03", "done", "pi")] }),
    ], "", { expandedLineageSessions: new Set(["root"]), expandedDetailSessions: new Set(["child"]) })
    expect(treePrefix(rowFor(rows, "root")!)).toBe("▾ ")
    expect(treePrefix(rowFor(rows, "child")!)).toBe("└─▾ ")
    const detailRow = rows.find((row) => row.detail?.title === "main" && row.session.name === "child")!
    expect(treePrefix(detailRow)).toContain("· ")
    expect(treePrefix(detailRow)).not.toContain("├")
    expect(treePrefix(detailRow)).not.toContain("└")
  })

  test("fits inline summaries compactly and reports hidden entries", () => {
    const crowded = session("crowded", {
      details: [
        detail("crowded", "main", "11"),
        detail("crowded", "pi", "12", "done", "pi"),
        detail("crowded", "claude", "13", "working", "claude"),
        detail("crowded", "codex", "14", "blocked", "codex"),
      ],
    })
    expect(inlineSummary(crowded, 40)).toEqual({
      entries: [
        { detail: crowded.details[0]!, label: "main" },
        { detail: crowded.details[1]!, label: "pi" },
        { detail: crowded.details[2]!, label: "claude" },
      ],
      hiddenCount: 1,
    })
    expect(inlineSummary(crowded, 12)).toEqual({
      entries: [
        { detail: crowded.details[0]!, label: "main" },
        { detail: crowded.details[1]!, label: "pi" },
      ],
      hiddenCount: 2,
    })
    expect(visibleInlineSummary(crowded, 40, "exact-hit")).toEqual({ entries: [], hiddenCount: 0 })
    expect(inlineSummaryWidth({ entries: [], hiddenCount: 4 })).toBe(4)
    expect(inlineSummaryWidth({ entries: [{ detail: crowded.details[0]!, label: "main" }], hiddenCount: 3 })).toBe(10)
    expect(prefixedLabelWidth("⇣2")).toBe(4)
  })

  test("describes separate lineage and detail navigation affordances", () => {
    const rows = buildTreeRows([
      session("root", { workspaceId: "root" }),
      session("child", { workspaceId: "child", parentWorkspaceId: "root" }),
    ], "", { expandedLineageSessions: new Set(["root"]), expandedDetailSessions: new Set(["child"]) })
    expect(jumpFooterAction(rowFor(rows, "root"))).toBe("← lineage  → details  Enter open")
    expect(jumpFooterAction(rowFor(rows, "child"))).toBe("← details/parent  Enter open")
    expect(jumpFooterAction(rows.find((row) => row.detail?.title === "child-window"))).toBe("← session  Enter focus")
  })
})
