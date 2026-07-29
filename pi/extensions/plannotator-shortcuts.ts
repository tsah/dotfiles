import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type PlannotatorResponse =
    | {
        status: "handled";
        result: {
            approved?: boolean;
            exit?: boolean;
            feedback?: string;
        };
    }
    | { status: "unavailable" | "error"; error?: string };

function request(
    pi: ExtensionAPI,
    action: "code-review" | "annotate-last",
    payload: Record<string, unknown>,
): Promise<PlannotatorResponse> {
    return new Promise((respond) => {
        pi.events.emit("plannotator:request", {
            requestId: crypto.randomUUID(),
            action,
            payload,
            respond,
        });
    });
}

function reportFailure(response: PlannotatorResponse, ctx: ExtensionContext): boolean {
    if (response.status === "handled") return false;
    ctx.ui.notify(response.error ?? "Plannotator is unavailable.", "error");
    return true;
}

export default function (pi: ExtensionAPI) {
    pi.registerCommand("plr", {
        description: "Open Plannotator code review",
        handler: async (args, ctx) => {
            const tokens = args.trim().split(/\s+/).filter(Boolean);
            const vcsType = tokens.includes("--git")
                ? "git"
                : tokens.includes("--gitbutler")
                    ? "gitbutler"
                    : undefined;
            const useLocal = tokens.includes("--local")
                ? true
                : tokens.includes("--no-local")
                    ? false
                    : undefined;
            const prUrl = tokens.find((token) => !token.startsWith("--"));
            const response = await request(pi, "code-review", {
                cwd: ctx.cwd,
                prUrl,
                vcsType,
                useLocal,
            });
            if (reportFailure(response, ctx) || response.status !== "handled") return;

            if (response.result.feedback) {
                pi.sendUserMessage(response.result.feedback, { deliverAs: "followUp" });
            } else if (response.result.approved) {
                pi.sendUserMessage("Plannotator code review approved the changes.", {
                    deliverAs: "followUp",
                });
            } else {
                ctx.ui.notify("Code review session closed.", "info");
            }
        },
    });

    pi.registerCommand("pll", {
        description: "Annotate the last assistant message in Plannotator",
        handler: async (args, ctx) => {
            const response = await request(pi, "annotate-last", {
                filePath: "last-assistant-message",
                mode: "annotate-last",
                gate: args.trim().split(/\s+/).includes("--gate"),
            });
            if (reportFailure(response, ctx) || response.status !== "handled") return;

            if (response.result.feedback) {
                pi.sendUserMessage(response.result.feedback, { deliverAs: "followUp" });
            } else if (response.result.approved) {
                ctx.ui.notify("Message approved.", "info");
            } else {
                ctx.ui.notify("Annotation session closed.", "info");
            }
        },
    });
}
