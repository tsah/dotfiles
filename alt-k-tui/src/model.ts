export type Target =
  | { type: "tmux_session"; session: string }
  | { type: "tmux_window"; session: string; windowId: string; pane: string }
  | { type: "opencode"; session: string; pane: string }
  | { type: "directory"; path: string }

export type AgentState = "blocked" | "working" | "done" | "idle" | "unknown"
export type ReportedAgentState = AgentState | "running" | "attention"

export interface DetailRow { kind: string; status: string; detail: string; title: string; age: string; state: AgentState; target: Target; completionKey?: string; updatedAt: number }
export interface SessionRow { name: string; path: string; branch: string; flags: string; markers: string[]; age: string; recency: number; target: Target; details: DetailRow[]; searchText: string; activitySource?: string; frecency?: number }
export interface TreeRow { key: string; depth: 0 | 1; session: SessionRow; detail?: DetailRow; target: Target; state: AgentState; searchText: string }
export interface FuzzyResult { score: number; positions: number[] }

export const normalizeReportedState = (state: ReportedAgentState, hookEvent?: string): AgentState => {
  if (state === "running") return "working"
  if (state === "attention") return "blocked"
  if (state === "done" && hookEvent === "session_start") return "idle"
  return state
}

export const stateWithSeen = (state: AgentState, updatedAt: number, seenAt = 0, focused = false): AgentState => {
  if (state !== "done") return state
  if (focused || (seenAt > 0 && (!updatedAt || seenAt >= updatedAt))) return "idle"
  return "done"
}

export const sessionState = (session: SessionRow): AgentState => {
  const states = session.details.map((detail) => detail.state)
  if (states.includes("blocked")) return "blocked"
  if (states.includes("working")) return "working"
  if (states.includes("done")) return "done"
  if (states.includes("idle")) return "idle"
  return "unknown"
}

export const sessionSortRank = (session: SessionRow) => ["blocked", "working"].includes(sessionState(session)) ? 0 : 1

export const fuzzyResult = (text: string, query: string): FuzzyResult | undefined => {
  const chars = Array.from(text.toLowerCase())
  const normalizedQuery = query.toLowerCase().trim()
  if (!normalizedQuery) return { score: 0, positions: [] }
  const positions: number[] = []
  let searchFrom = 0
  for (const char of Array.from(normalizedQuery)) {
    const index = chars.indexOf(char, searchFrom)
    if (index < 0) return undefined
    positions.push(index)
    searchFrom = index + 1
  }
  const span = positions[positions.length - 1]! - positions[0]! + 1
  let score = normalizedQuery.length * 100 - span * 8 - positions[0]! * 2
  for (let i = 0; i < positions.length; i += 1) {
    const position = positions[i]!
    const previousPosition = positions[i - 1]
    const previousChar = position > 0 ? chars[position - 1] ?? "" : ""
    if (position === 0) score += 35
    if (["/", "@", "-", "_", " ", "."].includes(previousChar)) score += 30
    if (previousPosition !== undefined && position === previousPosition + 1) score += 45
  }
  return { score, positions }
}

const targetKey = (target: Target) => {
  switch (target.type) {
    case "tmux_session": return `session:${target.session}`
    case "tmux_window": return `window:${target.session}:${target.windowId}`
    case "opencode": return `opencode:${target.session}:${target.pane}`
    case "directory": return `directory:${target.path}`
  }
}

const sessionSearchText = (session: SessionRow) => [session.name, session.path, session.branch, session.flags, session.markers.join(" ")].join(" ").toLowerCase()
const detailSearchText = (session: SessionRow, detail: DetailRow) => [session.name, session.path, detail.kind, detail.status, detail.detail, detail.title, detail.age, detail.state].join(" ").toLowerCase()
const selectableDetails = (session: SessionRow) => session.details.filter((detail) => !["directory", "repository", "session"].includes(detail.kind))

export const defaultExpandedSessions = (sessions: SessionRow[], maxChildren = 3) => new Set(
  sessions.filter((session) => {
    const childCount = selectableDetails(session).length
    return childCount > 0 && childCount <= maxChildren
  }).map((session) => session.name),
)

export const buildTreeRows = (sessions: SessionRow[], query: string, options: { expandedSessions?: ReadonlySet<string>; bottomUp?: boolean } = {}): TreeRow[] => {
  const normalized = query.trim().toLowerCase()
  const groups = sessions.flatMap((session) => {
    const parentMatch = fuzzyResult(sessionSearchText(session), normalized)
    const detailMatches = selectableDetails(session).flatMap((detail) => {
      const match = fuzzyResult(detailSearchText(session, detail), normalized)
      return match ? [{ detail, match }] : []
    })
    if (normalized && !parentMatch && detailMatches.length === 0) return []
    const expanded = !options.expandedSessions || options.expandedSessions.has(session.name)
    const details = normalized && !parentMatch ? detailMatches.map(({ detail }) => detail) : expanded ? selectableDetails(session) : []
    const score = Math.max(parentMatch?.score ?? Number.NEGATIVE_INFINITY, ...detailMatches.map(({ match }) => match.score))
    return [{ session, details, score }]
  })
  if (normalized) groups.sort((a, b) => b.score - a.score || sessionSortRank(a.session) - sessionSortRank(b.session) || b.session.recency - a.session.recency || (b.session.frecency ?? 0) - (a.session.frecency ?? 0) || a.session.name.localeCompare(b.session.name))
  return groups.flatMap(({ session, details }) => {
    const parent: TreeRow = { key: targetKey(session.target), depth: 0, session, target: session.target, state: sessionState(session), searchText: sessionSearchText(session) }
    const children = details.map((detail): TreeRow => ({ key: `${targetKey(detail.target)}:${detail.kind}`, depth: 1, session, detail, target: detail.target, state: detail.state, searchText: detailSearchText(session, detail) }))
    return options.bottomUp ? [...children.reverse(), parent] : [parent, ...children]
  })
}
