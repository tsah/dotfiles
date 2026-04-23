import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

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
	if (!signalFile) {
		return;
	}

	let signaled = false;

	const writeSignal = (payload: Record<string, unknown>) => {
		if (signaled) {
			return;
		}
		signaled = true;

		mkdirSync(dirname(signalFile), { recursive: true });
		writeFileSync(signalFile, `${JSON.stringify(payload)}\n`, "utf8");
	};

	pi.on("agent_end", async (event) => {
		const result = extractAssistantResult(event.messages as Array<any>);
		writeSignal({
			timestamp: Date.now(),
			status: result.status,
			stopReason: result.stopReason,
			errorMessage: result.errorMessage,
			reply: result.reply,
		});
	});

	pi.on("session_shutdown", async () => {
		writeSignal({
			timestamp: Date.now(),
			status: 130,
			stopReason: "session_shutdown",
			errorMessage: "Session ended before the wait target signaled completion.",
			reply: "",
		});
	});
}
