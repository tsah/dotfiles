import type { AgentState, DetailRow, SessionRow, TreeRow } from "./model"

export interface InlineSummaryEntry {
  detail: DetailRow
  label: string
}

export interface InlineSummary {
  entries: InlineSummaryEntry[]
  hiddenCount: number
}

const selectableSummaryDetails = (details: DetailRow[]) => details.filter((detail) => !["directory", "repository", "session"].includes(detail.kind))

export const ellipsize = (text: string, maxWidth: number) => {
  if (maxWidth <= 0) return ""
  if (Array.from(text).length <= maxWidth) return text
  if (maxWidth === 1) return "…"
  return `${Array.from(text).slice(0, maxWidth - 1).join("")}…`
}

export const summaryLabel = (detail: DetailRow) => detail.kind === "window" ? detail.title || detail.status || "window" : detail.kind
export const summaryGlyph = (detail: DetailRow, glyph: (state: AgentState) => string) => detail.kind === "window" ? "○" : glyph(detail.state)
export const summaryNeutral = (detail: DetailRow) => detail.kind === "window"

export const inlineSummary = (session: SessionRow, maxWidth: number, maxItems = 3): InlineSummary => {
  const details = selectableSummaryDetails(session.details)
  if (maxWidth <= 0 || details.length === 0) return { entries: [], hiddenCount: details.length }

  const entries: InlineSummaryEntry[] = []
  let used = 0
  for (const detail of details) {
    if (entries.length >= maxItems) break
    const separatorWidth = entries.length > 0 ? 2 : 0
    const remainingWidth = maxWidth - used - separatorWidth - 2
    if (remainingWidth <= 0) break
    const label = ellipsize(summaryLabel(detail), Math.min(remainingWidth, 18))
    if (!label) break
    entries.push({ detail, label })
    used += separatorWidth + Array.from(label).length + 2
  }

  let hiddenCount = Math.max(0, details.length - entries.length)
  while (hiddenCount > 0) {
    const tail = `+${hiddenCount}`
    const tailWidth = (entries.length > 0 ? 2 : 0) + tail.length
    if (used + tailWidth <= maxWidth) break
    const removed = entries.pop()
    if (!removed) break
    used = Math.max(0, used - Array.from(removed.label).length - 2 - (entries.length > 0 ? 2 : 0))
    hiddenCount = Math.max(0, details.length - entries.length)
  }

  return { entries, hiddenCount }
}

export const detailStatusLabel = (detail: DetailRow) => {
  if (detail.kind === "window") return "idle"
  if (["opencode", "pi", "claude", "codex"].includes(detail.kind) && detail.state !== "unknown") return detail.state === "blocked" ? "waiting" : detail.state === "done" ? "ready" : detail.state
  if (detail.status) return detail.status
  return detail.kind
}

export const sessionMeta = (session: SessionRow) => session.target.type === "directory"
  ? [session.activitySource, session.age].filter(Boolean).join(" ")
  : session.flags === "dirty"
    ? "dirty"
    : ""

export const treePrefix = (row: TreeRow) => {
  const guides = row.guideColumns.map((guide) => guide ? "│ " : "  ").join("")
  if (row.detail) return `${guides}${"  ".repeat(Math.max(1, row.depth))}· `
  if (row.depth === 0) {
    if (row.expandable) return `${guides}${row.expanded ? "▾ " : "▸ "}`
    return `${guides}${row.detailsExpanded ? "▾ " : "  "}`
  }
  const branch = row.isLastSibling ? "└" : "├"
  if (row.expandable) return `${guides}${branch}─${row.expanded ? "▾" : "▸"} `
  return `${guides}${branch}─${row.detailsExpanded ? "▾ " : "  "}`
}

export const jumpFooterAction = (row: TreeRow | undefined) => {
  if (!row) return ""
  if (row.detail) return "← session  Enter focus"
  if (row.detailsExpanded) return row.parentSessionKey ? "← details/parent  Enter open" : "← details  Enter open"
  if (row.expandable && row.expanded) return row.detailsExpandable ? "← lineage  → details  Enter open" : row.parentSessionKey ? "← lineage/parent  Enter open" : "← lineage  Enter open"
  if (row.expandable) return row.parentSessionKey ? "← parent  → lineage  Enter open" : "→ lineage  Enter open"
  if (row.detailsExpandable) return row.parentSessionKey ? "← parent  → details  Enter open" : "→ details  Enter open"
  return row.parentSessionKey ? "← parent  Enter open" : "Enter open"
}
