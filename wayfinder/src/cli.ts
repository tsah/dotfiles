#!/usr/bin/env bun
import { AgentApiError, agentCapabilities, agentStatus, listAgents, resultForAgent, sendAgent, waitForAgent, type AgentDelivery } from "./agent-api"
import { bootstrapRepositoryFromManifests, projectSnapshot, reconcileRepositoryWorkspaces, workspaceDetails, workspaceTree } from "./lineage"
import { currentWorktreeAgents, ensureDirectorySession, ensureSession, identity, sendToPane, spawnAgent, spawnWorktree, spawnWorktreeSession, type Harness } from "./workflow"

export interface ParsedArgs {
  args: string[]
  take: (flag: string) => string | undefined
  has: (flag: string) => boolean
  shift: () => string | undefined
}

export const parseArgs = (argv: string[]): ParsedArgs => {
  const args = [...argv]
  const take = (flag: string) => {
    const index = args.indexOf(flag)
    if (index < 0) return undefined
    const value = args[index + 1]
    if (!value || value.startsWith("-")) throw new Error(`${flag} requires a value`)
    args.splice(index, 2)
    return value
  }
  const has = (flag: string) => {
    const index = args.indexOf(flag)
    if (index < 0) return false
    args.splice(index, 1)
    return true
  }
  const shift = () => args.shift()
  return { args, take, has, shift }
}

const requiredAgentId = (parsed: ParsedArgs) => {
  const id = parsed.take("--id") || parsed.shift()
  if (!id) throw new Error("agent id is required")
  return id
}

const nonNegativeNumber = (value: string | undefined, flag: string) => {
  if (value === undefined) return undefined
  const number = Number(value)
  if (!Number.isFinite(number) || number < 0) throw new Error(`${flag} must be a non-negative number`)
  return number
}

const agentDelivery = (value: string | undefined): AgentDelivery | undefined => {
  if (value === undefined) return undefined
  if (value === "steer") return "steer"
  if (value === "follow-up" || value === "followUp") return "followUp"
  throw new Error("--delivery must be steer or follow-up")
}

export async function runWaystationAgentCli(argv: string[]) {
  const parsed = parseArgs(argv)
  const subcommand = parsed.shift()
  if (subcommand === "list") return console.log(JSON.stringify(await listAgents({ cwd: parsed.take("--cwd") })))
  if (subcommand === "status") return console.log(JSON.stringify(await agentStatus(requiredAgentId(parsed))))
  if (subcommand === "capabilities") return console.log(JSON.stringify(await agentCapabilities(requiredAgentId(parsed))))
  if (subcommand === "wait") {
    const afterGeneration = nonNegativeNumber(parsed.take("--after"), "--after")
    const timeoutSeconds = nonNegativeNumber(parsed.take("--timeout"), "--timeout")
    const id = requiredAgentId(parsed)
    return console.log(JSON.stringify(await waitForAgent(id, { afterGeneration, timeoutMs: timeoutSeconds === undefined ? undefined : timeoutSeconds * 1000 })))
  }
  if (subcommand === "send") {
    const delivery = agentDelivery(parsed.take("--delivery"))
    const wait = parsed.has("--wait")
    const timeoutSeconds = nonNegativeNumber(parsed.take("--timeout"), "--timeout")
    const textFlag = parsed.take("--text")
    const id = requiredAgentId(parsed)
    const text = textFlag ?? await Bun.stdin.text()
    const receipt = await sendAgent(id, text, { delivery })
    if (!wait) return console.log(JSON.stringify(receipt))
    const settled = await waitForAgent(id, { afterGeneration: receipt.afterGeneration, timeoutMs: timeoutSeconds === undefined ? undefined : timeoutSeconds * 1000 })
    const result = await resultForAgent(id, settled.settledGeneration)
    return console.log(JSON.stringify({ ...receipt, settled, result }))
  }
  if (subcommand === "result") {
    const generation = nonNegativeNumber(parsed.take("--generation"), "--generation")
    const id = requiredAgentId(parsed)
    return console.log(JSON.stringify(await resultForAgent(id, generation)))
  }
  throw new Error("Usage: waystation agent list|status|capabilities|wait|send|result ...")
}

export async function runCli(argv = process.argv.slice(2)) {
  const parsed = parseArgs(argv)
  const cmd = parsed.shift()

  if (cmd === "waystation-agent") return runWaystationAgentCli(parsed.args)
  if (cmd === "identity") return console.log(JSON.stringify(await identity(parsed.take("--cwd") || process.cwd())))
  if (cmd === "agents") return console.log(JSON.stringify(await currentWorktreeAgents(parsed.take("--cwd") || process.cwd())))
  if (cmd === "session") {
    const cwd = parsed.take("--cwd") || process.cwd()
    let worktree
    try { worktree = await identity(cwd) }
    catch { return console.log(await ensureDirectorySession(cwd)) }
    return console.log(await ensureSession(worktree))
  }
  if (cmd === "spawn-session") {
    const base = parsed.take("--base")
    const branch = parsed.shift()
    if (!branch) throw new Error("branch is required")
    return console.log(JSON.stringify(await spawnWorktreeSession(branch, base)))
  }
  if (cmd === "send") {
    const pane = parsed.take("--pane")
    const id = parsed.take("--agent-id")
    if (!pane && !id) throw new Error("--agent-id or --pane is required")
    if (pane && id) throw new Error("--agent-id and --pane are mutually exclusive")
    const text = parsed.take("--text") ?? await Bun.stdin.text()
    const submit = !parsed.has("--no-submit")
    if (!submit) throw new Error("Native agent transports cannot append without submitting a user message")
    const delivery = agentDelivery(parsed.take("--delivery"))
    const receipt = id ? await sendAgent(id, text, { delivery }) : await sendToPane(pane!, text, submit, delivery)
    return console.log(JSON.stringify(receipt))
  }
  if (cmd === "agent") {
    const harness = (parsed.take("--harness") || "pi") as Harness
    const cwd = parsed.take("--cwd") || process.cwd()
    const agent = parsed.take("--agent")
    const window = parsed.take("--window")
    const wait = parsed.has("--wait")
    const prompt = parsed.args.join(" ")
    if (!prompt) throw new Error("prompt is required")
    return console.log(JSON.stringify(await spawnAgent(harness, cwd, prompt, agent, window, wait)))
  }
  if (cmd === "worker") {
    const harness = (parsed.take("--harness") || "pi") as Harness
    const agent = parsed.take("--agent")
    const base = parsed.take("--base")
    const window = parsed.take("--window")
    const explicitParent = parsed.take("--parent")
    const noParent = parsed.has("--no-parent")
    if (explicitParent && noParent) throw new Error("--parent and --no-parent are mutually exclusive")
    const wait = parsed.has("--wait")
    const branch = parsed.shift()
    const prompt = parsed.args.join(" ")
    if (!branch || !prompt) throw new Error("branch and prompt are required")
    return console.log(JSON.stringify(await spawnWorktree(harness, branch, prompt, { agent, base, window, wait, parentWorkspaceId: explicitParent, noParent })))
  }
  if (cmd === "workspace") {
    const subcommand = parsed.shift()
    const cwd = parsed.take("--cwd") || process.cwd()
    if (subcommand === "show") return console.log(JSON.stringify(workspaceDetails(cwd, { id: parsed.take("--id"), path: parsed.take("--path") }) ?? null, null, 2))
    if (subcommand === "tree") return console.log(JSON.stringify(workspaceTree(cwd), null, 2))
    if (subcommand === "project") return console.log(JSON.stringify(projectSnapshot(cwd), null, 2))
    if (subcommand === "reconcile") return console.log(JSON.stringify(reconcileRepositoryWorkspaces(cwd), null, 2))
    if (subcommand === "bootstrap") return console.log(JSON.stringify(bootstrapRepositoryFromManifests(cwd), null, 2))
    throw new Error("Usage: dotfiles-workflow workspace show|tree|project|reconcile|bootstrap")
  }
  throw new Error("Usage: dotfiles-workflow identity|agents|session|spawn-session|send|agent|worker|workspace ...")
}

if (import.meta.main) {
  runCli().catch((error) => {
    if (process.argv[2] === "waystation-agent") {
      const apiError = error instanceof AgentApiError ? error : undefined
      console.error(JSON.stringify({ apiVersion: 1, error: { code: apiError?.code || "INVALID_REQUEST", message: error instanceof Error ? error.message : String(error) } }))
      process.exit(apiError?.exitCode || 2)
    }
    console.error(error instanceof Error ? error.message : error)
    process.exit(1)
  })
}
