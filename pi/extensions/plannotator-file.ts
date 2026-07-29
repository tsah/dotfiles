import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

type AnnotationResponse =
    | { status: "handled"; result: { approved?: boolean; exit?: boolean; feedback?: string } }
    | { status: "unavailable" | "error"; error?: string };

export default function (pi: ExtensionAPI) {
    const command = {
        description: "Open a file or folder in Plannotator",
        handler: async (args: string, ctx: ExtensionContext) => {
            const requestedPath = args.trim();
            if (!requestedPath) {
                ctx.ui.notify("Usage: /plannotator-file <file | folder>", "error");
                return;
            }

            const expandedPath = requestedPath === "~"
                ? homedir()
                : requestedPath.startsWith("~/")
                    ? resolve(homedir(), requestedPath.slice(2))
                    : resolve(ctx.cwd, requestedPath);

            let isFolder: boolean;
            let markdown: string;
            try {
                isFolder = statSync(expandedPath).isDirectory();
                markdown = isFolder ? "" : readFileSync(expandedPath, "utf8");
            } catch (error) {
                ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
                return;
            }

            const response = await new Promise<AnnotationResponse>((respond) => {
                pi.events.emit("plannotator:request", {
                    requestId: crypto.randomUUID(),
                    action: "annotate",
                    payload: {
                        filePath: expandedPath,
                        markdown,
                        mode: isFolder ? "annotate-folder" : "annotate",
                        folderPath: isFolder ? expandedPath : undefined,
                    },
                    respond,
                });
            });

            if (response.status !== "handled") {
                ctx.ui.notify(response.error ?? "Plannotator is unavailable.", "error");
                return;
            }

            const { approved, exit, feedback } = response.result;
            if (feedback) {
                pi.sendUserMessage(`Plannotator feedback for ${expandedPath}:\n\n${feedback}`, {
                    deliverAs: "followUp",
                });
            } else if (approved) {
                ctx.ui.notify("Annotation approved.", "info");
            } else if (exit) {
                ctx.ui.notify("Annotation session closed.", "info");
            }
        },
    };

    pi.registerCommand("plannotator-file", command);
    pi.registerCommand("plf", command);
}
