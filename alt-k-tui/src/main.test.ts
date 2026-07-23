import { describe, expect, test } from "bun:test"
import { buildTreeRows, defaultExpandedSessions, normalizeReportedState, sessionState, stateWithSeen } from "./model"

const target = { type: "tmux_session" as const, session: "qa-tree" }
const sessions = [
  {
    name: "qa-tree",
    path: "/tmp/qa-tree",
    branch: "main",
    flags: "clean",
    markers: ["pi"],
    age: "1m",
    recency: 20,
    target,
    searchText: "",
    details: [
      { kind: "pi", status: "", detail: "", title: "implement parser", age: "2s", state: "done", target: { type: "tmux_window" as const, session: "qa-tree", windowId: "@2", pane: "%2" }, completionKey: "pane:%2", updatedAt: 200 },
      { kind: "window", status: "zsh", detail: "", title: "shell", age: "3s", state: "unknown", target: { type: "tmux_window" as const, session: "qa-tree", windowId: "@1", pane: "%1" }, completionKey: "window:@1", updatedAt: 100 },
    ],
  },
] as any

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
    const session = structuredClone(sessions[0])
    session.details = ["unknown", "idle", "done", "working", "blocked"].map((state) => ({ state }))
    expect(sessionState(session)).toBe("blocked")
    session.details.pop()
    expect(sessionState(session)).toBe("working")
    session.details.pop()
    expect(sessionState(session)).toBe("done")
  })
})

describe("session tree", () => {
  test("makes parent and child targets independently selectable", () => {
    const rows = buildTreeRows(sessions, "")
    expect(rows.map((row) => [row.depth, row.detail?.kind ?? "session"])).toEqual([[0, "session"], [1, "pi"], [1, "window"]])
    expect(rows[1]?.target).toEqual({ type: "tmux_window", session: "qa-tree", windowId: "@2", pane: "%2" })
  })

  test("retains parent context when only a child matches", () => {
    const rows = buildTreeRows(sessions, "parser")
    expect(rows.map((row) => row.detail?.kind ?? "session")).toEqual(["session", "pi"])
  })

  test("retains all children when the parent matches", () => {
    const rows = buildTreeRows(sessions, "qa-tree")
    expect(rows.map((row) => row.detail?.kind ?? "session")).toEqual(["session", "pi", "window"])
  })

  test("collapses inactive sessions and preserves bottom-up grouping", () => {
    const collapsed = buildTreeRows(sessions, "", { expandedSessions: new Set(), bottomUp: true })
    expect(collapsed.map((row) => row.detail?.kind ?? "session")).toEqual(["session"])

    const expanded = buildTreeRows(sessions, "", { expandedSessions: new Set(["qa-tree"]), bottomUp: true })
    expect(expanded.map((row) => row.detail?.kind ?? "session")).toEqual(["window", "pi", "session"])
  })

  test("expands trees with at most three children by default", () => {
    expect(defaultExpandedSessions(sessions)).toEqual(new Set(["qa-tree"]))

    const crowded = structuredClone(sessions[0])
    crowded.name = "crowded"
    crowded.details.push(structuredClone(crowded.details[0]), structuredClone(crowded.details[0]))
    expect(defaultExpandedSessions([crowded])).toEqual(new Set())
  })
})
