import { describe, expect, test } from "bun:test"
import { buildTreeRows, defaultExpandedSessions, normalizeReportedState, sessionState, stateWithSeen } from "./model"
import type { SessionRow, Target, TreeRow } from "./model"

const sessionTarget = (session: string): Target => ({ type: "tmux_session", session })
const windowTarget = (session: string, suffix: string): Target => ({ type: "tmux_window", session, windowId: `@${suffix}`, pane: `%${suffix}` })

const detail = (session: string, title: string, suffix: string, state: TreeRow["state"] = "unknown") => ({
  kind: "window",
  status: "zsh",
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

describe("session tree", () => {
  const groupedSessions = [
    session("y-root", { workspaceId: "y", lineageSearchText: "y root", recency: 500 }),
    session("b-child", { workspaceId: "b", parentWorkspaceId: "a", lineageSearchText: "b a", recency: 490 }),
    session("a-root", { workspaceId: "a", childWorkspaceCount: 2, lineageLabel: "⇣2", lineageSearchText: "a child-count-2", recency: 480 }),
    session("d-grandchild", { workspaceId: "d", parentWorkspaceId: "c", lineageSearchText: "d c a", recency: 470, details: [detail("d-grandchild", "deep-window", "41", "done")] }),
    session("c-child", { workspaceId: "c", parentWorkspaceId: "a", childWorkspaceCount: 1, lineageLabel: "⇣1", lineageSearchText: "c a", recency: 460 }),
    session("z-root", { workspaceId: "z", lineageSearchText: "z root", recency: 450 }),
  ]

  test("renders recursive hierarchy with selectable nested sessions and details", () => {
    const rows = buildTreeRows(groupedSessions, "", { expandedSessions: new Set(groupedSessions.map((row) => row.name)) })
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
    const rows = buildTreeRows(groupedSessions, "", { expandedSessions: new Set(groupedSessions.map((row) => row.name)), bottomUp: true })
    expect(labeledRows(rows)).toEqual([
      "1:z-root-window",
      "0:z-root",
      "3:deep-window",
      "2:d-grandchild",
      "2:c-child-window",
      "1:c-child",
      "2:b-child-window",
      "1:b-child",
      "1:a-root-window",
      "0:a-root",
      "1:y-root-window",
      "0:y-root",
    ])
  })

  test("collapsing a parent hides both its details and descendant sessions", () => {
    const rows = buildTreeRows(groupedSessions, "", { expandedSessions: new Set(["y-root", "z-root", "b-child", "c-child", "d-grandchild"]) })
    expect(labeledRows(rows)).toEqual([
      "0:y-root",
      "1:y-root-window",
      "0:a-root",
      "0:z-root",
      "1:z-root-window",
    ])
    expect(rows.find((row) => !row.detail && row.session.name === "a-root")?.expandable).toBe(true)
    expect(rows.find((row) => !row.detail && row.session.name === "a-root")?.expanded).toBe(false)
  })

  test("expands sessions by counting own details plus direct child sessions", () => {
    expect(defaultExpandedSessions(groupedSessions)).toEqual(new Set(["y-root", "a-root", "b-child", "c-child", "d-grandchild", "z-root"]))

    const crowded = [
      session("crowded-root", { workspaceId: "crowded", childWorkspaceCount: 3, details: [detail("crowded-root", "crowded-window", "51")] }),
      session("child-one", { workspaceId: "crowded-1", parentWorkspaceId: "crowded" }),
      session("child-two", { workspaceId: "crowded-2", parentWorkspaceId: "crowded" }),
      session("child-three", { workspaceId: "crowded-3", parentWorkspaceId: "crowded" }),
    ]
    expect(defaultExpandedSessions(crowded)).toEqual(new Set(["child-one", "child-two", "child-three"]))
  })

  test("retains complete ancestor context for descendant detail matches", () => {
    const rows = buildTreeRows(groupedSessions, "deep")
    expect(labeledRows(rows)).toEqual([
      "0:a-root",
      "1:c-child",
      "2:d-grandchild",
      "3:deep-window",
    ])
    expect(rows.find((row) => !row.detail && row.session.name === "a-root")?.expanded).toBe(true)
    expect(rows.find((row) => !row.detail && row.session.name === "c-child")?.expanded).toBe(true)
  })

  test("a matching session exposes its subtree and lineage search context", () => {
    const rows = buildTreeRows(groupedSessions, "a child-count-2")
    expect(labeledRows(rows)).toEqual([
      "0:a-root",
      "1:a-root-window",
      "1:b-child",
      "2:b-child-window",
      "1:c-child",
      "2:c-child-window",
      "2:d-grandchild",
      "3:deep-window",
    ])
    expect(rows[0]?.searchText).toContain("child-count-2")
  })

  test("keeps aggregate state from descendants hidden by filtering", () => {
    const root = session("state-root", { workspaceId: "state-root", details: [detail("state-root", "root-idle", "61", "idle")] })
    const visible = session("visible-child", { workspaceId: "visible", parentWorkspaceId: "state-root", details: [detail("visible-child", "visible-ready", "62", "done")] })
    const hidden = session("hidden-child", { workspaceId: "hidden", parentWorkspaceId: "state-root", details: [detail("hidden-child", "hidden-blocked", "63", "blocked")] })
    const rows = buildTreeRows([root, visible, hidden], "visible-child")
    expect(rows.find((row) => !row.detail && row.session.name === "state-root")?.state).toBe("blocked")
  })

  test("treats orphaned parents as roots", () => {
    const orphan = session("orphan", { workspaceId: "orphan", parentWorkspaceId: "missing" })
    const rows = buildTreeRows([orphan, session("plain")], "", { expandedSessions: new Set(["orphan", "plain"]) })
    expect(sessionRows(rows).map((row) => row.session.name)).toEqual(["orphan", "plain"])
    expect(rows.find((row) => !row.detail && row.session.name === "orphan")?.parentSessionKey).toBeUndefined()
  })

  test("breaks stale cycles defensively instead of duplicating rows", () => {
    const a = session("cycle-a", { workspaceId: "cycle-a", parentWorkspaceId: "cycle-b" })
    const b = session("cycle-b", { workspaceId: "cycle-b", parentWorkspaceId: "cycle-a" })
    const rows = buildTreeRows([a, b], "", { expandedSessions: new Set(["cycle-a", "cycle-b"]) })
    expect(sessionRows(rows).map((row) => row.session.name)).toEqual(["cycle-a", "cycle-b"])
    expect(rows.filter((row) => !row.detail)).toHaveLength(2)
  })

  test("preserves ungrouped sessions exactly as a flat tree", () => {
    const flat = [session("flat-one"), session("flat-two")]
    const rows = buildTreeRows(flat, "", { expandedSessions: new Set(["flat-one", "flat-two"]) })
    expect(labeledRows(rows)).toEqual([
      "0:flat-one",
      "1:flat-one-window",
      "0:flat-two",
      "1:flat-two-window",
    ])
  })
})
