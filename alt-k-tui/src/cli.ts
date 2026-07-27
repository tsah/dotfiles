#!/usr/bin/env bun
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

export async function runCli(argv = process.argv.slice(2)) {
  const parsed = parseArgs(argv)
  const cmd = parsed.shift()

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
    if (!pane) throw new Error("--pane is required")
    const text = parsed.take("--text") ?? await Bun.stdin.text()
    await sendToPane(pane, text, !parsed.has("--no-submit"))
    return
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
  runCli().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exit(1) })
}
