import { render, useKeyboard, usePaste, useRenderer, useTerminalDimensions } from "@opentui/solid"
import { createMemo, createSignal, For, onCleanup, onMount } from "solid-js"
import { Effect, Exit } from "effect"
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"

type Target =
  | { type: "tmux_session"; session: string }
  | { type: "tmux_window"; session: string; windowId: string }
  | { type: "opencode"; session: string; pane: string }
  | { type: "directory"; path: string }

type AgentState = "running" | "done" | "attention" | "unknown"

interface TmuxSession { name: string; recency: number; path: string }
interface TmuxWindow { session: string; id: string; name: string; pane: string; pid: string; command: string; title: string; activity: number }
interface OpencodeStatus { directory: string; status: string; detail: string; title: string; age: string; session: string; pane: string }
interface DirectoryRow { path: string; source: "worktree" | "zoxide"; branch: string }
interface AgentReport { agent: string; state: AgentState; pane: string; updatedAt: number; hookEvent?: string }
interface DetailRow { kind: string; status: string; detail: string; title: string; age: string; state: AgentState; target: Target }
interface SessionRow { name: string; path: string; branch: string; flags: string; markers: string[]; age: string; recency: number; target: Target; details: DetailRow[]; searchText: string }
interface FuzzyResult { score: number; positions: number[] }
interface CachePayload { generatedAt: number; sessions: SessionRow[] }
interface BranchRow { name: string; value: string; kind: "worktree" | "local" | "remote" | "create"; path: string; recency: number; searchText: string }
type PickerMode = "jump" | "repo" | "new" | "branch" | "rename"

const repoRoot = new URL("../..", import.meta.url).pathname.replace(/\/$/, "")
const runtimeDir = `${Bun.env.XDG_RUNTIME_DIR ?? "/tmp"}/alt-k-tui-${process.getuid?.() ?? Bun.env.USER ?? "user"}`
const cachePath = `${runtimeDir}/state.json`
const pidPath = `${runtimeDir}/server.pid`
const agentStateDir = `${runtimeDir}/agent-state`
const refreshMs = Number(Bun.env.ALT_K_TUI_REFRESH_MS ?? 1500) || 1500
const spawnMode = Bun.env.ALT_K_TUI_MODE === "spawn"
const theme = {
  accent: "#7dd3fc",
  accentStrong: "#38bdf8",
  border: "#334155",
  header: "#e2e8f0",
  muted: "#94a3b8",
  ok: "#86efac",
  selectedBg: "#1e3a5f",
  selectedFg: "#f8fafc",
  warning: "#fde68a",
}

const runCommand = (cmd: string[], options: { cwd?: string; allowFailure?: boolean } = {}) =>
  Effect.tryPromise({
    try: async () => {
      const proc = Bun.spawn(cmd, { cwd: options.cwd ?? repoRoot, stdout: "pipe", stderr: "pipe" })
      const [stdout, stderr, exitCode] = await Promise.all([
        new Response(proc.stdout).text(),
        new Response(proc.stderr).text(),
        proc.exited,
      ])
      if (exitCode !== 0 && !options.allowFailure) throw new Error(stderr.trim() || `${cmd.join(" ")} exited ${exitCode}`)
      return stdout
    },
    catch: (error) => error instanceof Error ? error : new Error(String(error)),
  })

const parseTsv = (output: string) => output.split("\n").filter(Boolean).map((line) => line.split("\t"))
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))
const expandHome = (path: string) => path === "~" ? Bun.env.HOME ?? path : path.startsWith("~/") ? `${Bun.env.HOME}${path.slice(1)}` : path
const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(value, max))
const ageFromUnixSeconds = (seconds: number) => {
  if (seconds <= 0) return ""
  const diff = Math.max(0, Math.floor(Date.now() / 1000) - seconds)
  if (diff < 60) return `${diff}s`
  if (diff < 3600) return `${Math.floor(diff / 60)}m`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`
  return `${Math.floor(diff / 86400)}d`
}

const collectTmuxSessions = runCommand(["tmux", "list-sessions", "-F", "#{session_name}\t#{session_last_attached}\t#{session_activity}\t#{session_created}\t#{session_path}"]).pipe(
  Effect.map((output) => parseTsv(output).map((parts): TmuxSession => ({
    name: parts[0] ?? "",
    recency: Math.max(Number(parts[1] ?? 0) || 0, Number(parts[2] ?? 0) || 0, Number(parts[3] ?? 0) || 0),
    path: parts[4] ?? "",
  })).filter((session) => session.name.length > 0)),
)

const collectTmuxWindows = runCommand(["tmux", "list-windows", "-a", "-F", "#{session_name}\t#{window_id}\t#{window_name}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}\t#{window_activity}"]).pipe(
  Effect.map((output) => parseTsv(output).map((parts): TmuxWindow => ({
    session: parts[0] ?? "",
    id: parts[1] ?? "",
    name: parts[2] ?? "",
    pane: parts[3] ?? "",
    pid: parts[4] ?? "",
    command: (parts[5] ?? "").toLowerCase(),
    title: parts[6] ?? "",
    activity: Number(parts[7] ?? 0) || 0,
  })).filter((window) => window.session.length > 0)),
)

const collectOpencode = runCommand(["opencode-status", "--tsv"], { allowFailure: true }).pipe(
  Effect.map((output) => parseTsv(output).map((parts): OpencodeStatus | undefined => {
    if (parts.length < 7) return undefined
    const directory = parts[0] ?? ""
    if (directory.endsWith("(deleted)")) return undefined
    if (parts.length >= 8) {
      return { directory, status: parts[1] ?? "", detail: parts[2] ?? "", title: parts[3] ?? "", age: parts[4] ?? "", session: parts[5] ?? "", pane: parts[6] ?? "" }
    }
    return { directory, status: parts[1] ?? "", detail: "", title: parts[2] ?? "", age: parts[3] ?? "", session: parts[4] ?? "", pane: parts[5] ?? "" }
  }).filter((row): row is OpencodeStatus => Boolean(row?.session))),
)

const collectZoxideDirectories = runCommand(["zoxide", "query", "-l"], { allowFailure: true }).pipe(
  Effect.map((output) => output.split("\n").filter(Boolean).map((path): DirectoryRow => ({ path, source: "zoxide", branch: "" })).filter((row) => existsSync(expandHome(row.path)))),
)

const parseWorktrees = (output: string): DirectoryRow[] => output.trim().split("\n\n").flatMap((block) => {
  let path = ""
  let branch = ""
  for (const line of block.split("\n")) {
    if (line.startsWith("worktree ")) path = line.slice("worktree ".length)
    if (line.startsWith("branch refs/heads/")) branch = line.slice("branch refs/heads/".length)
    if (line === "detached") branch = "detached"
  }
  return path && existsSync(path) ? [{ path, source: "worktree" as const, branch }] : []
})

const devRoot = Bun.env.ALT_K_TUI_DEV_ROOT ?? `${Bun.env.HOME ?? ""}/dev`
const collectDevWorktrees = existsSync(devRoot)
  ? runCommand(["fd", "--hidden", "--exclude", ".archive", "--type", "directory", "^\\.git$", devRoot], { allowFailure: true }).pipe(
      Effect.flatMap((output) => Effect.forEach(
        output.split("\n").filter(Boolean),
        (gitDir) => runCommand(["git", "-C", dirname(gitDir), "worktree", "list", "--porcelain"], { allowFailure: true }),
        { concurrency: 8 },
      )),
      Effect.map((outputs) => outputs.flatMap(parseWorktrees)),
    )
  : Effect.succeed([] as DirectoryRow[])

const collectDirectories = Effect.all([collectDevWorktrees, collectZoxideDirectories], { concurrency: "unbounded" }).pipe(
  Effect.map(([worktrees, zoxide]) => {
    const directories = new Map<string, DirectoryRow>()
    for (const row of [...worktrees, ...zoxide]) {
      const path = expandHome(row.path)
      if (!directories.has(path)) directories.set(path, row)
    }
    return [...directories.values()]
  }),
)

const collectAgentReports = Effect.sync(() => {
  if (!existsSync(agentStateDir)) return []
  const reports: AgentReport[] = []
  for (const entry of readdirSync(agentStateDir)) {
    if (!entry.endsWith(".json")) continue
    try {
      const raw = JSON.parse(readFileSync(`${agentStateDir}/${entry}`, "utf8")) as Partial<AgentReport>
      if (!raw.agent || !raw.pane || !raw.state || !["running", "done", "attention", "unknown"].includes(raw.state)) continue
      reports.push({ agent: raw.agent, pane: raw.pane, state: raw.state, updatedAt: Number(raw.updatedAt ?? 0) || 0, hookEvent: raw.hookEvent })
    } catch {}
  }
  return reports
})

const gitMeta = (path: string) => Effect.gen(function* () {
  if (!path) return { branch: "", flags: "" }
  const gitPath = expandHome(path)
  const branch = yield* runCommand(["git", "-C", gitPath, "branch", "--show-current"], { allowFailure: true }).pipe(Effect.map((out) => out.trim()))
  if (!branch) return { branch: "", flags: "" }
  const dirty = yield* runCommand(["git", "-C", gitPath, "status", "--porcelain"], { allowFailure: true }).pipe(Effect.map((out) => out.trim().length > 0))
  return { branch, flags: dirty ? "dirty" : "clean" }
})

const isPiWindow = (window: TmuxWindow) => window.command === "pi" || ["pi", "pi-agent"].includes(window.name.toLowerCase()) || window.name.toLowerCase().startsWith("p:") || window.title.startsWith("π")
const isClaudeWindow = (window: TmuxWindow) => window.command === "claude" || window.name.toLowerCase() === "claude" || window.title.toLowerCase().includes("claude code")
const isCodexWindow = (window: TmuxWindow) => window.command === "codex" || window.name.toLowerCase() === "codex" || window.title.toLowerCase().includes("codex")
const processGroupContains = (pid: string, needle: string) => pid
  ? runCommand(["ps", "-o", "args=", "--forest", "-g", pid], { allowFailure: true }).pipe(Effect.map((output) => output.toLowerCase().includes(needle.toLowerCase())))
  : Effect.succeed(false)

const agentStateFromStatus = (status: string, detail = "", age = ""): AgentState => {
  const normalized = status.trim().toLowerCase()
  const normalizedDetail = detail.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (["done", "idle", "complete", "completed", "success", "succeeded"].includes(normalized)) return "done"
  if (normalized === "waiting question") return "attention"
  if (normalized.includes("tool running") && ["question", "permission", "approval"].some((word) => normalizedDetail.includes(word))) return "attention"
  if (["error", "failed", "failure", "blocked", "input", "attention", "confirm", "review", "question", "permission", "approval"].some((word) => normalized.includes(word))) return "attention"
  if (["running", "generating", "streaming", "working"].some((word) => normalized.includes(word))) return "running"
  return "unknown"
}
const codexStateFromTitle = (title: string): AgentState => {
  const normalized = title.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/.test(normalized)) return "running"
  if (/^[✓✔]/.test(normalized) || normalized.includes("done") || normalized.includes("complete")) return "done"
  if (/^[!✗×]/.test(normalized) || ["error", "failed", "blocked", "attention"].some((word) => normalized.includes(word))) return "attention"
  return "unknown"
}
const claudeStateFromTitle = (title: string): AgentState => {
  const normalized = title.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (/^[⠁⠂⠄⡀⢀⠠⠐⠈]/.test(normalized)) return "running"
  if (/^[✳✓✔]/.test(normalized) || normalized.includes("done") || normalized.includes("complete")) return "done"
  if (/^[!✗×]/.test(normalized) || ["error", "failed", "blocked", "attention"].some((word) => normalized.includes(word))) return "attention"
  return "unknown"
}

const sessionState = (session: SessionRow): AgentState => {
  const states = session.details.map((detail) => detail.state)
  if (states.includes("attention")) return "attention"
  if (states.includes("running")) return "running"
  if (states.includes("done")) return "done"
  return "unknown"
}

const sessionSortRank = (session: SessionRow) => ["attention", "running"].includes(sessionState(session)) ? 0 : 1

const buildSessionRows = (sessions: TmuxSession[], windows: TmuxWindow[], opencodes: OpencodeStatus[], directoryRows: DirectoryRow[], agentReports: AgentReport[]) => Effect.gen(function* () {
  const windowsBySession = Map.groupBy(windows, (window) => window.session)
  const opencodesBySession = Map.groupBy(opencodes, (row) => row.session)
  const reportsByPane = new Map(agentReports.map((report) => [report.pane, report]))
  const codexDetections = yield* Effect.forEach(
    windows,
    (window) => isCodexWindow(window)
      ? Effect.succeed([window.pane, true] as const)
      : processGroupContains(window.pid, "codex").pipe(Effect.map((detected) => [window.pane, detected] as const)),
    { concurrency: 8 },
  )
  const codexPanes = new Set(codexDetections.filter(([, detected]) => detected).map(([pane]) => pane))
  const rows: SessionRow[] = []

  for (const session of sessions) {
    const sessionWindows = windowsBySession.get(session.name) ?? []
    const sessionOpencodes = opencodesBySession.get(session.name) ?? []
    const meta = yield* gitMeta(session.path)
    const details: DetailRow[] = []

    for (const opencode of sessionOpencodes) {
      details.push({ kind: "opencode", status: opencode.status, detail: opencode.detail, title: opencode.title || opencode.directory, age: opencode.age, state: agentStateFromStatus(opencode.status, opencode.detail, opencode.age), target: { type: "opencode", session: opencode.session, pane: opencode.pane } })
    }

    const agentWindows = sessionWindows.filter((window) => isPiWindow(window) || isClaudeWindow(window) || codexPanes.has(window.pane))
    for (const window of agentWindows) {
      const kind = isPiWindow(window) ? "pi" : isClaudeWindow(window) ? "claude" : "codex"
      const report = reportsByPane.get(window.pane)
      const state = report?.agent === kind ? report.state : kind === "codex" ? codexStateFromTitle(window.title || window.name) : kind === "claude" ? claudeStateFromTitle(window.title || window.name) : "unknown"
      details.push({ kind, status: "", detail: "", title: window.title || window.name, age: "", state, target: { type: "tmux_window", session: window.session, windowId: window.id } })
    }

    if (details.length === 0) {
      details.push({ kind: "session", status: meta.flags, detail: "", title: session.path, age: ageFromUnixSeconds(session.recency), state: "unknown", target: { type: "tmux_session", session: session.name } })
    }

    const markers = [sessionOpencodes.length > 0 ? "oc" : "", sessionWindows.some(isPiWindow) ? "pi" : "", sessionWindows.some(isClaudeWindow) ? "C" : "", sessionWindows.some((window) => codexPanes.has(window.pane)) ? "codex" : ""].filter(Boolean)
    const row: SessionRow = { name: session.name, path: session.path, branch: meta.branch, flags: meta.flags, markers, age: ageFromUnixSeconds(session.recency), recency: session.recency, target: { type: "tmux_session", session: session.name }, details, searchText: "" }
    row.searchText = [row.name, row.path, row.branch, row.flags, row.markers.join(" "), ...row.details.flatMap((detail) => [detail.kind, detail.status, detail.detail, detail.title, detail.age])].join(" ").toLowerCase()
    rows.push(row)
  }

  const occupiedDirs = new Set([
    ...sessions.map((session) => expandHome(session.path)),
    ...opencodes.map((row) => expandHome(row.directory.replace(/ \([0-9]+\)$/, ""))),
  ])
  for (const directory of directoryRows) {
    const path = expandHome(directory.path)
    if (occupiedDirs.has(path)) continue
    occupiedDirs.add(path)
    const details: DetailRow[] = [{ kind: "directory", status: "", detail: directory.source, title: path, age: "", state: "unknown", target: { type: "directory", path } }]
    const row: SessionRow = { name: path, path, branch: directory.branch, flags: "", markers: [], age: "", recency: 0, target: { type: "directory", path }, details, searchText: "" }
    row.searchText = [row.name, row.path, row.branch, `${directory.source} directory`].join(" ").toLowerCase()
    rows.push(row)
  }

  return rows.sort((a, b) => sessionSortRank(a) - sessionSortRank(b) || b.recency - a.recency || a.name.localeCompare(b.name))
})

const collectSessions = Effect.all([collectTmuxSessions, collectTmuxWindows, collectOpencode, collectDirectories, collectAgentReports], { concurrency: "unbounded" }).pipe(
  Effect.flatMap(([sessions, windows, opencodes, directoryRows, agentReports]) => buildSessionRows(sessions, windows, opencodes, directoryRows, agentReports)),
)

const writeCache = (sessions: SessionRow[]) => Effect.sync(() => {
  mkdirSync(runtimeDir, { recursive: true })
  const tmpPath = `${cachePath}.${process.pid}.tmp`
  writeFileSync(tmpPath, JSON.stringify({ generatedAt: Date.now(), sessions } satisfies CachePayload))
  renameSync(tmpPath, cachePath)
})

const readCache = () => {
  try {
    const payload = JSON.parse(readFileSync(cachePath, "utf8")) as Partial<CachePayload>
    return Array.isArray(payload.sessions) ? payload.sessions as SessionRow[] : undefined
  } catch {
    return undefined
  }
}

const serverProgram = Effect.gen(function* () {
  yield* Effect.sync(() => {
    mkdirSync(runtimeDir, { recursive: true })
    writeFileSync(pidPath, `${process.pid}\n`)
    const cleanup = () => {
      try { unlinkSync(pidPath) } catch {}
    }
    process.once("exit", cleanup)
    process.once("SIGINT", () => { cleanup(); process.exit(0) })
    process.once("SIGTERM", () => { cleanup(); process.exit(0) })
  })

  while (true) {
    yield* collectSessions.pipe(
      Effect.flatMap(writeCache),
      Effect.catchAll((error) => Effect.sync(() => console.error(error instanceof Error ? error.message : String(error)))),
    )
    yield* Effect.promise(() => sleep(refreshMs))
  }
})

const cachedOrCollectedSessions = Effect.gen(function* () {
  const cached = yield* Effect.sync(readCache)
  if (cached) return cached
  const sessions = yield* collectSessions
  yield* writeCache(sessions)
  return sessions
})

const repositoryRows = (rows: SessionRow[]) => Effect.gen(function* () {
  const repositories = new Map<string, SessionRow>()
  for (const row of rows) {
    if (!row.path || !existsSync(expandHome(row.path))) continue
    const path = expandHome(row.path)
    const commonDir = yield* runCommand(["git", "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"], { allowFailure: true }).pipe(Effect.map((output) => output.trim()))
    if (!commonDir) continue
    const repoPath = commonDir.endsWith("/.git") ? commonDir.slice(0, -5) : commonDir
    const existing = repositories.get(commonDir)
    if (existing && !["main", "master"].includes(row.branch)) continue
    const name = repoPath.split("/").filter(Boolean).at(-1) ?? repoPath
    const details: DetailRow[] = [{ kind: "repository", status: "", detail: "choose branch next", title: repoPath, age: "", state: "unknown", target: { type: "directory", path } }]
    repositories.set(commonDir, { ...row, name, path, target: { type: "directory", path }, details, markers: [], age: "", searchText: `${name} ${repoPath} ${path}`.toLowerCase() })
  }
  return [...repositories.values()].sort((a, b) => a.name.localeCompare(b.name))
})

const collectBranchesSync = (repoPath: string): BranchRow[] => {
  const worktrees = new Map<string, string>()
  const worktreeResult = Bun.spawnSync(["git", "-C", repoPath, "worktree", "list", "--porcelain"], { stdout: "pipe", stderr: "ignore" })
  let currentPath = ""
  for (const line of worktreeResult.stdout.toString().split("\n")) {
    if (line.startsWith("worktree ")) currentPath = line.slice("worktree ".length)
    if (line.startsWith("branch refs/heads/")) worktrees.set(line.slice("branch refs/heads/".length), currentPath)
  }

  const refsResult = Bun.spawnSync(
    ["git", "-C", repoPath, "for-each-ref", "--format=%(refname)\t%(refname:short)\t%(committerdate:unix)", "refs/heads", "refs/remotes"],
    { stdout: "pipe", stderr: "ignore" },
  )
  if (refsResult.exitCode !== 0) return []
  const localBranches = new Set<string>()
  const remoteBranches = new Set<string>()
  const rows: BranchRow[] = []
  const refs = parseTsv(refsResult.stdout.toString())
  for (const [ref = "", short = "", timestamp = "0"] of refs) {
    if (!ref.startsWith("refs/heads/")) continue
    const name = ref.slice("refs/heads/".length)
    localBranches.add(name)
    const path = worktrees.get(name) ?? ""
    const kind = path ? "worktree" : "local"
    rows.push({ name, value: name, kind, path, recency: Number(timestamp) || 0, searchText: `${name} ${kind} ${path}`.toLowerCase() })
  }
  for (const [ref = "", short = "", timestamp = "0"] of refs) {
    if (!ref.startsWith("refs/remotes/") || ref.endsWith("/HEAD")) continue
    const slash = short.indexOf("/")
    const branchName = slash >= 0 ? short.slice(slash + 1) : short
    if (!branchName || localBranches.has(branchName) || remoteBranches.has(branchName)) continue
    remoteBranches.add(branchName)
    rows.push({ name: short, value: branchName, kind: "remote", path: "", recency: Number(timestamp) || 0, searchText: `${short} ${branchName} remote`.toLowerCase() })
  }
  const rank = { worktree: 0, local: 1, remote: 2, create: 3 }
  return rows.sort((a, b) => rank[a.kind] - rank[b.kind] || (a.kind === "remote" ? b.recency - a.recency : a.name.localeCompare(b.name)))
}

const switchBranchSessionSync = (repoPath: string, branch: string, create: boolean, base = "^") => {
  const wtArgs = ["wt", "-C", repoPath, "switch", ...(create ? ["--create"] : []), branch, "--no-cd", "--format", "json", ...(create && base ? ["--base", base] : [])]
  const switched = Bun.spawnSync(wtArgs, { cwd: repoRoot, stdout: "pipe", stderr: "pipe" })
  if (switched.exitCode !== 0) return { error: switched.stderr.toString().trim() || `wt exited ${switched.exitCode}` }
  try {
    const worktree = JSON.parse(switched.stdout.toString()) as { path?: string }
    if (!worktree.path) return { error: "Worktrunk did not return a worktree path" }
    const created = Bun.spawnSync([`${repoRoot}/bin/dotfiles-workflow`, "session", "--cwd", worktree.path], { cwd: repoRoot, stdout: "pipe", stderr: "pipe" })
    if (created.exitCode !== 0) return { error: created.stderr.toString().trim() || `session creation exited ${created.exitCode}` }
    const session = created.stdout.toString().trim()
    if (!session) return { error: "Session creation did not return a session name" }
    return { session }
  } catch {
    return { error: "Worktrunk returned invalid JSON" }
  }
}

const dumpState = collectSessions.pipe(
  Effect.flatMap((sessions) => Effect.sync(() => {
    console.log(JSON.stringify(sessions.map((session) => ({
      name: session.name,
      state: sessionState(session),
      recency: session.recency,
      branch: session.branch,
      flags: session.flags,
      markers: session.markers,
      agents: session.details
        .filter((detail) => ["opencode", "pi", "claude", "codex"].includes(detail.kind))
        .map((detail) => ({ kind: detail.kind, state: detail.state, status: detail.status, detail: detail.detail, title: detail.title })),
    })), null, 2))
  })),
)

const dumpCachedState = Effect.sync(() => {
  console.log(JSON.stringify(readCache() ?? [], null, 2))
})

const fuzzyResult = (text: string, query: string): FuzzyResult | undefined => {
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

const filterSessions = (sessions: SessionRow[], query: string) => {
  const normalized = query.trim().toLowerCase()
  if (!normalized) return sessions
  return sessions
    .map((session) => ({ session, match: fuzzyResult(session.searchText, normalized) }))
    .filter((row): row is { session: SessionRow; match: FuzzyResult } => Boolean(row.match))
    .sort((a, b) => b.match.score - a.match.score || sessionSortRank(a.session) - sessionSortRank(b.session) || b.session.recency - a.session.recency || a.session.name.localeCompare(b.session.name))
    .map((row) => row.session)
}

const spinnerFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
const stateGlyph = (state: AgentState, frame = 0) => state === "running" ? spinnerFrames[frame % spinnerFrames.length]! : state === "done" ? "✓" : state === "attention" ? "!" : "·"
const agentIcon = (kind: string) => kind === "opencode" ? "🤖" : kind === "pi" ? "π" : kind === "claude" ? "🥐" : kind === "codex" ? "📜" : kind === "directory" ? "" : kind
const agentSummary = (sessions: SessionRow[]) => ["oc", "pi", "C", "codex"].map((marker) => `[${marker}:${sessions.filter((session) => session.markers.includes(marker)).length}]`).join(" ")
const sessionGitMeta = (session: SessionRow) => [session.branch, session.flags === "dirty" ? "dirty" : ""].filter(Boolean).join(", ")
const selectedColor = (selected: boolean, state: AgentState) => selected ? theme.selectedFg : state === "attention" ? theme.warning : state === "running" ? theme.ok : theme.header
const targetLabel = (target: Target) => {
  switch (target.type) {
    case "opencode": return `opencode pane ${target.pane}`
    case "tmux_session": return `tmux session ${target.session}`
    case "tmux_window": return `tmux window ${target.windowId}`
    case "directory": return "directory"
  }
}
const enterAction = (target: Target) => {
  switch (target.type) {
    case "opencode": return "attach to opencode"
    case "tmux_session": return process.env.TMUX ? "switch to session" : "attach to session"
    case "tmux_window": return process.env.TMUX ? "switch to window" : "attach to window"
    case "directory": return "open directory session"
  }
}
const detailStatusLabel = (detail: DetailRow) => {
  if (detail.kind === "opencode" && detail.state === "done") return "idle"
  if (detail.status) return detail.status
  if (["pi", "claude", "codex"].includes(detail.kind) && detail.state !== "unknown") return detail.state
  return detail.kind
}
const detailColor = (state: AgentState) => state === "attention" ? theme.warning : state === "running" ? theme.ok : theme.muted

const openTarget = (target: Target) => {
  const command = (() => {
    switch (target.type) {
      case "opencode": return ["opencode-attach-target", target.session, target.pane]
      case "tmux_session": return ["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", target.session]
      case "tmux_window": return process.env.TMUX
        ? ["sh", "-c", "tmux switch-client -t \"$1\" && tmux select-window -t \"$2\"", "sh", target.session, target.windowId]
        : ["tmux", "attach-session", "-t", target.session, ";", "select-window", "-t", target.windowId]
      case "directory": return ["sh", "-c", "name=$(dotfiles-workflow session --cwd \"$1\") && tmux ${TMUX:+switch-client} ${TMUX:-attach-session} -t \"=$name\"", "sh", target.path]
    }
  })()
  return runCommand(command).pipe(Effect.asVoid)
}

const openTargetSync = (target: Target | undefined) => {
  if (!target) return
  switch (target.type) {
    case "opencode":
      Bun.spawnSync(["opencode-attach-target", target.session, target.pane], { cwd: repoRoot, stdout: "ignore", stderr: "ignore" })
      return
    case "tmux_session":
      Bun.spawnSync(["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", target.session], { cwd: repoRoot, stdout: "ignore", stderr: "ignore" })
      return
    case "tmux_window":
      Bun.spawnSync(
        process.env.TMUX
          ? ["sh", "-c", "tmux switch-client -t \"$1\" && tmux select-window -t \"$2\"", "sh", target.session, target.windowId]
          : ["tmux", "attach-session", "-t", target.session, ";", "select-window", "-t", target.windowId],
        { cwd: repoRoot, stdout: "ignore", stderr: "ignore" },
      )
      return
    case "directory": {
      const created = Bun.spawnSync([`${repoRoot}/bin/dotfiles-workflow`, "session", "--cwd", target.path], { cwd: repoRoot, stdout: "pipe", stderr: "ignore" })
      const name = created.stdout.toString().trim()
      if (name) Bun.spawnSync(["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", `=${name}`], { stdout: "ignore", stderr: "ignore" })
    }
  }
}

function HighlightText(props: { text: string; query: string; fg: string }) {
  const positions = createMemo(() => fuzzyResult(props.text, props.query)?.positions ?? [])
  return <>{Array.from(props.text).map((char, index) => positions().includes(index) ? <b>{char}</b> : char)}</>
}

function AgentBadge(props: { detail: DetailRow; selected: boolean; frame: number }) {
  const color = () => props.detail.state === "running" ? theme.ok : props.detail.state === "attention" ? theme.warning : props.selected ? theme.selectedFg : theme.muted
  return <text fg={color()} flexShrink={0}>{agentIcon(props.detail.kind)} {stateGlyph(props.detail.state, props.frame)}</text>
}

function SessionRowView(props: { session: SessionRow; selected: boolean; query: string; frame: number }) {
  const state = () => sessionState(props.session)
  const rowFg = () => selectedColor(props.selected, state())
  const agents = () => props.session.details.filter((detail) => ["opencode", "pi", "claude", "codex"].includes(detail.kind))
  return (
    <box flexDirection="row" height={1} backgroundColor={props.selected ? theme.selectedBg : undefined}>
      <text width={2} fg={rowFg()}>{props.selected ? ">" : " "}</text>
      <text width={2} fg={rowFg()}>{stateGlyph(state(), props.frame)}</text>
      <text fg={rowFg()} flexShrink={1}><HighlightText text={props.session.name} query={props.query} fg={rowFg()} /></text>
      <text width={2}> </text>
      <box flexDirection="row" gap={1} flexShrink={0}>
        <For each={agents()}>{(detail) => <AgentBadge detail={detail} selected={props.selected} frame={props.frame} />}</For>
      </box>
      <text flexGrow={1}> </text>
      <text flexShrink={0} fg={props.session.flags === "dirty" ? theme.warning : props.selected ? theme.selectedFg : theme.muted}>{sessionGitMeta(props.session) ? `[${sessionGitMeta(props.session)}]` : ""}</text>
    </box>
  )
}

function DetailBox(props: { session: SessionRow | undefined; frame: number }) {
  return (
    <box border borderStyle="single" borderColor={theme.border} height={8} flexDirection="column">
      {props.session ? (
        <>
          <box flexDirection="row" height={1}>
            <text fg={theme.accentStrong} flexShrink={1}>{props.session.name}</text>
            <text flexGrow={1}> </text>
            <text fg={props.session.flags === "dirty" ? theme.warning : theme.muted}>{sessionGitMeta(props.session)}</text>
          </box>
          <text height={1} fg={theme.muted}>{props.session.path || targetLabel(props.session.target)}</text>
          <box flexDirection="row" height={1}>
            <text width={8} fg={theme.muted}>Target:</text>
            <text fg={theme.header}>{targetLabel(props.session.target)}</text>
          </box>
          <For each={props.session.details.slice(0, 3)}>{(detail) => (
            <box flexDirection="row" height={1}>
              <text width={8} fg={theme.muted}>{detail.kind === "directory" || detail.kind === "session" ? "Info:" : "Agent:"}</text>
              <text fg={detailColor(detail.state)}>{agentIcon(detail.kind)} {stateGlyph(detail.state, props.frame)} {detail.kind}</text>
              <text fg={theme.muted}>  ·  </text>
              <text fg={theme.header}>{detailStatusLabel(detail)}</text>
              {detail.detail ? <text fg={theme.muted}>  ·  {detail.detail}</text> : null}
              {detail.title ? <text fg={theme.muted}>  ·  {detail.title}</text> : null}
              <text flexGrow={1}> </text>
              {detail.age ? <text fg={theme.muted}>{detail.age}</text> : null}
            </box>
          )}</For>
          <box flexDirection="row" height={1}>
            <text width={8} fg={theme.muted}>Enter:</text>
            <text fg={theme.header}>{enterAction(props.session.target)} · Alt-k open/create{props.session.target.type === "tmux_session" ? " · Alt-r rename" : ""} · Alt-d delete</text>
          </box>
        </>
      ) : <text fg={theme.muted}>No matches</text>}
    </box>
  )
}

function PickerRowView(props: { name: string; meta: string; selected: boolean; query: string }) {
  const color = () => props.selected ? theme.selectedFg : theme.header
  return (
    <box flexDirection="row" height={1} backgroundColor={props.selected ? theme.selectedBg : undefined}>
      <text width={2} fg={color()}>{props.selected ? ">" : " "}</text>
      <text fg={color()} flexShrink={1}><HighlightText text={props.name} query={props.query} fg={color()} /></text>
      <text flexGrow={1}> </text>
      <text fg={props.selected ? theme.selectedFg : theme.muted}>{props.meta}</text>
    </box>
  )
}

function App(props: { sessions: SessionRow[]; repositories: SessionRow[]; currentSession: string; onOpen: (target: Target | undefined) => void }) {
  const renderer = useRenderer()
  const dimensions = useTerminalDimensions()
  const [sessions, setSessions] = createSignal(props.sessions)
  const [mode, setMode] = createSignal<PickerMode>(spawnMode ? "repo" : "jump")
  const [query, setQuery] = createSignal("")
  const initialIndex = props.sessions.findIndex((row) => row.target.type === "tmux_session" && row.target.session === props.currentSession)
  const [index, setIndex] = createSignal(Math.max(0, initialIndex))
  const [frame, setFrame] = createSignal(0)
  const [repository, setRepository] = createSignal<SessionRow>()
  const [branches, setBranches] = createSignal<BranchRow[]>([])
  const [branchName, setBranchName] = createSignal("")
  const [base, setBase] = createSignal("^")
  const [renameName, setRenameName] = createSignal("")
  const [renameSession, setRenameSession] = createSignal<SessionRow>()
  const [deleteSession, setDeleteSession] = createSignal<SessionRow>()
  const [newField, setNewField] = createSignal<"branch" | "base">("branch")
  const [error, setError] = createSignal("")
  const [fetchStatus, setFetchStatus] = createSignal<"" | "fetching" | "done" | "failed">("")
  let fetchRequest = 0

  const filteredSessions = createMemo(() => filterSessions(sessions(), query()))
  const filteredRepositories = createMemo(() => filterSessions(props.repositories, query()))
  const filteredBranches = createMemo(() => {
    const normalized = query().trim().toLowerCase()
    if (!normalized) return branches()
    const matches = branches()
      .map((branch) => ({ branch, match: fuzzyResult(branch.searchText, normalized) }))
      .filter((row): row is { branch: BranchRow; match: FuzzyResult } => Boolean(row.match))
      .sort((a, b) => b.match.score - a.match.score)
      .map((row) => row.branch)
    const exact = branches().some((branch) => branch.value.toLowerCase() === normalized || branch.name.toLowerCase() === normalized)
    return exact ? matches : [{ name: query().trim(), value: query().trim(), kind: "create" as const, path: "", recency: 0, searchText: `${normalized} create new branch` }, ...matches]
  })
  const activeLength = createMemo(() => mode() === "jump" ? filteredSessions().length : mode() === "repo" ? filteredRepositories().length : mode() === "branch" ? filteredBranches().length : 0)
  const selectedSession = createMemo(() => mode() === "jump" ? filteredSessions()[index()] : undefined)
  const selectedRepository = createMemo(() => mode() === "repo" ? filteredRepositories()[index()] : undefined)
  const selectedBranch = createMemo(() => mode() === "branch" ? filteredBranches()[index()] : undefined)
  const visibleCount = createMemo(() => Math.max(1, dimensions().height - 11))
  const visibleSessions = createMemo(() => visibleSlice(filteredSessions(), index(), visibleCount()))
  const visibleRepositories = createMemo(() => visibleSlice(filteredRepositories(), index(), visibleCount()))
  const visibleBranches = createMemo(() => visibleSlice(filteredBranches(), index(), visibleCount()))

  const resetList = (nextMode: PickerMode) => {
    setMode(nextMode)
    setQuery("")
    setIndex(0)
    setError("")
  }
  const updateIndex = (next: number) => setIndex(clamp(next, 0, Math.max(0, activeLength() - 1)))
  const closeWith = (target?: Target) => {
    props.onOpen(target)
    openTargetSync(target)
    renderer.destroy()
  }
  const finishBranch = (branch: string, create: boolean) => {
    const repo = repository()
    if (!repo) return
    setError("")
    const result = switchBranchSessionSync(expandHome(repo.path), branch, create, base())
    if (!result.session) {
      setError(result.error ?? "Unable to open worktree")
      return
    }
    closeWith({ type: "tmux_session", session: result.session })
  }
  const appendInput = (raw: string) => {
    const text = raw.replace(/[\x00-\x1f\x7f]/g, "")
    if (!text) return
    if (mode() === "new") {
      if (newField() === "branch") setBranchName((value) => value + text)
      else setBase((value) => value + text)
    } else if (mode() === "rename") {
      setRenameName((value) => value + text)
    } else {
      setQuery((value) => value + text)
      setIndex(0)
    }
  }
  const refreshRemoteBranches = (repo: SessionRow) => {
    const request = ++fetchRequest
    const path = expandHome(repo.path)
    setFetchStatus("fetching")
    void (async () => {
      try {
        const proc = Bun.spawn(["git", "-C", path, "fetch", "--all", "--prune", "--quiet"], {
          stdin: "ignore",
          stdout: "ignore",
          stderr: "ignore",
          env: { ...Bun.env, GIT_TERMINAL_PROMPT: "0" },
        })
        proc.unref()
        const exitCode = await proc.exited
        if (request !== fetchRequest) return
        if (exitCode !== 0) {
          setFetchStatus("failed")
          return
        }
        setBranches(collectBranchesSync(path))
        setFetchStatus("done")
        setIndex((value) => clamp(value, 0, Math.max(0, filteredBranches().length - 1)))
      } catch {
        if (request === fetchRequest) setFetchStatus("failed")
      }
    })()
  }

  usePaste((event) => {
    appendInput(new TextDecoder().decode(event.bytes))
    event.preventDefault()
  })

  useKeyboard((key) => {
    if (deleteSession()) {
      if (key.name === "n" || key.name === "escape") {
        setDeleteSession(undefined)
        return
      }
      if (key.name !== "y") return
      const selected = deleteSession()!
      setDeleteSession(undefined)
      renderer.destroy()
      if (selected.target.type === "tmux_session") {
        const sessionName = selected.target.session
        const sessions = Bun.spawnSync(["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}"], { stdout: "pipe", stderr: "ignore" })
        const sessionId = parseTsv(sessions.stdout.toString()).find(([, name]) => name === sessionName)?.[0]
        if (sessionId) Bun.spawnSync(["tmux", "kill-session", "-t", sessionId], { stdout: "ignore", stderr: "ignore" })
      } else if (selected.branch && selected.path) {
        Bun.spawnSync([`${repoRoot}/bin/worktree-delete`, expandHome(selected.path)], { stdin: "inherit", stdout: "inherit", stderr: "inherit" })
      }
      return
    }
    if (key.meta && key.name === "k") return resetList("repo")
    if (key.meta && key.name === "r" && mode() === "jump") {
      const selected = selectedSession()
      if (selected?.target.type !== "tmux_session") return
      setRenameSession(selected)
      setRenameName(selected.target.session)
      setError("")
      setMode("rename")
      return
    }
    if (key.ctrl && key.name === "r" && mode() === "branch" && repository()) {
      refreshRemoteBranches(repository()!)
      return
    }
    if (key.name === "escape") {
      if (mode() === "rename") {
        setMode("jump")
        setError("")
        return
      }
      if (mode() === "new") {
        const name = branchName()
        resetList("branch")
        setQuery(name)
        return
      }
      if (mode() === "branch") return resetList("repo")
      if (query()) {
        setQuery("")
        setIndex(0)
        return
      }
      if (mode() === "repo") return resetList("jump")
      return closeWith()
    }
    if (key.name === "tab" && mode() === "new") {
      setNewField((field) => field === "branch" ? "base" : "branch")
      return
    }
    if (key.name === "backspace") {
      if (mode() === "new") {
        if (newField() === "branch") setBranchName((value) => value.slice(0, -1))
        else setBase((value) => value.slice(0, -1))
      } else if (mode() === "rename") {
        setRenameName((value) => value.slice(0, -1))
      } else {
        setQuery((value) => value.slice(0, -1))
        setIndex(0)
      }
      return
    }
    if (key.name === "up") return updateIndex(index() + 1)
    if (key.name === "down") return updateIndex(index() - 1)
    if (key.name === "return") {
      if (mode() === "rename" && renameSession()?.target.type === "tmux_session" && renameName().trim()) {
        const row = renameSession()!
        const oldName = row.target.type === "tmux_session" ? row.target.session : ""
        const found = Bun.spawnSync(["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}"], { stdout: "pipe", stderr: "pipe" })
        const sessionId = parseTsv(found.stdout.toString()).find(([, name]) => name === oldName)?.[0] ?? ""
        if (found.exitCode !== 0 || !sessionId) {
          setError(found.stderr.toString().trim() || "Selected session no longer exists")
          return
        }
        const renamed = Bun.spawnSync(["tmux", "rename-session", "-t", sessionId, renameName().trim()], { stdout: "pipe", stderr: "pipe" })
        if (renamed.exitCode !== 0) {
          setError(renamed.stderr.toString().trim() || "Unable to rename session")
          return
        }
        const refreshed = Bun.spawnSync(["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}"], { stdout: "pipe", stderr: "pipe" })
        const actual = parseTsv(refreshed.stdout.toString()).find(([id]) => id === sessionId)?.[1] || renameName().trim()
        const updateTarget = (target: Target): Target => target.type === "tmux_session" ? { ...target, session: actual } : target.type === "tmux_window" || target.type === "opencode" ? { ...target, session: actual } : target
        row.name = actual
        row.target = updateTarget(row.target)
        row.details = row.details.map((detail) => ({ ...detail, target: updateTarget(detail.target) }))
        row.searchText = `${actual} ${row.searchText}`.toLowerCase()
        setRenameSession(undefined)
        resetList("jump")
        setIndex(Math.max(0, sessions().indexOf(row)))
        return
      }
      if (mode() === "jump") return closeWith(selectedSession()?.target)
      if (mode() === "repo") {
        const repo = selectedRepository()
        if (!repo) return
        setRepository(repo)
        setBranches(collectBranchesSync(expandHome(repo.path)))
        resetList("branch")
        refreshRemoteBranches(repo)
        return
      }
      if (mode() === "branch" && selectedBranch()?.kind === "create") {
        setBranchName(selectedBranch()!.value)
        setBase("^")
        setNewField("base")
        return resetList("new")
      }
      if (mode() === "branch" && selectedBranch()) return finishBranch(selectedBranch()!.value, false)
      if (mode() === "new" && branchName().trim()) return finishBranch(branchName().trim(), true)
      return
    }
    if (key.meta && key.name === "d" && mode() === "jump") {
      const selected = selectedSession()
      if (!selected) return
      setDeleteSession(selected)
      return
    }
    if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) appendInput(key.sequence)
  }, {})

  onMount(() => {
    const interval = setInterval(() => setFrame((value) => value + 1), 120)
    const cacheInterval = setInterval(() => {
      const refreshed = readCache()
      if (!refreshed) return
      const byName = new Map(refreshed.map((session) => [session.name, session]))
      const currentNames = new Set(sessions().map((session) => session.name))
      setSessions([
        ...sessions().map((session) => byName.get(session.name) ?? session),
        ...refreshed.filter((session) => !currentNames.has(session.name)),
      ])
    }, 500)
    onCleanup(() => {
      clearInterval(interval)
      clearInterval(cacheInterval)
    })
  })

  const title = () => mode() === "jump" ? "Jump" : mode() === "repo" ? "Open or create branch · choose repository" : mode() === "branch" ? `Open or create branch · ${repository()?.name ?? ""}` : mode() === "rename" ? "Rename tmux session" : `New branch · ${repository()?.name ?? ""}`

  return (
    <box flexDirection="column" width="100%" height="100%">
      <box height={1} flexDirection="row">
        <text fg={theme.accentStrong}>{title()}</text>
        <text flexGrow={1}> </text>
        <text fg={fetchStatus() === "failed" ? theme.warning : theme.muted}>Alt-k open/create  {mode() === "jump" && selectedSession()?.target.type === "tmux_session" ? "Alt-r rename" : ""}{mode() === "branch" ? `^r refresh · ${fetchStatus() === "fetching" ? "fetching remotes…" : fetchStatus() === "failed" ? "fetch failed" : fetchStatus() === "done" ? "remotes synced" : ""}` : ""}  Esc back</text>
      </box>
      <box border borderStyle="single" borderColor={theme.border} flexGrow={1} flexDirection="column" justifyContent="flex-end">
        {mode() === "jump" ? <For each={visibleSessions()}>{(session) => <SessionRowView session={session} selected={session === selectedSession()} query={query()} frame={frame()} />}</For> : null}
        {mode() === "repo" ? <For each={visibleRepositories()}>{(repo) => <PickerRowView name={repo.name} meta={repo.path} selected={repo === selectedRepository()} query={query()} />}</For> : null}
        {mode() === "branch" ? <For each={visibleBranches()}>{(branch) => <PickerRowView name={branch.name} meta={branch.kind === "worktree" ? `worktree · ${branch.path}` : branch.kind === "create" ? "create new branch" : branch.kind === "remote" ? `remote${branch.recency ? ` · ${ageFromUnixSeconds(branch.recency)}` : ""}` : branch.kind} selected={branch === selectedBranch()} query={query()} />}</For> : null}
        {mode() === "new" ? (
          <box flexDirection="column" padding={2}>
            <text fg={newField() === "branch" ? theme.accentStrong : theme.header}>Branch: {branchName()}{newField() === "branch" ? "_" : ""}</text>
            <text fg={newField() === "base" ? theme.accentStrong : theme.header}>Base:   {base()}{newField() === "base" ? "_" : ""}</text>
            <text fg={theme.muted}>Tab changes field · Enter creates worktree and session</text>
          </box>
        ) : mode() === "rename" ? (
          <box flexDirection="column" padding={2}>
            <text fg={theme.accentStrong}>Session: {renameName()}_</text>
            <text fg={theme.muted}>Enter renames only the tmux display label</text>
          </box>
        ) : null}
      </box>
      {deleteSession() ? (
        <box border borderStyle="single" borderColor={theme.warning} height={8} flexDirection="column" padding={1}>
          <text fg={theme.warning}>Destroy {deleteSession()!.target.type === "tmux_session" ? "session" : "worktree"} '{deleteSession()!.name}'?</text>
          <text fg={theme.header}>Press y to confirm or n to cancel.</text>
        </box>
      ) : mode() === "jump" ? <DetailBox session={selectedSession()} frame={frame()} /> : (
        <box border borderStyle="single" borderColor={theme.border} height={8} flexDirection="column">
          <text fg={theme.header}>{mode() === "rename" ? renameSession()?.path ?? "" : mode() === "repo" ? selectedRepository()?.path ?? "Select a repository" : repository()?.path ?? "Select a repository"}</text>
          <text fg={theme.muted}>{mode() === "branch" ? "Worktrees, local branches, and recently updated remote branches; remotes refresh in the background" : mode() === "new" ? "Worktrunk will create the branch, worktree, and setup hooks" : mode() === "rename" ? "Canonical worktree identity and included agents are unchanged" : "Enter chooses repository"}</text>
          {error() ? <text fg={theme.warning}>{error()}</text> : null}
        </box>
      )}
      {mode() !== "new" && mode() !== "rename" ? (
        <box flexDirection="row" height={1}>
          <text fg={theme.accent}>{"> "}{query()}_</text>
          <text flexGrow={1}> </text>
          <text fg={theme.muted}>{activeLength()} items</text>
        </box>
      ) : <box height={1}><text fg={theme.muted}>{mode() === "rename" ? "Enter rename · Esc cancel" : "Enter create · Tab field · Esc branch picker"}</text></box>}
    </box>
  )
}

const visibleSlice = <T,>(rows: T[], index: number, count: number) => {
  const start = Math.max(0, Math.min(rows.length - count, index - count + 1))
  return rows.slice(start, start + count).reverse()
}

const program = process.argv.includes("--server") ? serverProgram : process.argv.includes("--dump-cache") ? dumpCachedState : process.argv.includes("--dump-state") ? dumpState : Effect.gen(function* () {
  const sessions = yield* cachedOrCollectedSessions
  const repositories = yield* repositoryRows(sessions)
  let currentSession = ""
  if (Bun.env.TMUX) currentSession = yield* runCommand(["tmux", "display-message", "-p", "#{session_name}"], { allowFailure: true }).pipe(Effect.map((output) => output.trim()))
  let target: Target | undefined
  yield* Effect.tryPromise({
    try: () => render(() => <App sessions={sessions} repositories={repositories} currentSession={currentSession} onOpen={(next) => { target = next }} />, { exitOnCtrlC: true }),
    catch: (error) => error instanceof Error ? error : new Error(String(error)),
  })
})

Effect.runPromiseExit(program).then((exit) => {
  if (Exit.isFailure(exit)) {
    console.error(exit.cause.toString())
    process.exitCode = 1
  }
})
