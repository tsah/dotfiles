import { existsSync, readFileSync, readdirSync } from "node:fs"
import { resolve } from "node:path"
import { canonicalActivityPath } from "./activity"
import type { DetailRow, SessionRow, Target } from "./model"

export type IncidentKind = "resource_pressure_termination" | "unclean_boot_agent_loss"

export interface ResourceIncident {
  version: 1
  id: string
  kind: IncidentKind
  occurredAt: number
  status: "open"
  agent: {
    agentId: string
    harness: "pi" | "claude" | "opencode"
    pane?: string
    sessionName?: string
    worktreePath?: string
    cwd?: string
  }
  evidence?: {
    reason?: string
    forced?: boolean
    previousBootId?: string
  }
}

export const incidentStateDirectory = `${Bun.env.XDG_STATE_HOME || `${Bun.env.HOME || ""}/.local/state`}/alt-k-tui/incidents`
const incidentKinds = new Set<IncidentKind>(["resource_pressure_termination", "unclean_boot_agent_loss"])
const harnesses = new Set(["pi", "claude", "opencode"])

const validIncident = (value: unknown): value is ResourceIncident => {
  if (!value || typeof value !== "object") return false
  const incident = value as Partial<ResourceIncident>
  return incident.version === 1
    && typeof incident.id === "string" && incident.id.length > 0
    && incidentKinds.has(incident.kind as IncidentKind)
    && Number.isFinite(incident.occurredAt) && Number(incident.occurredAt) > 0
    && incident.status === "open"
    && Boolean(incident.agent && typeof incident.agent.agentId === "string" && harnesses.has(incident.agent.harness || ""))
}

export const readResourceIncidents = (directory = incidentStateDirectory): ResourceIncident[] => {
  if (!existsSync(directory)) return []
  return readdirSync(directory).flatMap((entry) => {
    if (!entry.endsWith(".json")) return []
    try {
      const incident = JSON.parse(readFileSync(resolve(directory, entry), "utf8"))
      return validIncident(incident) ? [incident] : []
    } catch {
      return []
    }
  }).sort((a, b) => b.occurredAt - a.occurredAt || a.id.localeCompare(b.id))
}

const incidentPath = (incident: ResourceIncident) => incident.agent.worktreePath || incident.agent.cwd || ""
const incidentStatus = (incident: ResourceIncident) => incident.kind === "resource_pressure_termination" ? "terminated" : "lost on reboot"
const ageFromTimestamp = (timestamp: number) => {
  const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000))
  if (seconds < 60) return `${seconds}s`
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`
  return `${Math.floor(seconds / 86400)}d`
}

const incidentDetail = (incident: ResourceIncident, target: Target): DetailRow => ({
  kind: "incident",
  status: incidentStatus(incident),
  detail: incident.evidence?.reason || incident.kind,
  title: `${incident.agent.harness} ${incident.agent.agentId}`,
  age: ageFromTimestamp(incident.occurredAt),
  state: "failed",
  target,
  updatedAt: incident.occurredAt,
})

const rowMatches = (row: SessionRow, incident: ResourceIncident) => {
  if (incident.agent.sessionName && row.target.type === "tmux_session" && row.name === incident.agent.sessionName) return true
  const path = incidentPath(incident)
  return Boolean(path && row.path && canonicalActivityPath(row.path) === canonicalActivityPath(path))
}

export const applyResourceIncidents = (rows: SessionRow[], incidents: ResourceIncident[]) => {
  const result = rows.map((row) => ({ ...row, details: [...row.details] }))
  for (const incident of incidents) {
    let row = result.find((candidate) => rowMatches(candidate, incident))
    if (!row) {
      const path = incidentPath(incident)
      if (!path) continue
      const canonicalPath = canonicalActivityPath(path)
      const target: Target = { type: "directory", path: canonicalPath }
      row = {
        name: incident.agent.sessionName || canonicalPath,
        path: canonicalPath,
        branch: "",
        flags: "",
        markers: [],
        age: ageFromTimestamp(incident.occurredAt),
        recency: Math.floor(incident.occurredAt / 1000),
        target,
        details: [],
        searchText: "",
        directorySource: "activity",
        activitySource: "incident",
      }
      result.push(row)
    }
    row.details.push(incidentDetail(incident, row.target))
    row.recency = Math.max(row.recency, Math.floor(incident.occurredAt / 1000))
    row.searchText = [row.searchText, incident.id, incident.kind, incidentStatus(incident), incident.agent.harness, incident.agent.agentId, incident.evidence?.reason].filter(Boolean).join(" ").toLowerCase()
  }
  return result
}
