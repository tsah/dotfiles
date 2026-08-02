import { afterEach, describe, expect, test } from "bun:test"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { applyResourceIncidents, readResourceIncidents, type ResourceIncident } from "./incidents"
import type { SessionRow } from "./model"

const roots: string[] = []
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true })
})

const incident = (overrides: Partial<ResourceIncident> = {}): ResourceIncident => ({
  version: 1,
  id: "pressure-test",
  kind: "resource_pressure_termination",
  occurredAt: 2_000,
  status: "open",
  agent: { agentId: "ws-test", harness: "pi", sessionName: "repo@work", worktreePath: "/tmp/work" },
  evidence: { reason: "sustained_memory_pressure" },
  ...overrides,
})

const session = (): SessionRow => ({
  name: "repo@work",
  path: "/tmp/work",
  branch: "work",
  flags: "clean",
  markers: ["pi"],
  age: "1m",
  recency: 1,
  target: { type: "tmux_session", session: "repo@work" },
  details: [],
  searchText: "repo work",
})

describe("resource incidents", () => {
  test("reads valid open incidents and ignores malformed records", () => {
    const root = mkdtempSync(join(tmpdir(), "wayfinder-incidents-"))
    roots.push(root)
    writeFileSync(join(root, "valid.json"), JSON.stringify(incident()))
    writeFileSync(join(root, "closed.json"), JSON.stringify({ ...incident(), id: "closed", status: "closed" }))
    writeFileSync(join(root, "broken.json"), "{")

    expect(readResourceIncidents(root).map((record) => record.id)).toEqual(["pressure-test"])
  })

  test("attaches a red-x detail to the original session", () => {
    const [row] = applyResourceIncidents([session()], [incident()])
    expect(row?.details[0]).toMatchObject({ kind: "incident", status: "terminated", state: "failed", target: { type: "tmux_session", session: "repo@work" } })
    expect(row?.searchText).toContain("sustained_memory_pressure")
  })

  test("creates a directory-backed row for a session lost on reboot", () => {
    const reboot = incident({ id: "reboot-test", kind: "unclean_boot_agent_loss", agent: { agentId: "ws-lost", harness: "claude", sessionName: "repo@lost", worktreePath: "/tmp/lost" } })
    const [row] = applyResourceIncidents([], [reboot])
    expect(row).toMatchObject({ name: "repo@lost", target: { type: "directory", path: "/tmp/lost" } })
    expect(row?.details[0]).toMatchObject({ status: "lost on reboot", state: "failed" })
  })
})
