import { afterEach, describe, expect, test } from "bun:test"
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { createServer } from "node:net"
import { join } from "node:path"
import { tmpdir } from "node:os"
import { generatedAgentId, parsePaneMetadata, requestUnixSocket } from "./agent-api"

const roots: string[] = []
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true })
})

describe("Waystation agent metadata", () => {
  test("parses tmux discovery metadata without using pane contents", () => {
    const rows = parsePaneMetadata("pi\tws-123\t/tmp/pi.sock\t$1\trepo@branch\t@2\tpi\t%3\t/repo\t/repo")
    expect(rows).toEqual([{
      harness: "pi",
      id: "ws-123",
      socketPath: "/tmp/pi.sock",
      sessionId: "$1",
      session: "repo@branch",
      window: "@2",
      name: "pi",
      pane: "%3",
      cwd: "/repo",
      worktreePath: "/repo",
    }])
  })

  test("generates opaque namespaced ids", () => {
    expect(generatedAgentId()).toMatch(/^ws-[0-9a-f-]{36}$/)
    expect(generatedAgentId()).not.toBe(generatedAgentId())
  })
})

describe("report generations", () => {
  test("advances and settles a non-Pi lifecycle from native hook reports", async () => {
    const root = mkdtempSync(join(tmpdir(), "waystation-report-test-"))
    roots.push(root)
    const bin = join(root, "bin")
    const runtime = join(root, "runtime")
    mkdirSync(bin)
    mkdirSync(runtime)
    const tmux = join(bin, "tmux")
    writeFileSync(tmux, "#!/bin/sh\ncase \"$1\" in show-option) exit 1 ;; set-option) exit 0 ;; display-message) pwd -P ;; esac\n")
    chmodSync(tmux, 0o755)
    const reporter = join(import.meta.dir, "../../bin/alt-k-agent-state-report")
    const env = {
      ...process.env,
      PATH: `${bin}:${process.env.PATH || ""}`,
      XDG_RUNTIME_DIR: runtime,
      XDG_STATE_HOME: join(root, "state"),
      TMUX_PANE: "%99",
      WAYSTATION_AGENT_ID: "ws-test",
    }
    const emit = async (state: string, hookEvent: string) => {
      const process = Bun.spawn([reporter, "claude", state], { env, stdin: "pipe", stdout: "pipe", stderr: "pipe" })
      process.stdin.write(JSON.stringify({ hook_event_name: hookEvent }))
      process.stdin.end()
      expect(await process.exited).toBe(0)
    }
    await emit("running", "UserPromptSubmit")
    await emit("done", "Stop")
    const report = JSON.parse(readFileSync(join(runtime, `alt-k-tui-${process.getuid?.() || 0}`, "agent-state", "%99.json"), "utf8"))
    expect(report).toMatchObject({ agent: "claude", agentId: "ws-test", generation: 1, settledGeneration: 1, state: "done" })
  })

  test("exposes report-only harnesses and rejects unsupported sends", async () => {
    const root = mkdtempSync(join(tmpdir(), "waystation-cli-test-"))
    roots.push(root)
    const bin = join(root, "bin")
    const runtime = join(root, "runtime")
    const reportDirectory = join(runtime, `alt-k-tui-${process.getuid?.() || 0}`, "agent-state")
    mkdirSync(bin)
    mkdirSync(reportDirectory, { recursive: true })
    const nested = join(root, "nested")
    mkdirSync(nested)
    expect(Bun.spawnSync(["git", "init", "-q", root]).exitCode).toBe(0)
    const tmux = join(bin, "tmux")
    writeFileSync(tmux, `#!/bin/sh\ncase "$1" in\n  list-panes) printf '%b\\n' 'claude\\tws-claude\\t\\t$1\\tfixture\\t@2\\tclaude\\t%7\\t${root}\\t${root}' 'pi\\tws-pi\\t\\t$1\\tfixture\\t@3\\tpi\\t%8\\t${nested}\\t' ;;\n  *) exit 1 ;;\nesac\n`)
    chmodSync(tmux, 0o755)
    writeFileSync(join(reportDirectory, "%7.json"), JSON.stringify({ agent: "claude", agentId: "ws-claude", pane: "%7", state: "done", generation: 2, settledGeneration: 2, updatedAt: Date.now(), hookEvent: "Stop" }))
    writeFileSync(join(reportDirectory, "%8.json"), JSON.stringify({
      agent: "pi", agentId: "ws-pi", pane: "%8", state: "idle", generation: 0, settledGeneration: 0, updatedAt: Date.now(), hookEvent: "session_start", results: [],
    }))
    const repository = join(import.meta.dir, "../..")
    const waystation = join(repository, "bin/waystation")
    const env = { ...process.env, PATH: `${bin}:${process.env.PATH || ""}`, XDG_RUNTIME_DIR: runtime, DOTFILES_DIR: repository }
    const list = Bun.spawnSync([waystation, "agent", "list", "--cwd", root], { env, stdout: "pipe", stderr: "pipe" })
    expect(list.exitCode).toBe(0)
    const listed = JSON.parse(list.stdout.toString())
    expect(listed).toHaveLength(2)
    expect(listed[0]).toMatchObject({ id: "ws-claude", harness: "claude", state: "done", settledGeneration: 2, capabilities: { wait: "reports", send: false, result: false } })
    expect(listed[1]).toMatchObject({ id: "ws-pi", generation: 0, settledGeneration: 0 })
    writeFileSync(join(reportDirectory, "%8.json"), JSON.stringify({
      agent: "pi", agentId: "ws-pi", pane: "%8", state: "done", generation: 2, settledGeneration: 2, updatedAt: Date.now(), hookEvent: "agent_settled",
      results: [
        { generation: 1, timestamp: 1, status: 0, stopReason: "stop", errorMessage: "", reply: "first" },
        { generation: 2, timestamp: 2, status: 0, stopReason: "stop", errorMessage: "", reply: "second" },
      ],
    }))
    const result = Bun.spawnSync([waystation, "agent", "result", "--generation", "1", "ws-pi"], { env, stdout: "pipe", stderr: "pipe" })
    expect(result.exitCode).toBe(0)
    expect(JSON.parse(result.stdout.toString())).toMatchObject({ agentId: "ws-pi", generation: 1, reply: "first" })
    const waiter = Bun.spawn([waystation, "agent", "wait", "--after", "2", "--timeout", "2", "ws-claude"], { env, stdout: "pipe", stderr: "pipe" })
    await Bun.sleep(250)
    writeFileSync(join(reportDirectory, "%7.json"), JSON.stringify({ agent: "claude", agentId: "ws-claude", pane: "%7", state: "done", generation: 3, settledGeneration: 3, updatedAt: Date.now(), hookEvent: "Stop" }))
    const waited = await new Response(waiter.stdout).text()
    expect(await waiter.exited).toBe(0)
    expect(JSON.parse(waited)).toMatchObject({ id: "ws-claude", generation: 3, settledGeneration: 3 })
    const timeout = Bun.spawnSync([waystation, "agent", "wait", "--after", "3", "--timeout", "0", "ws-claude"], { env, stdout: "pipe", stderr: "pipe" })
    expect(timeout.exitCode).toBe(124)
    expect(JSON.parse(timeout.stderr.toString())).toMatchObject({ apiVersion: 1, error: { code: "TIMEOUT" } })
    const send = Bun.spawn([waystation, "agent", "send", "ws-claude"], { env, stdin: "pipe", stdout: "pipe", stderr: "pipe" })
    send.stdin.write("hello")
    send.stdin.end()
    const error = await new Response(send.stderr).text()
    expect(await send.exited).toBe(4)
    expect(JSON.parse(error)).toMatchObject({ apiVersion: 1, error: { code: "UNSUPPORTED", message: expect.stringMatching(/does not support send.*no verified native transport/) } })
  })
})

describe("Pi native transport", () => {
  test("serves native messages and generation results from the global extension", async () => {
    const root = mkdtempSync(join(tmpdir(), "waystation-extension-test-"))
    roots.push(root)
    const bin = join(root, "bin")
    const runtime = join(root, "runtime")
    mkdirSync(bin)
    mkdirSync(runtime)
    const tmux = join(bin, "tmux")
    writeFileSync(tmux, "#!/bin/sh\ncase \"$1\" in show-option) exit 1 ;; set-option) exit 0 ;; esac\n")
    chmodSync(tmux, 0o755)
    const extension = join(import.meta.dir, "../../pi/extensions/tmux-worker-lifecycle.ts")
    const script = join(root, "extension-test.ts")
    writeFileSync(script, `
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs"
import { createConnection } from "node:net"
import extension from ${JSON.stringify(extension)}
const handlers = new Map<string, Function>()
const sent: unknown[] = []
const pi = {
  events: { on: () => () => {} },
  on: (name: string, handler: Function) => { handlers.set(name, handler) },
  sendUserMessage: (text: string, options?: unknown) => sent.push({ text, options }),
}
extension(pi as never)
let idle = true
const context = { isIdle: () => idle }
await handlers.get("session_start")?.({}, context)
const socketDirectory = \`${runtime}/alt-k-tui-\${process.getuid?.() || 0}/agent-sockets\`
const socketPath = \`\${socketDirectory}/\${readdirSync(socketDirectory).find((entry) => entry.endsWith(".sock"))}\`
const sendNative = (text: string, delivery?: "steer" | "followUp") => new Promise<Record<string, unknown>>((resolve, reject) => {
  const socket = createConnection(socketPath)
  let response = ""
  socket.setEncoding("utf8")
  socket.on("connect", () => socket.write(JSON.stringify({ version: 1, action: "send", agentId: "ws-pi-test", text, delivery }) + "\\n"))
  socket.on("data", (chunk) => { response += chunk; if (response.includes("\\n")) resolve(JSON.parse(response.trim())) })
  socket.on("error", reject)
})
const firstReceipt = await sendNative("native hello")
await handlers.get("agent_start")?.({}, context)
await handlers.get("agent_end")?.({ messages: [{ role: "assistant", stopReason: "stop", content: [{ type: "text", text: "native result" }] }] }, context)
await handlers.get("agent_settled")?.({}, context)
idle = false
const secondReceipt = await sendNative("second turn")
const concurrentReceipt = await sendNative("too soon", "steer")
idle = true
await handlers.get("agent_start")?.({}, context)
await handlers.get("agent_end")?.({ messages: [{ role: "assistant", stopReason: "stop", content: [{ type: "text", text: "second result" }] }] }, context)
await handlers.get("agent_settled")?.({}, context)
idle = false
const steerReceipt = await sendNative("steer now", "steer")
idle = true
await handlers.get("agent_start")?.({}, context)
await handlers.get("agent_end")?.({ messages: [{ role: "assistant", stopReason: "stop", content: [{ type: "text", text: "third result" }] }] }, context)
await handlers.get("agent_settled")?.({}, context)
const reportPath = \`${runtime}/alt-k-tui-\${process.getuid?.() || 0}/agent-state/%44.json\`
const report = JSON.parse(readFileSync(reportPath, "utf8"))
const socketMode = (statSync(socketPath).mode & 0o777).toString(8)
await handlers.get("session_shutdown")?.({ reason: "quit" }, context)
await Bun.sleep(10)
console.log(JSON.stringify({ firstReceipt, secondReceipt, concurrentReceipt, steerReceipt, sent, report, socketMode, socketRemoved: !existsSync(socketPath) }))
`)
    const child = Bun.spawnSync([process.execPath, script], {
      env: { ...process.env, PATH: `${bin}:${process.env.PATH || ""}`, XDG_RUNTIME_DIR: runtime, XDG_STATE_HOME: join(root, "state"), TMUX_PANE: "%44", WAYSTATION_AGENT_ID: "ws-pi-test" },
      stdout: "pipe",
      stderr: "pipe",
    })
    expect(child.exitCode).toBe(0)
    const output = JSON.parse(child.stdout.toString())
    expect(output.firstReceipt).toMatchObject({ ok: true, agentId: "ws-pi-test", afterGeneration: 0, delivery: "immediate" })
    expect(output.secondReceipt).toMatchObject({ ok: true, agentId: "ws-pi-test", afterGeneration: 1, observedGeneration: 1, delivery: "followUp" })
    expect(output.concurrentReceipt).toMatchObject({ ok: false, error: expect.stringContaining("still awaiting settlement") })
    expect(output.steerReceipt).toMatchObject({ ok: true, agentId: "ws-pi-test", afterGeneration: 2, observedGeneration: 2, delivery: "steer" })
    expect(output.sent).toEqual([
      { text: "native hello" },
      { text: "second turn", options: { deliverAs: "followUp" } },
      { text: "steer now", options: { deliverAs: "steer" } },
    ])
    expect(output.report).toMatchObject({ agent: "pi", agentId: "ws-pi-test", generation: 3, settledGeneration: 3, state: "done", result: { generation: 3, status: 0, reply: "third result" } })
    expect(output.report.results).toEqual([
      expect.objectContaining({ generation: 1, reply: "native result" }),
      expect.objectContaining({ generation: 2, reply: "second result" }),
      expect.objectContaining({ generation: 3, reply: "third result" }),
    ])
    expect(output.socketMode).toBe("600")
    expect(output.socketRemoved).toBe(true)
  })

  test("uses one newline-delimited request and response", async () => {
    const root = mkdtempSync(join(tmpdir(), "waystation-agent-test-"))
    roots.push(root)
    const path = join(root, "pi.sock")
    const server = createServer((socket) => {
      socket.setEncoding("utf8")
      socket.once("data", (data) => {
        const request = JSON.parse(String(data).trim())
        socket.end(`${JSON.stringify({ ok: true, echoed: request.text })}\n`)
      })
    })
    await new Promise<void>((resolve) => server.listen(path, resolve))
    chmodSync(path, 0o600)
    await expect(requestUnixSocket(path, { version: 1, action: "send", text: "hello" })).resolves.toEqual({ ok: true, echoed: "hello" })
    await new Promise<void>((resolve) => server.close(() => resolve()))
  })

})
