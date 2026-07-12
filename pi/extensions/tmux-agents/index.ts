import * as fs from "node:fs"
import * as os from "node:os"
import * as path from "node:path"
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"
import { Type } from "typebox"

const Common = {
  prompt: Type.String({ description: "Objective, context, constraints, and definition of done." }),
  agent: Type.Optional(Type.String({ description: "Agent preset; repository definitions override personal defaults." })),
  windowName: Type.Optional(Type.String({ description: "Optional agent window name; collisions receive a numeric suffix." })),
  wait: Type.Optional(Type.Boolean({ description: "Wait for a settled, valid initial result. Timeout leaves the worker running." })),
}
const AgentParams = Type.Object({ ...Common, cwd: Type.Optional(Type.String()) })
const WorkerParams = Type.Object({ ...Common, branch: Type.Optional(Type.String()), base: Type.Optional(Type.String()) })

type State = "running" | "done" | "attention" | "unknown"
function report(state: State, event: string) {
  try {
    const pane = process.env.TMUX_PANE; if (!pane) return
    const dir = path.join(process.env.XDG_RUNTIME_DIR || "/tmp", `alt-k-tui-${process.getuid?.() || 0}`, "agent-state")
    fs.mkdirSync(dir, { recursive: true }); const file = path.join(dir, `${pane.replace(/[^\w.%-]/g, "_")}.json`)
    fs.writeFileSync(file, JSON.stringify({ agent: "pi", state, pane, updatedAt: Date.now(), hookEvent: event }))
  } catch {}
}
const slug = (text: string) => text.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48) || `task-${Date.now()}`

export default function (pi: ExtensionAPI) {
  pi.on("session_start", () => report("done", "session_start"))
  pi.on("agent_start", () => report("running", "agent_start"))
  pi.on("agent_settled", () => report("done", "agent_settled"))
  pi.on("session_shutdown", () => report("unknown", "session_shutdown"))

  const run = async (args: string[], signal?: AbortSignal) => {
    const executable = path.join(process.env.DOTFILES_DIR || path.join(os.homedir(), "dotfiles"), "bin", "dotfiles-workflow")
    const result = await pi.exec(executable, args, { signal })
    return { content: [{ type: "text" as const, text: result.stdout.trim() || result.stderr.trim() }], details: result, isError: result.code !== 0 }
  }
  pi.registerTool({ name: "tmux_subagent", label: "Tmux Subagent", description: "Launch a pi agent in a dedicated window in the current worktree session.", parameters: AgentParams,
    async execute(_id, p, signal) { return run(["agent", "--harness", "pi", "--cwd", p.cwd || process.cwd(), ...(p.agent ? ["--agent", p.agent] : []), ...(p.windowName ? ["--window", p.windowName] : []), ...(p.wait ? ["--wait"] : []), p.prompt], signal) } })
  const register = (name: string) => pi.registerTool({ name, label: "Tworker", description: "Create a local Worktrunk worktree and launch a pi agent window in its lazy tmux session.", parameters: WorkerParams,
    async execute(_id, p, signal) { return run(["worker", "--harness", "pi", ...(p.agent ? ["--agent", p.agent] : []), ...(p.windowName ? ["--window", p.windowName] : []), ...(p.base ? ["--base", p.base] : []), ...(p.wait ? ["--wait"] : []), p.branch || slug(p.prompt), p.prompt], signal) } })
  register("tworker"); register("tmux_tworker")
}
