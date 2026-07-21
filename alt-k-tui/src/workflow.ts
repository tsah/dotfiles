import { createHash } from "node:crypto"
import { realpathSync } from "node:fs"
import { basename, dirname, resolve } from "node:path"

export type Harness = "pi" | "claude" | "opencode"
export interface WorktreeIdentity { path: string; commonDir: string; repo: string; branch: string }

async function command(argv: string[], cwd?: string, allowFailure = false) {
  const proc = Bun.spawn(argv, { cwd, stdout: "pipe", stderr: "pipe" })
  const [stdout, stderr, code] = await Promise.all([new Response(proc.stdout).text(), new Response(proc.stderr).text(), proc.exited])
  if (code !== 0 && !allowFailure) throw new Error(stderr.trim() || `${argv.join(" ")} exited ${code}`)
  return { stdout: stdout.trim(), stderr: stderr.trim(), code }
}

export async function identity(cwd = process.cwd()): Promise<WorktreeIdentity> {
  const top = (await command(["git", "rev-parse", "--show-toplevel"], cwd)).stdout
  const commonRaw = (await command(["git", "rev-parse", "--git-common-dir"], top)).stdout
  const commonDir = realpathSync(resolve(top, commonRaw))
  const branch = (await command(["git", "branch", "--show-current"], top)).stdout || "detached"
  return { path: realpathSync(top), commonDir, repo: basename(dirname(commonDir)), branch }
}

const safeName = (value: string) => value.replace(/[.:]/g, "-").replace(/[^A-Za-z0-9_@-]/g, "-").slice(0, 80)
const realpathSafe = (path: string) => { try { return realpathSync(path) } catch { return resolve(path) } }

async function sessionForPath(path: string) {
  const canonical = realpathSafe(path)
  const result = await command([
    "tmux", "list-sessions", "-F",
    "#{session_id}\t#{session_name}\t#{@dotfiles_worktree_path}\t#{@dotfiles_directory_path}\t#{session_path}\t#{session_activity}",
  ], undefined, true)
  if (result.code !== 0) return undefined
  return result.stdout.split("\n").filter(Boolean).map((line) => {
    const [id = "", name = "", worktreePath = "", directoryPath = "", sessionPath = "", activity = "0"] = line.split("\t")
    const taggedPath = worktreePath || directoryPath
    const candidatePath = taggedPath || sessionPath
    return { id, name, candidatePath, activity: Number(activity) || 0 }
  }).filter((session) => session.id && session.name && session.candidatePath && realpathSafe(session.candidatePath) === canonical)
    .sort((a, b) => b.activity - a.activity)[0]
}

export async function sessionName(id: WorktreeIdentity) {
  const human = safeName(`${id.repo}@${id.branch}`)
  const result = await command(["tmux", "display-message", "-p", "-t", `=${human}`, "#{@dotfiles_worktree_path}\t#{session_path}"], undefined, true)
  if (result.code !== 0 || !result.stdout) return human
  const [taggedPath = "", sessionPath = ""] = result.stdout.split("\t")
  if (realpathSafe(taggedPath || sessionPath) === id.path) return human
  return `${human}-${createHash("sha256").update(id.path).digest("hex").slice(0, 8)}`
}

export async function ensureSession(id: WorktreeIdentity) {
  const existing = await sessionForPath(id.path)
  const name = existing?.name ?? await sessionName(id)
  if (!existing && (await command(["tmux", "has-session", "-t", `=${name}`], undefined, true)).code !== 0) {
    await command(["tmux", "new-session", "-d", "-s", name, "-n", "main", "-c", id.path])
  }
  // Session IDs remain unambiguous even when a user-chosen name contains tmux target punctuation.
  const target = existing?.id || name
  await command(["tmux", "set-option", "-t", target, "@dotfiles_worktree_path", id.path])
  await command(["tmux", "set-option", "-t", target, "@dotfiles_git_common_dir", id.commonDir])
  return name
}

function harnessCommand(harness: Harness, cwd: string, prompt: string, agent?: string, signalFile?: string) {
  if (harness === "claude") return ["env", "-u", "ANTHROPIC_API_KEY", "claude", ...(agent ? ["--agent", agent] : []), prompt]
  if (harness === "opencode") return ["oc", ...(agent ? ["--agent", agent] : []), "--prompt", prompt]
  const presetArgs: string[] = []
  if (agent) {
    const helper = resolve(import.meta.dir, "../../bin/pi-agent-config")
    const resolved = Bun.spawnSync([helper, "--cwd", cwd, "--format", "json", agent], { stdout: "pipe", stderr: "pipe" })
    if (resolved.exitCode !== 0) throw new Error(resolved.stderr.toString().trim() || `Unknown pi agent: ${agent}`)
    const config = JSON.parse(resolved.stdout.toString())
    if (config.model) presetArgs.push("--model", config.model)
    if (config.thinking) presetArgs.push("--thinking", config.thinking)
    if (config.tools?.length) presetArgs.push("--tools", config.tools.join(","))
    const body = Bun.spawnSync([helper, "--cwd", cwd, "--body", agent], { stdout: "pipe" }).stdout.toString()
    if (body.trim()) presetArgs.push("--append-system-prompt", body)
  }
  const lifecycleEnv = signalFile ? [`PI_TMUX_WAIT_SIGNAL_FILE=${signalFile}`] : []
  return ["env", ...lifecycleEnv, "pi", ...presetArgs, prompt]
}

export async function spawnAgent(harness: Harness, cwd: string, prompt: string, agent?: string, requestedName?: string, wait = false) {
  const id = await identity(cwd)
  const session = await ensureSession(id)
  const prefix = requestedName || harness
  const existing = (await command(["tmux", "list-windows", "-t", `=${session}`, "-F", "#{window_name}"], undefined, true)).stdout.split("\n")
  let name = prefix; let n = 2
  while (existing.includes(name)) name = `${prefix}-${n++}`
  if (wait && harness !== "pi") throw new Error("settled waiting is currently supported only by pi")
  const signalFile = wait ? `${Bun.env.XDG_RUNTIME_DIR || "/tmp"}/dotfiles-worker-${process.pid}-${Date.now()}.json` : undefined
  const argv = harnessCommand(harness, id.path, prompt, agent, signalFile)
  const result = await command(["tmux", "new-window", "-d", "-P", "-F", "#{window_id}\t#{pane_id}", "-t", `=${session}`, "-n", name, "-c", id.path, ...argv])
  const [window, pane] = result.stdout.split("\t")
  await command(["tmux", "set-option", "-w", "-t", window!, "@dotfiles_agent", harness])
  const spawned: Record<string, unknown> = { identity: id, session, window, pane, name }
  if (signalFile) {
    const timeout = Number(Bun.env.DOTFILES_WORKER_WAIT_TIMEOUT || 600) * 1000
    const started = Date.now()
    while (!Bun.file(signalFile).size) {
      if (Date.now() - started >= timeout) throw new Error(`Timed out waiting for ${session}:${name}; worker remains running`)
      await Bun.sleep(200)
    }
    const settled = await Bun.file(signalFile).json(); await Bun.file(signalFile).delete()
    if (settled.status !== 0) throw new Error(settled.errorMessage || settled.stopReason || "worker failed")
    spawned.result = settled.reply
  }
  return spawned
}

export async function spawnWorktreeSession(branch: string, base?: string) {
  // Worktrunk remains authoritative for creation and project setup.
  const result = await command(["wt", "switch", "--create", branch, "--no-cd", "--format", "json", ...(base ? ["--base", base] : [])])
  let worktree: { path?: string }
  try { worktree = JSON.parse(result.stdout) }
  catch { throw new Error(`Worktrunk returned invalid JSON while creating '${branch}'`) }
  if (!worktree.path) throw new Error(`Worktrunk created '${branch}', but did not return its path`)
  const id = await identity(worktree.path)
  return { identity: id, session: await ensureSession(id) }
}

export async function spawnWorktree(harness: Harness, branch: string, prompt: string, options: { agent?: string; base?: string; window?: string; wait?: boolean } = {}) {
  const created = await spawnWorktreeSession(branch, options.base)
  return spawnAgent(harness, created.identity.path, prompt, options.agent, options.window, options.wait)
}

export async function ensureDirectorySession(directory: string) {
  const canonical = realpathSync(directory)
  const existing = await sessionForPath(canonical)
  if (existing) {
    await command(["tmux", "set-option", "-t", existing.id, "@dotfiles_directory_path", canonical])
    return existing.name
  }
  const base = safeName(basename(canonical)) || "shell"
  let name = base
  const current = await command(["tmux", "display-message", "-p", "-t", `=${name}`, "#{@dotfiles_worktree_path}\t#{@dotfiles_directory_path}\t#{session_path}"], undefined, true)
  if (current.code === 0) {
    const [worktreePath = "", directoryPath = "", sessionPath = ""] = current.stdout.split("\t")
    if (realpathSafe(worktreePath || directoryPath || sessionPath) !== canonical) name = `${base}-${createHash("sha256").update(canonical).digest("hex").slice(0, 8)}`
  }
  if ((await command(["tmux", "has-session", "-t", `=${name}`], undefined, true)).code !== 0) await command(["tmux", "new-session", "-d", "-s", name, "-n", "main", "-c", canonical])
  await command(["tmux", "set-option", "-t", name, "@dotfiles_directory_path", canonical])
  return name
}

export async function currentWorktreeAgents(cwd = process.cwd()) {
  const id = await identity(cwd)
  const output = await command(["tmux", "list-panes", "-a", "-F", "#{@dotfiles_worktree_path}\t#{@dotfiles_agent}\t#{session_name}\t#{window_id}\t#{pane_id}\t#{window_name}"], undefined, true)
  return output.stdout.split("\n").filter(Boolean).map((line) => line.split("\t")).filter((p) => realpathSafe(p[0]!) === id.path && p[1]).map((p) => ({ harness: p[1]!, session: p[2]!, window: p[3]!, pane: p[4]!, name: p[5]! }))
}

export async function sendToPane(pane: string, text: string, submit = true) {
  const buffer = `agent-bridge-${process.pid}`
  const proc = Bun.spawn(["tmux", "load-buffer", "-b", buffer, "-"], { stdin: "pipe" })
  proc.stdin.write(text); proc.stdin.end(); if (await proc.exited !== 0) throw new Error("tmux load-buffer failed")
  await command(["tmux", "paste-buffer", "-d", "-b", buffer, "-t", pane])
  if (submit) await command(["tmux", "send-keys", "-t", pane, "Enter"])
}
