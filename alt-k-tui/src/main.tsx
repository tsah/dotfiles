import { render, useKeyboard, useRenderer, useTerminalDimensions } from "@opentui/solid"
import { createMemo, createSignal, For, onCleanup, onMount } from "solid-js"
import { Effect, Exit } from "effect"

type Target =
  | { type: "tmux_session"; session: string }
  | { type: "tmux_window"; session: string; windowId: string }
  | { type: "opencode"; session: string; pane: string }

type AgentState = "running" | "done" | "attention" | "unknown"

interface TmuxSession { name: string; recency: number; path: string }
interface TmuxWindow { session: string; id: string; name: string; pane: string; pid: string; command: string; title: string }
interface OpencodeStatus { directory: string; status: string; detail: string; title: string; age: string; session: string; pane: string }
interface DetailRow { kind: string; status: string; detail: string; title: string; age: string; state: AgentState; target: Target }
interface SessionRow { name: string; path: string; branch: string; flags: string; markers: string[]; age: string; recency: number; target: Target; details: DetailRow[]; searchText: string }
interface FuzzyResult { score: number; positions: number[] }

const repoRoot = new URL("../..", import.meta.url).pathname.replace(/\/$/, "")
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

const collectTmuxWindows = runCommand(["tmux", "list-windows", "-a", "-F", "#{session_name}\t#{window_id}\t#{window_name}\t#{pane_id}\t#{pane_pid}\t#{pane_current_command}\t#{pane_title}"]).pipe(
  Effect.map((output) => parseTsv(output).map((parts): TmuxWindow => ({
    session: parts[0] ?? "",
    id: parts[1] ?? "",
    name: parts[2] ?? "",
    pane: parts[3] ?? "",
    pid: parts[4] ?? "",
    command: (parts[5] ?? "").toLowerCase(),
    title: parts[6] ?? "",
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

const gitMeta = (path: string) => Effect.gen(function* () {
  if (!path) return { branch: "", flags: "" }
  const branch = yield* runCommand(["git", "-C", path, "branch", "--show-current"], { allowFailure: true }).pipe(Effect.map((out) => out.trim()))
  if (!branch) return { branch: "", flags: "" }
  const dirty = yield* runCommand(["git", "-C", path, "status", "--porcelain"], { allowFailure: true }).pipe(Effect.map((out) => out.trim().length > 0))
  return { branch, flags: dirty ? "dirty" : "clean" }
})

const isPiWindow = (window: TmuxWindow) => window.command === "pi" || ["pi", "pi-agent"].includes(window.name.toLowerCase()) || window.name.toLowerCase().startsWith("p:") || window.title.startsWith("π")
const isClaudeWindow = (window: TmuxWindow) => window.command === "claude" || window.name.toLowerCase() === "claude" || window.title.toLowerCase().includes("claude code")
const isCodexWindow = (window: TmuxWindow) => window.command === "codex" || window.name.toLowerCase() === "codex" || window.title.toLowerCase().includes("codex")
const processGroupContains = (pid: string, needle: string) => pid
  ? runCommand(["ps", "-o", "args=", "--forest", "-g", pid], { allowFailure: true }).pipe(Effect.map((output) => output.toLowerCase().includes(needle.toLowerCase())))
  : Effect.succeed(false)

const ageToSeconds = (age: string) => {
  const match = age.trim().match(/^(\d+)([smhd])$/)
  if (!match) return 0
  const value = Number(match[1] ?? 0)
  const unit = match[2]
  if (unit === "s") return value
  if (unit === "m") return value * 60
  if (unit === "h") return value * 60 * 60
  return value * 24 * 60 * 60
}

const agentStateFromStatus = (status: string, detail = "", age = ""): AgentState => {
  const normalized = status.trim().toLowerCase()
  const normalizedDetail = detail.trim().toLowerCase()
  if (!normalized) return "unknown"
  if (["done", "idle", "complete", "completed", "success", "succeeded"].includes(normalized)) return "done"
  if (normalized === "waiting question") return "attention"
  if (normalized.includes("tool running") && ["question", "permission", "approval"].some((word) => normalizedDetail.includes(word))) return "attention"
  if (["error", "failed", "failure", "blocked", "input", "attention", "confirm", "review", "question"].some((word) => normalized.includes(word))) return "attention"
  if (["running", "generating", "streaming", "working"].some((word) => normalized.includes(word))) return ageToSeconds(age) > 30 * 60 ? "attention" : "running"
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

const buildSessionRows = (sessions: TmuxSession[], windows: TmuxWindow[], opencodes: OpencodeStatus[]) => Effect.gen(function* () {
  const windowsBySession = Map.groupBy(windows, (window) => window.session)
  const opencodeBySession = new Map(opencodes.map((row) => [row.session, row]))
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
    const opencode = opencodeBySession.get(session.name)
    const meta = yield* gitMeta(session.path)
    const details: DetailRow[] = []

    if (opencode) {
      details.push({ kind: "opencode", status: opencode.status, detail: opencode.detail, title: opencode.title || opencode.directory, age: opencode.age, state: agentStateFromStatus(opencode.status, opencode.detail, opencode.age), target: { type: "opencode", session: opencode.session, pane: opencode.pane } })
    }

    const agentWindows = sessionWindows.filter((window) => isPiWindow(window) || isClaudeWindow(window) || codexPanes.has(window.pane))
    for (const window of agentWindows) {
      const kind = isPiWindow(window) ? "pi" : isClaudeWindow(window) ? "claude" : "codex"
      details.push({ kind, status: "", detail: "", title: window.title || window.name, age: "", state: "unknown", target: { type: "tmux_window", session: window.session, windowId: window.id } })
    }

    if (details.length === 0) {
      details.push({ kind: "session", status: meta.flags, detail: "", title: session.path, age: ageFromUnixSeconds(session.recency), state: "unknown", target: { type: "tmux_session", session: session.name } })
    }

    const markers = [opencode ? "oc" : "", sessionWindows.some(isPiWindow) ? "pi" : "", sessionWindows.some(isClaudeWindow) ? "C" : "", sessionWindows.some((window) => codexPanes.has(window.pane)) ? "codex" : ""].filter(Boolean)
    const row: SessionRow = { name: session.name, path: session.path, branch: meta.branch, flags: meta.flags, markers, age: ageFromUnixSeconds(session.recency), recency: session.recency, target: { type: "tmux_session", session: session.name }, details, searchText: "" }
    row.searchText = [row.name, row.path, row.branch, row.flags, row.markers.join(" "), ...row.details.flatMap((detail) => [detail.kind, detail.status, detail.detail, detail.title, detail.age])].join(" ").toLowerCase()
    rows.push(row)
  }

  return rows.sort((a, b) => sessionSortRank(a) - sessionSortRank(b) || b.recency - a.recency || a.name.localeCompare(b.name))
})

const collectSessions = Effect.all([collectTmuxSessions, collectTmuxWindows, collectOpencode], { concurrency: "unbounded" }).pipe(
  Effect.flatMap(([sessions, windows, opencodes]) => buildSessionRows(sessions, windows, opencodes)),
)

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
const agentIcon = (kind: string) => kind === "opencode" ? "🤖" : kind === "pi" ? "π" : kind === "claude" ? "🥐" : kind === "codex" ? "📜" : kind
const agentSummary = (sessions: SessionRow[]) => ["oc", "pi", "C", "codex"].map((marker) => `[${marker}:${sessions.filter((session) => session.markers.includes(marker)).length}]`).join(" ")
const sessionGitMeta = (session: SessionRow) => [session.branch, session.flags === "dirty" ? "dirty" : ""].filter(Boolean).join(", ")
const selectedColor = (selected: boolean, state: AgentState) => selected ? theme.selectedFg : state === "attention" ? theme.warning : state === "running" ? theme.ok : theme.header

const openTarget = (target: Target) => {
  const command = (() => {
    switch (target.type) {
      case "opencode": return ["opencode-attach-target", target.session, target.pane]
      case "tmux_session": return ["tmux", process.env.TMUX ? "switch-client" : "attach-session", "-t", target.session]
      case "tmux_window": return process.env.TMUX
        ? ["sh", "-c", "tmux switch-client -t \"$1\" && tmux select-window -t \"$2\"", "sh", target.session, target.windowId]
        : ["tmux", "attach-session", "-t", target.session, ";", "select-window", "-t", target.windowId]
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

function App(props: { sessions: SessionRow[]; onOpen: (target: Target | undefined) => void }) {
  const renderer = useRenderer()
  const dimensions = useTerminalDimensions()
  const [query, setQuery] = createSignal("")
  const [index, setIndex] = createSignal(0)
  const [frame, setFrame] = createSignal(0)
  const filtered = createMemo(() => filterSessions(props.sessions, query()))
  const visibleCount = createMemo(() => Math.max(1, dimensions().height - 3))
  const start = createMemo(() => Math.max(0, Math.min(filtered().length - visibleCount(), index() - visibleCount() + 1)))
  const visible = createMemo(() => filtered().slice(start(), start() + visibleCount()).reverse())

  const updateIndex = (next: number) => setIndex(clamp(next, 0, Math.max(0, filtered().length - 1)))
  const closeWith = (target?: Target) => {
    props.onOpen(target)
    openTargetSync(target)
    renderer.destroy()
  }

  useKeyboard((key) => {
    if (key.meta && key.name === "k") return closeWith()
    if (key.name === "escape") {
      if (query()) {
        setQuery("")
        setIndex(0)
      } else closeWith()
      return
    }
    if (key.name === "backspace") {
      setQuery((value) => value.slice(0, -1))
      setIndex(0)
      return
    }
    if (key.name === "up") return updateIndex(index() + 1)
    if (key.name === "down") return updateIndex(index() - 1)
    if (key.name === "return") return closeWith(filtered()[index()]?.target)
    if (key.sequence && key.sequence.length === 1 && !key.ctrl && !key.meta) {
      setQuery((value) => value + key.sequence)
      setIndex(0)
    }
  }, {})

  onMount(() => {
    setIndex(0)
    const interval = setInterval(() => setFrame((value) => value + 1), 120)
    onCleanup(() => clearInterval(interval))
  })

  return (
    <box flexDirection="column" width="100%" height="100%">
      <box border borderStyle="single" borderColor={theme.border} flexGrow={1} flexDirection="column" justifyContent="flex-end">
        <For each={visible()}>{(session) => <SessionRowView session={session} selected={session === filtered()[index()]} query={query()} frame={frame()} />}</For>
      </box>
      <box flexDirection="row" height={1}>
        <text fg={theme.accent}>{"> "}{query()}_</text>
        <text flexGrow={1}> </text>
        <text fg={theme.muted}>{filtered().length}/{props.sessions.length} {agentSummary(props.sessions)}</text>
      </box>
    </box>
  )
}

const program = process.argv.includes("--dump-state") ? dumpState : Effect.gen(function* () {
  const sessions = yield* collectSessions
  let target: Target | undefined
  yield* Effect.tryPromise({
    try: () => render(() => <App sessions={sessions} onOpen={(next) => { target = next }} />, { exitOnCtrlC: true }),
    catch: (error) => error instanceof Error ? error : new Error(String(error)),
  })
})

Effect.runPromiseExit(program).then((exit) => {
  if (Exit.isFailure(exit)) {
    console.error(exit.cause.toString())
    process.exitCode = 1
  }
})
