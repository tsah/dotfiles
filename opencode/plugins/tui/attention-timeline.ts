import { appendFile, mkdir } from "node:fs/promises"
import path from "node:path"

const family = new Map([
  ["form.created", "question.asked"],
  ["permission.asked", "permission.asked"],
  ["session.execution.succeeded", "session.status"],
  ["session.execution.failed", "session.error"],
  ["session.step.failed", "session.error"],
])

export default {
  id: "attention-timeline",
  async setup(context: any) {
    const file = path.join(process.env.HOME ?? "", ".cache/opencode/attention-timeline.log")
    await mkdir(path.dirname(file), { recursive: true })
    const line = (value: string) =>
      appendFile(file, `${new Date().toISOString()} ${value}\n`).catch(() => {})

    await line("plugin.loaded")
    return context.data.listen((event: any) => {
      const type = event?.type ?? event?.name
      const name = family.get(type)
      if (!name) return

      const envelope = event?.properties ?? event?.data ?? event?.details ?? {}
      const data = envelope.data ?? envelope
      const sessionID = data.sessionID ?? data.form?.sessionID ?? "-"
      const session = context.data.session.get?.(sessionID)
      const parentID = session?.parentID ?? session?.parent_id ?? "-"
      const status =
        type === "session.execution.succeeded"
          ? "idle"
          : type === "session.execution.failed" || type === "session.step.failed"
            ? "error"
            : name
      void line(`${name} session=${sessionID} parent=${parentID} status=${status} source=${type}`)
    })
  },
}
