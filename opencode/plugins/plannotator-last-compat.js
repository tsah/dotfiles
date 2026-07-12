import { spawn } from "node:child_process"
import { appendFileSync, openSync, readFileSync, rmSync } from "node:fs"
import { join } from "node:path"
import { tmpdir } from "node:os"

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const stdoutFile = options.stdoutFile ? openSync(options.stdoutFile, "w") : "pipe"
    const child = spawn(command, args, {
      cwd: options.cwd,
      env: options.env ?? process.env,
      stdio: ["pipe", stdoutFile, "pipe"],
    })

    let stdout = ""
    let stderr = ""

    child.stdout?.setEncoding("utf8")
    child.stderr.setEncoding("utf8")
    child.stdout?.on("data", (chunk) => {
      stdout += chunk
    })
    child.stderr.on("data", (chunk) => {
      stderr += chunk
    })
    child.on("error", reject)
    child.on("close", (code) => resolve({ code, stdout, stderr }))

    if (options.input) {
      child.stdin.end(options.input)
    } else {
      child.stdin.end()
    }
  })
}

function log(message) {
  appendFileSync("/tmp/plannotator-last-compat.log", `${new Date().toISOString()} ${message}\n`)
}

function parseJsonLine(output) {
  const lines = output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)

  for (let i = lines.length - 1; i >= 0; i--) {
    if (!lines[i].startsWith("{")) continue
    try {
      return JSON.parse(lines[i])
    } catch {}
  }
}

function annotationFeedbackPrompt(feedback) {
  return `# Message Annotations

${feedback}

Please address the annotation feedback above.`
}

function startPlannotator(client, sessionId, directory, payload) {
  const child = spawn("plannotator", ["opencode-annotate-last"], {
    cwd: directory,
    env: {
      ...process.env,
      OPENCODE: "1",
      PLANNOTATOR_ORIGIN: "opencode",
      PLANNOTATOR_CWD: directory,
      PLANNOTATOR_REMOTE: "1",
      PLANNOTATOR_PORT: "19432",
    },
    stdio: ["pipe", "pipe", "pipe"],
  })

  let stdout = ""
  child.stdout.setEncoding("utf8")
  child.stderr.setEncoding("utf8")
  child.stdout.on("data", (chunk) => {
    stdout += chunk
    appendFileSync("/tmp/plannotator-last-compat.log", chunk)
  })
  child.stderr.on("data", (chunk) => {
    appendFileSync("/tmp/plannotator-last-compat.log", chunk)
  })
  child.on("error", (error) => {
    log(`plannotator spawn error: ${error instanceof Error ? error.message : String(error)}`)
  })
  child.on("close", async (code) => {
    log(`plannotator exited code=${code}`)
    const outcome = parseJsonLine(stdout)
    if (outcome?.decision !== "annotated" || !outcome.feedback?.trim()) return

    try {
      await client.session.prompt({
        path: { id: sessionId },
        body: {
          parts: [{ type: "text", text: annotationFeedbackPrompt(outcome.feedback) }],
        },
      })
      log(`injected feedback into session ${sessionId}`)
    } catch (error) {
      log(`feedback injection failed: ${error instanceof Error ? error.message : String(error)}`)
    }
  })

  child.stdin.end(JSON.stringify(payload))
}

function setOutput(output, text) {
  output.parts.length = 0
  output.parts.push({ type: "text", text })
}

async function exportSession(sessionId, directory) {
  const exportPath = join(tmpdir(), `opencode-session-${sessionId}-${Date.now()}.json`)
  try {
    const exported = await run("opencode", ["export", sessionId], { cwd: directory, stdoutFile: exportPath })
    if (exported.code !== 0) {
      return { error: `Failed to export session ${sessionId}: ${exported.stderr || exported.stdout}` }
    }

    const stdout = readFileSync(exportPath, "utf8")
    return { session: JSON.parse(stdout) }
  } catch (error) {
    return { error: `Failed to parse exported session ${sessionId}: ${error instanceof Error ? error.message : String(error)}` }
  } finally {
    rmSync(exportPath, { force: true })
  }
}

function recentAssistantMessages(session) {
  const messages = Array.isArray(session.messages) ? session.messages : []
  const result = []

  for (let i = messages.length - 1; i >= 0 && result.length < 25; i--) {
    const message = messages[i]
    if (message.info?.role !== "assistant") continue

    const text = (message.parts ?? [])
      .filter((part) => part.type === "text" && part.text?.trim())
      .map((part) => part.text)
      .join("\n")

    if (!text.trim()) continue

    result.push({
      messageId: message.info?.id ?? `opencode-${i}`,
      text,
      timestamp: message.info?.time?.created ? new Date(message.info.time.created).toISOString() : undefined,
    })
  }

  return result
}

export const PlannotatorLastCompatPlugin = async ({ client, directory }) => {
  return {
    "command.execute.before": async (input, output) => {
      if (input.command !== "plannotator-last") return

      const sessionId = input.sessionID
      if (!sessionId) {
        setOutput(output, "[Plannotator] Could not determine the current OpenCode session.")
        return
      }

      const exported = await exportSession(sessionId, directory)
      if (exported.error) {
        setOutput(output, `[Plannotator] ${exported.error}`)
        return
      }

      const recentMessages = recentAssistantMessages(exported.session)
      if (recentMessages.length === 0) {
        setOutput(output, "[Plannotator] No assistant text messages found in this OpenCode session.")
        return
      }

      await run("pkill", ["-f", "^plannotator opencode-annotate-last$"], { cwd: directory })

      startPlannotator(client, sessionId, directory, {
        gate: (input.arguments ?? "").includes("--gate"),
        recentMessages,
      })

      setOutput(output, "[Plannotator] Opening annotation UI for the last assistant message in this session.")
    },
  }
}
