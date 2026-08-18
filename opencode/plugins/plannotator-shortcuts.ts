function parseLastJson(stdout: string) {
  const lines = stdout.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
  const line = lines.findLast((candidate) => candidate.startsWith("{"))
  if (!line) throw new Error("Plannotator did not return JSON.")
  return JSON.parse(line)
}

function commandArgs(input: string, name: string) {
  return input.trim().replace(new RegExp(`^/?${name}\\s*`), "")
}

async function runPlannotator(args: string[], input: unknown, cwd: string) {
  const process = Bun.spawn(["plannotator", ...args], {
    cwd,
    stdin: new Blob([JSON.stringify(input)]),
    stdout: "pipe",
    stderr: "pipe",
  })
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process.stdout).text(),
    new Response(process.stderr).text(),
    process.exited,
  ])
  if (exitCode !== 0) throw new Error(stderr.trim() || `Plannotator exited with code ${exitCode}`)
  return parseLastJson(stdout)
}

function currentSessionID(api: any) {
  return api.route.current.name === "session" ? api.route.current.params.sessionID : undefined
}

async function sendFollowUp(api: any, sessionID: string, text: string) {
  await api.client.session.prompt({
    sessionID,
    directory: api.state.path.directory,
    parts: [{ type: "text", text }],
  })
}

export default {
  id: "dotfiles.plannotator-shortcuts",
  setup: async () => {},
  tui: async (api: any) => {
    let running = false

    const execute = async (action: () => Promise<void>) => {
      if (running) return
      running = true
      api.ui.dialog.clear()
      try {
        await action()
      } catch (error) {
        api.ui.toast({
          variant: "error",
          message: error instanceof Error ? error.message : String(error),
        })
      } finally {
        running = false
      }
    }

    api.keymap.registerLayer({
      commands: [
        {
          namespace: "palette",
          name: "plannotator.review",
          title: "Plannotator code review",
          category: "Plugin",
          slashName: "plr",
          enabled: () => Boolean(currentSessionID(api)) && !running,
          run: (context: { input: string }) => execute(async () => {
            const sessionID = currentSessionID(api)
            if (!sessionID) throw new Error("No active session.")
            const outcome = await runPlannotator(
              ["opencode-review"],
              { arguments: commandArgs(context.input, "plr") },
              api.state.path.directory,
            )
            if (outcome.feedback) {
              await sendFollowUp(api, sessionID, outcome.feedback)
            } else if (outcome.approved || outcome.decision === "approved") {
              await sendFollowUp(api, sessionID, "Plannotator code review approved the changes.")
            } else {
              api.ui.toast({ variant: "info", message: "Code review session closed." })
            }
          }),
        },
        {
          namespace: "palette",
          name: "plannotator.last",
          title: "Annotate the last assistant message",
          category: "Plugin",
          slashName: "pll",
          enabled: () => Boolean(currentSessionID(api)) && !running,
          run: (context: { input: string }) => execute(async () => {
            const sessionID = currentSessionID(api)
            if (!sessionID) throw new Error("No active session.")
            const recentMessages = [...api.state.session.messages(sessionID)]
              .filter((message: any) => message.role === "assistant")
              .reverse()
              .slice(0, 25)
              .map((message: any) => ({
                messageId: message.id,
                text: api.state.part(message.id)
                  .filter((part: any) => part.type === "text" && part.text?.trim())
                  .map((part: any) => part.text)
                  .join("\n"),
                timestamp: message.time?.created
                  ? new Date(message.time.created).toISOString()
                  : undefined,
              }))
              .filter((message: any) => message.text)
            if (recentMessages.length === 0) throw new Error("No assistant message found in session.")

            const outcome = await runPlannotator(
              ["opencode-annotate-last"],
              {
                gate: commandArgs(context.input, "pll").split(/\s+/).includes("--gate"),
                recentMessages,
              },
              api.state.path.directory,
            )
            if (outcome.feedback) {
              await sendFollowUp(api, sessionID, outcome.feedback)
            } else if (outcome.approved || outcome.decision === "approved") {
              api.ui.toast({ variant: "success", message: "Message approved." })
            } else {
              api.ui.toast({ variant: "info", message: "Annotation session closed." })
            }
          }),
        },
      ],
    })
  },
}
