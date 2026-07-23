import { render, useKeyboard, usePaste, useRenderer, useTerminalDimensions } from "@opentui/solid"
import { createMemo, createSignal, For, onCleanup, onMount } from "solid-js"
import { Effect, Exit } from "effect"
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import { buildTreeRows, defaultExpandedSessions, fuzzyResult, normalizeReportedState, sessionSortRank, sessionState, stateWithSeen } from "./model"
import type { AgentState, DetailRow, FuzzyResult, ReportedAgentState, SessionRow, Target, TreeRow } from "./model"

interface TmuxSession { name: string; recency: number; path: string; attached: boolean }
interface TmuxWindow { session: string; id: string; index: string; name: string; pane: string; pid: string; command: string; title: string; activity: number; active: boolean }
interface OpencodeStatus { directory: string; status: string; detail: string; title: string; age: string; session: string; pane: string; updatedAt: number; stablePane: string }
interface DirectoryRow { path: string; source: "worktree" | "zoxide"; branch: string }
interface AgentReport { agent: string; state: AgentState; pane: string; updatedAt: number; hookEvent?: string }
interface CachePayload { version: number; generatedAt: number; sessions: SessionRow[] }
interface BranchRow { name: string; value: string; kind: "worktree" | "local" | "remote" | "create"; path: string; recency: number; searchText: string }
interface DeleteAction { row: TreeRow; kind: "pane" | "session" | "worktree"; pane?: string; finalPane?: boolean }
type PickerMode = "jump" | "repo" | "new" | "branch" | "rename"

const repoRoot = new URL("../..", import.meta.url).pathname.replace(/\/$/, "")
const runtimeDir = `${Bun.env.XDG_RUNTIME_DIR ?? "/tmp"}/alt-k-tui-${process.getuid?.() ?? Bun.env.USER ?? "user"}`
const cachePath = `${runtimeDir}/state.json`
const pidPath = `${runtimeDir}/server.pid`
const versionPath = `${runtimeDir}/server.version`
const agentStateDir = `${runtimeDir}/agent-state`
const seenStateDir = `${runtimeDir}/seen-state`
const detectedTmuxSocket = Bun.env.TMUX?.split(",")[0] || Bun.spawnSync(["tmux", "display-message", "-p", "#{socket_path}"], { stdout: "pipe", stderr: "ignore" }).stdout.toString().trim() || "default"
const tmuxServerKey = `tmux:${detectedTmuxSocket}`
const refreshMs = Number(Bun.env.ALT_K_TUI_REFRESH_MS ?? 1500) || 1500
const cacheVersion = 3
const spawnMode = Bun.env.ALT_K_TUI_MODE === "spawn"
const theme = {
  accent: "#7dd3fc",
  accentStrong: "#38bdf8",
  border: "#334155",
  header: "#e2e8f0",
  muted: "#94a3b8",
  waiting: "#f87171",
  working: "#fb923c",
  ready: "#4ade80",
  idle: "#60a5fa",
  unknown: "#a78bfa",
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

const collectTmuxSessions = runCommand(["tmux", "list-sessions", "-F", "#{session_name}\t#{session_last_attached}\t#{session_activity}\t#{session_created}\t#{session_path}\t#{session_attached}"]).pipe(
  Effect.map((output) => parseTsv(output).map((parts): TmuxSession => ({
    name: parts[0] ?? "",
    recency: Math.max(Number(parts[1] ?? 0) || 0, Number(parts[2] ?? 0) || 0, Number(parts[3] ?? 0) || 0),
    path: parts[4] ?? "",
    attached: Number(parts[5] ?? 0) > 0,
  })).filter((session) => session.name.length > 0)),
)

const collectTmuxWindows = runCommand(["tmux", "list-windows", "-a", "-F", "#{session_name}\t#{window_id}\t#{window_index}\t#{window_name}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}\t#{window_activity}\t#{window_active}"]).pipe(
  Effect.map((output) => parseTsv(output).map((parts): TmuxWindow => ({
    session: parts[0] ?? "",
    id: parts[1] ?? "",
    index: parts[2] ?? "",
    name: parts[3] ?? "",
    pane: parts[4] ?? "",
    pid: parts[5] ?? "",
    command: (parts[6] ?? "").toLowerCase(),
    title: parts[7] ?? "",
    activity: Number(parts[8] ?? 0) || 0,
    active: parts[9] === "1",
  })).filter((window) => window.session.length > 0)),
)

const collectOpencode = runCommand([Bun.env.ALT_K_TUI_OPENCODE_STATUS || "opencode-status", "--tsv"], { allowFailure: true }).pipe(
  Effect.map((output) => parseTsv(output).map((parts): OpencodeStatus | undefined => {
    if (parts.length < 7) return undefined
    const directory = parts[0] ?? ""
    if (directory.endsWith("(deleted)")) return undefined
    if (parts.length >= 8) {
      return { directory, status: parts[1] ?? "", detail: parts[2] ?? "", title: parts[3] ?? "", age: parts[4] ?? "", session: parts[5] ?? "", pane: parts[6] ?? "", updatedAt: Number(parts[8] ?? 0) || 0, stablePane: parts[9] ?? "" }
    }
    return { directory, status: parts[1] ?? "", detail: "", title: parts[2] ?? "", age: parts[3] ?? "", session: parts[4] ?? "", pane: parts[5] ?? "", updatedAt: 0, stablePane: "" }
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
      const raw = JSON.parse(readFileSync(`${agentStateDir}/${entry}`, "utf8")) as Partial<AgentReport> & { state?: ReportedAgentState }
      if (!raw.agent || !raw.pane || !raw.state || !["blocked", "working", "done", "idle", "unknown", "running", "attention"].includes(raw.state)) continue
      reports.push({ agent: raw.agent, pane: raw.pane, state: normalizeReportedState(raw.state, raw.hookEvent), updatedAt: Number(raw.updatedAt ?? 0) || 0, hookEvent: raw.hookEvent })
    } catch {}
  }
  return reports
})

const readSeenState = () => {
  const seen = new Map<string, number>()
  if (!existsSync(seenStateDir)) return seen
  for (const entry of readdirSync(seenStateDir)) {
    if (!entry.endsWith(".json")) continue
    try {
      const record = JSON.parse(readFileSync(`${seenStateDir}/${entry}`, "utf8")) as { key?: string; seenAt?: number }
      if (record.key) seen.set(record.key, Number(record.seenAt ?? 0) || 0)
    } catch {}
  }
  return seen
}

const markSeen = (key: string, seenAt = Date.now()) => {
  mkdirSync(seenStateDir, { recursive: true })
  const target = `${seenStateDir}/${encodeURIComponent(key)}.json`
  const tmp = `${target}.${process.pid}.tmp`
  writeFileSync(tmp, JSON.stringify({ key, seenAt }))
  renameSync(tmp, target)
}

const paneCompletionKey = (pane: string) => `${tmuxServerKey}:pane:${pane}`
const windowCompletionKey = (window: string) => `${tmuxServerKey}:window:${window}`

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
  if (["done", "complete", "completed", "success", "succeeded"].includes(normalized)) return "done"
  if (normalized === "idle") return "idle"
  if (normalized === "waiting question") return "blocked"
  if (normalized.includes("tool running") && ["question", "permission", "approval"].some((word) => normalizedDetail.includes(word))) return "blocked"
  if (["error", "failed", "failure", "blocked", "input", "attention", "confirm", "review", "question", "permission", "approval"].some((word) => normalized.includes(word))) return "blocked"
  if (["running", "generating", "streaming", "working"].some((word) => normalized.includes(word))) return "working"
  return "unknown"
}
const opencodeState = (opencode: OpencodeStatus) => {
  const state = agentStateFromStatus(opencode.status, opencode.detail, opencode.age)
  return !opencode.updatedAt && state === "done" ? "idle" : state
}
const codexStateFromTitle = (title: string): AgentState => {
  const normalized = title.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (/^[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]/.test(normalized)) return "working"
  if (/^[✓✔]/.test(normalized) || normalized.includes("done") || normalized.includes("complete")) return "done"
  if (/^[!✗×]/.test(normalized) || ["error", "failed", "blocked", "attention"].some((word) => normalized.includes(word))) return "blocked"
  return "unknown"
}
const claudeStateFromTitle = (title: string): AgentState => {
  const normalized = title.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (/^[⠁⠂⠄⡀⢀⠠⠐⠈]/.test(normalized)) return "working"
  if (/^[✳✓✔]/.test(normalized) || normalized.includes("done") || normalized.includes("complete")) return "done"
  if (/^[!✗×]/.test(normalized) || ["error", "failed", "blocked", "attention"].some((word) => normalized.includes(word))) return "blocked"
  return "unknown"
}

const buildSessionRows = (sessions: TmuxSession[], windows: TmuxWindow[], opencodes: OpencodeStatus[], directoryRows: DirectoryRow[], agentReports: AgentReport[], seen: Map<string, number>) => Effect.gen(function* () {
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

    const opencodesByWindow = Map.groupBy(sessionOpencodes, (opencode) => {
      if (opencode.stablePane) return sessionWindows.find((window) => window.pane === opencode.stablePane)?.id ?? ""
      const prefix = `${opencode.session}:`
      const windowIndex = opencode.pane.startsWith(prefix) ? opencode.pane.slice(prefix.length).split(".")[0] : ""
      return sessionWindows.find((window) => window.index === windowIndex)?.id ?? ""
    })

    for (const window of sessionWindows) {
      const focused = session.attached && window.active
      const windowOpencodes = opencodesByWindow.get(window.id) ?? []
      for (const opencode of windowOpencodes) {
        const completionKey = paneCompletionKey(opencode.stablePane || window.pane || opencode.pane)
        const sourceState = opencodeState(opencode)
        const state = stateWithSeen(sourceState, opencode.updatedAt, seen.get(completionKey), focused)
        if (sourceState === "done" && focused) {
          markSeen(completionKey)
          seen.set(completionKey, Date.now())
        }
        details.push({ kind: "opencode", status: opencode.status, detail: opencode.detail, title: opencode.title || window.name || opencode.directory, age: opencode.age, state, target: { type: "opencode", session: opencode.session, pane: opencode.stablePane || window.pane || opencode.pane }, completionKey, updatedAt: opencode.updatedAt })
      }
      if (windowOpencodes.length > 0) continue

      const kind = isPiWindow(window) ? "pi" : isClaudeWindow(window) ? "claude" : codexPanes.has(window.pane) ? "codex" : "window"
      const report = reportsByPane.get(window.pane)
      const sourceState = report?.agent === kind ? report.state : kind === "codex" ? codexStateFromTitle(window.title || window.name) : kind === "claude" ? claudeStateFromTitle(window.title || window.name) : "unknown"
      const updatedAt = report?.agent === kind ? report.updatedAt : window.activity * 1000
      const completionKey = kind === "window" ? windowCompletionKey(window.id) : paneCompletionKey(window.pane)
      const state = stateWithSeen(sourceState, updatedAt, seen.get(completionKey), focused)
      if (sourceState === "done" && focused) {
        markSeen(completionKey)
        seen.set(completionKey, Date.now())
      }
      details.push({ kind, status: kind === "window" ? window.command : "", detail: "", title: kind === "window" ? window.name || window.title : window.title || window.name, age: ageFromUnixSeconds(window.activity), state, target: { type: "tmux_window", session: window.session, windowId: window.id, pane: window.pane }, completionKey, updatedAt })
    }

    for (const opencode of opencodesByWindow.get("") ?? []) {
      const completionKey = paneCompletionKey(opencode.stablePane || opencode.pane)
      const sourceState = opencodeState(opencode)
      const state = stateWithSeen(sourceState, opencode.updatedAt, seen.get(completionKey))
      details.push({ kind: "opencode", status: opencode.status, detail: opencode.detail, title: opencode.title || opencode.directory, age: opencode.age, state, target: { type: "opencode", session: opencode.session, pane: opencode.stablePane || opencode.pane }, completionKey, updatedAt: opencode.updatedAt })
    }

    if (details.length === 0) {
      details.push({ kind: "session", status: meta.flags, detail: "", title: session.path, age: ageFromUnixSeconds(session.recency), state: "unknown", target: { type: "tmux_session", session: session.name }, updatedAt: 0 })
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
    const details: DetailRow[] = [{ kind: "directory", status: "", detail: directory.source, title: path, age: "", state: "unknown", target: { type: "directory", path }, updatedAt: 0 }]
    const row: SessionRow = { name: path, path, branch: directory.branch, flags: "", markers: [], age: "", recency: 0, target: { type: "directory", path }, details, searchText: "" }
    row.searchText = [row.name, row.path, row.branch, `${directory.source} directory`].join(" ").toLowerCase()
    rows.push(row)
  }

  return rows.sort((a, b) => sessionSortRank(a) - sessionSortRank(b) || b.recency - a.recency || a.name.localeCompare(b.name))
})

const collectSessions = Effect.all([collectTmuxSessions, collectTmuxWindows, collectOpencode, collectDirectories, collectAgentReports, Effect.sync(readSeenState)], { concurrency: "unbounded" }).pipe(
  Effect.flatMap(([sessions, windows, opencodes, directoryRows, agentReports, seen]) => buildSessionRows(sessions, windows, opencodes, directoryRows, agentReports, seen)),
)

const writeCache = (sessions: SessionRow[]) => Effect.sync(() => {
  mkdirSync(runtimeDir, { recursive: true })
  const tmpPath = `${cachePath}.${process.pid}.tmp`
  writeFileSync(tmpPath, JSON.stringify({ version: cacheVersion, generatedAt: Date.now(), sessions } satisfies CachePayload))
  renameSync(tmpPath, cachePath)
})

const readCache = () => {
  try {
    const payload = JSON.parse(readFileSync(cachePath, "utf8")) as Partial<CachePayload>
    return payload.version === cacheVersion && Array.isArray(payload.sessions) ? payload.sessions as SessionRow[] : undefined
  } catch {
    return undefined
  }
}

const serverProgram = Effect.gen(function* () {
  yield* Effect.sync(() => {
    mkdirSync(runtimeDir, { recursive: true })
    writeFileSync(pidPath, `${process.pid}\n`)
    writeFileSync(versionPath, `${cacheVersion}\n`)
    const cleanup = () => {
      try {
        if (readFileSync(pidPath, "utf8").trim() === String(process.pid)) unlinkSync(pidPath)
      } catch {}
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
    const details: DetailRow[] = [{ kind: "repository", status: "", detail: "choose branch next", title: repoPath, age: "", state: "unknown", target: { type: "directory", path }, updatedAt: 0 }]
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

const filterSessions = (sessions: SessionRow[], query: string) => {
  const normalized = query.trim().toLowerCase()
  if (!normalized) return sessions
  return sessions
    .map((session) => ({ session, match: fuzzyResult(session.searchText, normalized) }))
    .filter((row): row is { session: SessionRow; match: FuzzyResult } => Boolean(row.match))
    .sort((a, b) => b.match.score - a.match.score || sessionSortRank(a.session) - sessionSortRank(b.session) || b.session.recency - a.session.recency || a.session.name.localeCompare(b.session.name))
    .map((row) => row.session)
}

const stateGlyph = (state: AgentState) => state === "blocked" ? "!" : state === "working" ? "●" : state === "done" ? "✓" : state === "idle" ? "○" : "?"
const stateColor = (state: AgentState) => state === "blocked" ? theme.waiting : state === "working" ? theme.working : state === "done" ? theme.ready : state === "idle" ? theme.idle : theme.unknown
const stateLabel = (state: AgentState) => state === "blocked" ? "waiting" : state === "done" ? "ready" : state
const sessionGitMeta = (session: SessionRow) => [session.branch, session.flags === "dirty" ? "dirty" : ""].filter(Boolean).join(", ")
const selectedColor = (selected: boolean) => selected ? theme.selectedFg : theme.header
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
  if (["opencode", "pi", "claude", "codex"].includes(detail.kind) && detail.state !== "unknown") return stateLabel(detail.state)
  if (detail.status) return detail.status
  return detail.kind
}

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
  if (!target) return false
  switch (target.type) {
    case "opencode": return Bun.spawnSync(["opencode-attach-target", target.session, target.pane], { cwd: repoRoot, stdout: "ignore", stderr: "ignore" }).exitCode === 0
    case "tmux_session": return Bun.spawnSync(["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", target.session], { cwd: repoRoot, stdout: "ignore", stderr: "ignore" }).exitCode === 0
    case "tmux_window": return Bun.spawnSync(
        process.env.TMUX
          ? ["sh", "-c", "tmux switch-client -t \"$1\" && tmux select-window -t \"$2\"", "sh", target.session, target.windowId]
          : ["tmux", "attach-session", "-t", target.session, ";", "select-window", "-t", target.windowId],
        { cwd: repoRoot, stdout: "ignore", stderr: "ignore" },
      ).exitCode === 0
    case "directory": {
      const created = Bun.spawnSync([`${repoRoot}/bin/dotfiles-workflow`, "session", "--cwd", target.path], { cwd: repoRoot, stdout: "pipe", stderr: "ignore" })
      const name = created.stdout.toString().trim()
      return Boolean(name) && Bun.spawnSync(["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", `=${name}`], { stdout: "ignore", stderr: "ignore" }).exitCode === 0
    }
  }
}

const paneForTargetSync = (target: Target) => {
  if (target.type !== "tmux_window" && target.type !== "opencode") return ""
  const resolved = Bun.spawnSync(["tmux", "display-message", "-p", "-t", target.pane, "#{pane_id}"], { stdout: "pipe", stderr: "ignore" })
  return resolved.exitCode === 0 ? resolved.stdout.toString().trim() : ""
}

const sessionPaneIdsSync = (session: string) => {
  const result = Bun.spawnSync(["tmux", "list-panes", "-s", "-t", `=${session}`, "-F", "#{pane_id}"], { stdout: "pipe", stderr: "ignore" })
  return result.exitCode === 0 ? result.stdout.toString().split("\n").filter(Boolean) : []
}

const isLinkedWorktreeSync = (path: string) => {
  if (!path || !existsSync(expandHome(path))) return false
  const result = Bun.spawnSync(["git", "-C", expandHome(path), "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir"], { stdout: "pipe", stderr: "ignore" })
  if (result.exitCode !== 0) return false
  const [gitDir, commonDir] = result.stdout.toString().trim().split("\n")
  return Boolean(gitDir && commonDir && gitDir !== commonDir)
}

const killSessionSync = (sessionName: string) => {
  const sessions = Bun.spawnSync(["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}"], { stdout: "pipe", stderr: "ignore" })
  const sessionId = parseTsv(sessions.stdout.toString()).find(([, name]) => name === sessionName)?.[0]
  if (sessionId) Bun.spawnSync(["tmux", "kill-session", "-t", sessionId], { stdout: "ignore", stderr: "ignore" })
}

function HighlightText(props: { text: string; query: string; fg: string }) {
  const positions = createMemo(() => fuzzyResult(props.text, props.query)?.positions ?? [])
  return <>{Array.from(props.text).map((char, index) => positions().includes(index) ? <b>{char}</b> : char)}</>
}

function TreeRowView(props: { row: TreeRow; selected: boolean; query: string; expanded: boolean }) {
  const rowFg = () => selectedColor(props.selected)
  const detail = () => props.row.detail
  const neutralWindow = () => detail()?.kind === "window"
  const rowStateGlyph = () => neutralWindow() ? "○" : stateGlyph(props.row.state)
  const rowStateColor = () => neutralWindow() ? theme.muted : stateColor(props.row.state)
  const expandable = () => props.row.session.details.some((row) => !["directory", "repository", "session"].includes(row.kind))
  const childName = () => detail()?.kind === "window" ? detail()!.title : detail()?.kind ?? ""
  const childTitle = () => detail()?.kind === "window" ? "" : detail()?.title || detail()?.detail || ""
  return (
    <box flexDirection="row" height={1} backgroundColor={props.selected ? theme.selectedBg : undefined}>
      <text width={2} fg={rowFg()}>{props.selected ? ">" : " "}</text>
      <text width={props.row.depth === 0 ? 2 : 4} fg={theme.muted}>{props.row.depth === 0 ? expandable() ? props.expanded ? "▾" : "▸" : " " : " "}</text>
      <text width={2} fg={rowStateColor()}>{rowStateGlyph()}</text>
      {detail() ? (
        <>
          <text width={12} fg={rowFg()}><HighlightText text={childName()} query={props.query} fg={rowFg()} /></text>
          <text fg={theme.muted} flexShrink={1}><HighlightText text={childTitle()} query={props.query} fg={theme.muted} /></text>
          <text flexGrow={1}> </text>
          <text width={9} flexShrink={0} fg={neutralWindow() ? theme.muted : stateColor(detail()!.state)}>{detailStatusLabel(detail()!)}</text>
        </>
      ) : (
        <text fg={rowFg()} flexShrink={1}><HighlightText text={props.row.session.name} query={props.query} fg={rowFg()} /></text>
      )}
      {props.row.depth === 0 ? (
        <>
          <text flexGrow={1}> </text>
          <text flexShrink={0} fg={props.row.session.flags === "dirty" ? theme.warning : props.selected ? theme.selectedFg : theme.muted}>{sessionGitMeta(props.row.session) ? `[${sessionGitMeta(props.row.session)}]` : ""}</text>
        </>
      ) : null}
    </box>
  )
}

function JumpFooter(props: { row: TreeRow | undefined }) {
  return (
    <box height={1} flexDirection="row">
      <text fg={theme.muted} flexShrink={1}>{props.row?.session.path ?? "No matches"}</text>
      <text flexGrow={1}> </text>
      <text fg={theme.muted} flexShrink={0}>{props.row?.depth === 0 ? "← collapse  → expand  Enter open" : "← parent  Enter focus"}</text>
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
  const initialExpanded = defaultExpandedSessions(props.sessions)
  const initialRows = buildTreeRows(props.sessions, "", { expandedSessions: initialExpanded, bottomUp: true })
  const [sessions, setSessions] = createSignal(props.sessions)
  const [expandedSessions, setExpandedSessions] = createSignal<ReadonlySet<string>>(initialExpanded)
  const [mode, setMode] = createSignal<PickerMode>(spawnMode ? "repo" : "jump")
  const [query, setQuery] = createSignal("")
  const initialIndex = initialRows.findIndex((row) => row.depth === 0 && row.target.type === "tmux_session" && row.target.session === props.currentSession)
  const [index, setIndex] = createSignal(Math.max(0, initialIndex))
  const [repository, setRepository] = createSignal<SessionRow>()
  const [branches, setBranches] = createSignal<BranchRow[]>([])
  const [branchName, setBranchName] = createSignal("")
  const [base, setBase] = createSignal("^")
  const [renameName, setRenameName] = createSignal("")
  const [renameSession, setRenameSession] = createSignal<SessionRow>()
  const [deleteAction, setDeleteAction] = createSignal<DeleteAction>()
  const [newField, setNewField] = createSignal<"branch" | "base">("branch")
  const [error, setError] = createSignal("")
  const [fetchStatus, setFetchStatus] = createSignal<"" | "fetching" | "done" | "failed">("")
  let fetchRequest = 0

  const treeRows = (rows = sessions(), search = query(), expanded = expandedSessions()) => buildTreeRows(rows, search, { expandedSessions: expanded, bottomUp: true })
  const filteredTreeRows = createMemo(() => treeRows())
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
  const activeLength = createMemo(() => mode() === "jump" ? filteredTreeRows().length : mode() === "repo" ? filteredRepositories().length : mode() === "branch" ? filteredBranches().length : 0)
  const selectedTreeRow = createMemo(() => mode() === "jump" ? filteredTreeRows()[index()] : undefined)
  const selectedParent = createMemo(() => selectedTreeRow()?.depth === 0 ? selectedTreeRow()!.session : undefined)
  const selectedRepository = createMemo(() => mode() === "repo" ? filteredRepositories()[index()] : undefined)
  const selectedBranch = createMemo(() => mode() === "branch" ? filteredBranches()[index()] : undefined)
  const visibleCount = createMemo(() => Math.max(1, dimensions().height - (mode() === "jump" && !deleteAction() ? 5 : 11)))
  const visibleTreeRows = createMemo(() => visibleSlice(filteredTreeRows(), index(), visibleCount()))
  const visibleRepositories = createMemo(() => visibleSlice(filteredRepositories(), index(), visibleCount()))
  const visibleBranches = createMemo(() => visibleSlice(filteredBranches(), index(), visibleCount()))

  const resetList = (nextMode: PickerMode) => {
    setMode(nextMode)
    setQuery("")
    const parentIndex = nextMode === "jump" ? treeRows(sessions(), "").findIndex((row) => row.depth === 0) : 0
    setIndex(Math.max(0, parentIndex))
    setError("")
  }
  const updateIndex = (next: number) => setIndex(clamp(next, 0, Math.max(0, activeLength() - 1)))
  const setExpanded = (session: string, expanded: boolean) => {
    const next = new Set(expandedSessions())
    if (expanded) next.add(session)
    else next.delete(session)
    setExpandedSessions(next)
    const rows = treeRows(sessions(), query(), next)
    const nextIndex = rows.findIndex((row) => row.depth === 0 && row.session.name === session)
    setIndex(Math.max(0, nextIndex))
  }
  const closeWith = (target?: Target, completionKey?: string) => {
    props.onOpen(target)
    const opened = target ? openTargetSync(target) : true
    if (opened && completionKey) markSeen(completionKey)
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
  const deleteActionForRow = (row: TreeRow): DeleteAction | undefined => {
    if (row.depth === 0) {
      if (row.target.type === "tmux_session") return { row, kind: "session" }
      if (row.session.branch && row.session.path) return { row, kind: "worktree" }
      return undefined
    }

    const pane = paneForTargetSync(row.target)
    if (!pane) return undefined
    const panes = sessionPaneIdsSync(row.session.name)
    if (panes.length !== 1 || panes[0] !== pane) return { row, kind: "pane", pane }
    if (isLinkedWorktreeSync(row.session.path)) return { row, kind: "worktree", pane, finalPane: true }
    return { row, kind: "session", pane, finalPane: true }
  }
  const requestDelete = (row: TreeRow) => setDeleteAction(deleteActionForRow(row))
  const deletePrompt = () => {
    const action = deleteAction()
    if (!action) return ""
    const row = action.row
    if (action.kind === "pane") return `Destroy pane '${row.detail?.title || row.detail?.kind || action.pane}'?`
    if (action.finalPane && action.kind === "worktree") return `Destroy final pane, session, and worktree '${row.session.branch || row.session.path}'?`
    if (action.finalPane) return `Destroy final pane and session '${row.session.name}'?`
    return `Destroy ${action.kind} '${row.session.name}'?`
  }

  usePaste((event) => {
    appendInput(new TextDecoder().decode(event.bytes))
    event.preventDefault()
  })

  useKeyboard((key) => {
    if (deleteAction()) {
      if (key.name === "n" || key.name === "escape") {
        setDeleteAction(undefined)
        return
      }
      if (key.name !== "y") return
      const action = deleteAction()!
      const currentAction = deleteActionForRow(action.row)
      if (!currentAction) {
        setDeleteAction(undefined)
        return
      }
      if (currentAction.kind !== action.kind || currentAction.pane !== action.pane || currentAction.finalPane !== action.finalPane) {
        setDeleteAction(currentAction)
        return
      }
      setDeleteAction(undefined)
      renderer.destroy()
      if (action.kind === "pane" && action.pane) Bun.spawnSync(["tmux", "kill-pane", "-t", action.pane], { stdout: "ignore", stderr: "ignore" })
      else if (action.kind === "worktree" && action.row.session.path) Bun.spawnSync([`${repoRoot}/bin/worktree-delete`, "--yes", expandHome(action.row.session.path)], { stdout: "inherit", stderr: "inherit" })
      else if (action.kind === "session") killSessionSync(action.row.session.name)
      return
    }
    if (key.meta && key.name === "k") return resetList("repo")
    if (key.meta && key.name === "r" && mode() === "jump") {
      const selected = selectedParent()
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
        setIndex(Math.max(0, treeRows(sessions(), "").findIndex((row) => row.depth === 0)))
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
        setQuery((value) => {
          const next = value.slice(0, -1)
          if (!next) setIndex(Math.max(0, treeRows(sessions(), "").findIndex((row) => row.depth === 0)))
          else setIndex(0)
          return next
        })
      }
      return
    }
    if (mode() === "jump" && key.name === "right") {
      const selected = selectedTreeRow()
      if (selected?.depth === 0) setExpanded(selected.session.name, true)
      return
    }
    if (mode() === "jump" && key.name === "left") {
      const selected = selectedTreeRow()
      if (selected) setExpanded(selected.session.name, false)
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
        const nextExpanded = new Set(expandedSessions())
        if (nextExpanded.delete(oldName)) nextExpanded.add(actual)
        setExpandedSessions(nextExpanded)
        setRenameSession(undefined)
        resetList("jump")
        setIndex(Math.max(0, treeRows(sessions(), "", nextExpanded).findIndex((treeRow) => treeRow.depth === 0 && treeRow.session === row)))
        return
      }
      if (mode() === "jump") {
        const selected = selectedTreeRow()
        return closeWith(selected?.target, selected?.detail?.completionKey)
      }
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
      const selected = selectedTreeRow()
      if (!selected) return
      requestDelete(selected)
      return
    }
    if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) appendInput(key.sequence)
  }, {})

  onMount(() => {
    const cacheInterval = setInterval(() => {
      const refreshed = readCache()
      if (!refreshed) return
      const selectedKey = selectedTreeRow()?.key
      const selectedSessionName = selectedTreeRow()?.session.name
      const byName = new Map(refreshed.map((session) => [session.name, session]))
      const currentNames = new Set(sessions().map((session) => session.name))
      const nextSessions = [
        ...sessions().map((session) => byName.get(session.name) ?? session),
        ...refreshed.filter((session) => !currentNames.has(session.name)),
      ]
      setSessions(nextSessions)
      if (mode() === "jump") {
        const nextRows = treeRows(nextSessions, query())
        let nextIndex = selectedKey ? nextRows.findIndex((row) => row.key === selectedKey) : -1
        if (nextIndex < 0 && selectedSessionName) nextIndex = nextRows.findIndex((row) => row.depth === 0 && row.session.name === selectedSessionName)
        setIndex(nextIndex >= 0 ? nextIndex : clamp(index(), 0, Math.max(0, nextRows.length - 1)))
      }
    }, 500)
    onCleanup(() => {
      clearInterval(cacheInterval)
    })
  })

  const title = () => mode() === "jump" ? "Jump" : mode() === "repo" ? "Open or create branch · choose repository" : mode() === "branch" ? `Open or create branch · ${repository()?.name ?? ""}` : mode() === "rename" ? "Rename tmux session" : `New branch · ${repository()?.name ?? ""}`

  return (
    <box flexDirection="column" width="100%" height="100%">
      <box height={1} flexDirection="row">
        <text fg={theme.accentStrong}>{title()}</text>
        <text flexGrow={1}> </text>
        <text fg={fetchStatus() === "failed" ? theme.warning : theme.muted}>{mode() === "jump" ? `Alt-k branches${selectedParent()?.target.type === "tmux_session" ? " · Alt-r rename" : ""} · Esc close` : `Alt-k open/create${mode() === "branch" ? ` · ^r ${fetchStatus() === "fetching" ? "fetching" : fetchStatus() === "failed" ? "fetch failed" : fetchStatus() === "done" ? "synced" : "refresh"}` : ""} · Esc back`}</text>
      </box>
      <box border borderStyle="single" borderColor={theme.border} flexGrow={1} flexDirection="column" justifyContent="flex-end">
        {mode() === "jump" ? <For each={visibleTreeRows()}>{(row) => <TreeRowView row={row} selected={row === selectedTreeRow()} query={query()} expanded={expandedSessions().has(row.session.name)} />}</For> : null}
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
      {deleteAction() ? (
        <box border borderStyle="single" borderColor={theme.warning} height={8} flexDirection="column" padding={1}>
          <text fg={theme.warning}>{deletePrompt()}</text>
          <text fg={theme.header}>Press y to confirm or n to cancel.</text>
        </box>
      ) : mode() === "jump" ? <JumpFooter row={selectedTreeRow()} /> : (
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
          <text fg={theme.muted}>{activeLength()} targets</text>
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

if (import.meta.main) {
  Effect.runPromiseExit(program).then((exit) => {
    if (Exit.isFailure(exit)) {
      console.error(exit.cause.toString())
      process.exitCode = 1
    }
  })
}
