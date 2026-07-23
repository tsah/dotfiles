import { createHash } from "node:crypto";
import { mkdirSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type State = "blocked" | "working" | "done" | "idle" | "unknown";

function report(state: State, event: string) {
	try {
		const pane = process.env.TMUX_PANE;
		if (!pane) return;
		const directory = join(process.env.XDG_RUNTIME_DIR || "/tmp", `alt-k-tui-${process.getuid?.() || 0}`, "agent-state");
		mkdirSync(directory, { recursive: true });
		const file = join(directory, `${pane.replace(/[^\w.%-]/g, "_")}.json`);
		const updatedAt = Date.now();
		writeFileSync(file, JSON.stringify({ agent: "pi", state, pane, updatedAt, hookEvent: event }));
		const path = realpathSync(process.cwd());
		const activityDirectory = join(process.env.XDG_STATE_HOME || join(process.env.HOME || "", ".local", "state"), "alt-k-tui", "activity");
		mkdirSync(activityDirectory, { recursive: true });
		const target = join(activityDirectory, `${createHash("sha256").update(path).digest("hex")}-agent.json`);
		const tmp = `${target}.${process.pid}.tmp`;
		writeFileSync(tmp, JSON.stringify({ path, source: "agent", updatedAt }));
		renameSync(tmp, target);
	} catch {}
}

function extractAssistantResult(messages: Array<any>) {
	for (let index = messages.length - 1; index >= 0; index--) {
		const message = messages[index];
		if (message?.role !== "assistant") {
			continue;
		}

		const stopReason = typeof message.stopReason === "string" ? message.stopReason : "";
		const errorMessage = typeof message.errorMessage === "string" ? message.errorMessage : "";
		const status = stopReason === "error" || stopReason === "aborted" || errorMessage ? 1 : 0;
		const reply = Array.isArray(message.content)
			? message.content
					.filter((part: any) => part?.type === "text" && typeof part.text === "string")
					.map((part: any) => part.text)
					.join("\n")
			: "";
		return { status, stopReason, errorMessage, reply };
	}

	return { status: 0, stopReason: "", errorMessage: "", reply: "" };
}

export default function (pi: ExtensionAPI) {
	const signalFile = process.env.PI_TMUX_WAIT_SIGNAL_FILE?.trim();

	pi.on("session_start", () => report("idle", "session_start"));
	pi.on("agent_start", () => report("working", "agent_start"));

	let signaled = false;

	const writeSignal = (payload: Record<string, unknown>) => {
		if (signaled) {
			return;
		}
		signaled = true;

		if (signalFile) {
			mkdirSync(dirname(signalFile), { recursive: true });
			writeFileSync(signalFile, `${JSON.stringify(payload)}\n`, "utf8");
		}
	};

	let latestResult = { status: 1, stopReason: "no_result", errorMessage: "Agent settled without a result.", reply: "" };
	pi.on("agent_end", async (event) => {
		latestResult = extractAssistantResult(event.messages as Array<any>);
	});
	pi.on("agent_settled", async () => {
		report(latestResult.status === 0 ? "done" : "blocked", "agent_settled");
		writeSignal({ timestamp: Date.now(), ...latestResult });
	});

	pi.on("session_shutdown", async () => {
		report("unknown", "session_shutdown");
		writeSignal({
			timestamp: Date.now(),
			status: 130,
			stopReason: "session_shutdown",
			errorMessage: "Session ended before the wait target signaled completion.",
			reply: "",
		});
	});
}
