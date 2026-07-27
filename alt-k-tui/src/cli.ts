#!/usr/bin/env bun
import { bootstrapRepositoryFromManifests, projectSnapshot, reconcileRepositoryWorkspaces, workspaceDetails, workspaceTree } from "./lineage"
import { currentWorktreeAgents, ensureDirectorySession, ensureSession, identity, sendToPane, spawnAgent, spawnWorktree, spawnWorktreeSession, type Harness } from "./workflow"

const args = process.argv.slice(2)
const take = (flag: string) => { const i = args.indexOf(flag); if (i < 0) return; const value = args[i + 1]; args.splice(i, 2); return value }
const has = (flag: string) => { const i = args.indexOf(flag); if (i < 0) return false; args.splice(i, 1); return true }
const cmd = args.shift()

async function main() {
  if (cmd === "identity") return console.log(JSON.stringify(await identity(take("--cwd") || process.cwd())))
  if (cmd === "agents") return console.log(JSON.stringify(await currentWorktreeAgents(take("--cwd") || process.cwd())))
  if (cmd === "session") {
    const cwd = take("--cwd") || process.cwd()
    try { return console.log(await ensureSession(await identity(cwd))) }
    catch { return console.log(await ensureDirectorySession(cwd)) }
  }
  if (cmd === "spawn-session") {
    const base = take("--base"); const branch = args.shift(); if (!branch) throw new Error("branch is required")
    return console.log(JSON.stringify(await spawnWorktreeSession(branch, base)))
  }
  if (cmd === "send") {
    const pane = take("--pane"); if (!pane) throw new Error("--pane is required")
    const text = take("--text") ?? await Bun.stdin.text(); await sendToPane(pane, text, !has("--no-submit")); return
  }
  if (cmd === "agent") {
    const harness = (take("--harness") || "pi") as Harness; const cwd = take("--cwd") || process.cwd()
    const agent = take("--agent"); const window = take("--window"); const wait = has("--wait"); const prompt = args.join(" "); if (!prompt) throw new Error("prompt is required")
    return console.log(JSON.stringify(await spawnAgent(harness, cwd, prompt, agent, window, wait)))
  }
  if (cmd === "worker") {
    const harness = (take("--harness") || "pi") as Harness
    const agent = take("--agent")
    const base = take("--base")
    const window = take("--window")
    const explicitParent = take("--parent")
    const noParent = has("--no-parent")
    if (explicitParent && noParent) throw new Error("--parent and --no-parent are mutually exclusive")
    const wait = has("--wait")
    const branch = args.shift(); const prompt = args.join(" "); if (!branch || !prompt) throw new Error("branch and prompt are required")
    return console.log(JSON.stringify(await spawnWorktree(harness, branch, prompt, { agent, base, window, wait, parentWorkspaceId: explicitParent, noParent })))
  }
  if (cmd === "workspace") {
    const subcommand = args.shift()
    const cwd = take("--cwd") || process.cwd()
    if (subcommand === "show") return console.log(JSON.stringify(workspaceDetails(cwd, { id: take("--id"), path: take("--path") }) ?? null, null, 2))
    if (subcommand === "tree") return console.log(JSON.stringify(workspaceTree(cwd), null, 2))
    if (subcommand === "project") return console.log(JSON.stringify(projectSnapshot(cwd), null, 2))
    if (subcommand === "reconcile") return console.log(JSON.stringify(reconcileRepositoryWorkspaces(cwd), null, 2))
    if (subcommand === "bootstrap") return console.log(JSON.stringify(bootstrapRepositoryFromManifests(cwd), null, 2))
    throw new Error("Usage: dotfiles-workflow workspace show|tree|project|reconcile|bootstrap")
  }
  throw new Error("Usage: dotfiles-workflow identity|agents|session|spawn-session|send|agent|worker|workspace ...")
}
main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exit(1) })
