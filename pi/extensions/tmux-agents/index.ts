import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const SubagentParams = Type.Object({
	prompt: Type.String({
		description: "Objective for the spawned pi subagent, including context, constraints, and definition of done.",
	}),
	agent: Type.Optional(Type.String({ description: "Optional agent name from ~/.pi/agent/agents, ~/.claude/agents, or project agent directories." })),
	cwd: Type.Optional(Type.String({ description: "Working directory for the spawned agent. Defaults to the current cwd." })),
	windowName: Type.Optional(Type.String({ description: "Optional tmux window name. Defaults to p:<agent> or p:pi." })),
	wait: Type.Optional(Type.Boolean({ description: "If true, keep the spawned pi window interactive and wait until its initial task completes." })),
});

const TworkerParams = Type.Object({
	prompt: Type.String({
		description: "Objective for the spawned pi worker, including context, constraints, and definition of done.",
	}),
	branch: Type.Optional(
		Type.String({ description: "Branch name for the worktree. If omitted, a short kebab-case name is derived from the prompt." }),
	),
	agent: Type.Optional(Type.String({ description: "Optional agent name from ~/.pi/agent/agents, ~/.claude/agents, or project agent directories." })),
	windowName: Type.Optional(Type.String({ description: "Optional tmux window name. Defaults to pi-agent." })),
	wait: Type.Optional(Type.Boolean({ description: "If true, keep the spawned pi window interactive and wait until its initial task completes." })),
});

function resolveDotfilesDir(): string {
	if (process.env.DOTFILES_DIR) {
		return process.env.DOTFILES_DIR;
	}
	return path.join(os.homedir(), "dotfiles");
}

function resolveScript(scriptName: string): string {
	const dotfilesScript = path.join(resolveDotfilesDir(), "bin", scriptName);
	if (fs.existsSync(dotfilesScript)) {
		return dotfilesScript;
	}
	return scriptName;
}

function trimOutput(text: string): string {
	return text.trim() || text;
}

function deriveBranchName(prompt: string): string {
	const slug = prompt
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.replace(/-+/g, "-")
		.split("-")
		.filter(Boolean)
		.slice(0, 8)
		.join("-")
		.slice(0, 48)
		.replace(/-+$/g, "");

	if (slug.length > 0) {
		return slug;
	}

	const stamp = new Date().toISOString().replace(/[-:TZ.]/g, "").slice(0, 12);
	return `task-${stamp}`;
}

async function runScript(pi: ExtensionAPI, scriptName: string, args: string[], signal: AbortSignal | undefined) {
	const script = resolveScript(scriptName);
	return pi.exec(script, args, { signal });
}

function resultFromExec(result: { stdout: string; stderr: string; code: number }, fallback: string) {
	if (result.code !== 0) {
		return {
			content: [{ type: "text" as const, text: trimOutput(result.stderr) || trimOutput(result.stdout) || fallback }],
			details: { stdout: result.stdout, stderr: result.stderr, code: result.code },
			isError: true,
		};
	}

	return {
		content: [{ type: "text" as const, text: trimOutput(result.stdout) || fallback }],
		details: { stdout: result.stdout, stderr: result.stderr, code: result.code },
	};
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "tmux_subagent",
		label: "Tmux Subagent",
		description:
			"Launch a separate pi agent in a new tmux window inside the current tmux session. Use this when the user wants a parallel or subordinate pi agent while staying in the same repo/worktree. If wait is true, keep the spawned pi window interactive and wait until its initial task completes.",
		promptSnippet: "Launch a separate pi agent in a new tmux window in the current tmux session.",
		promptGuidelines: [
			"Use tmux_subagent when the user wants another pi agent running in parallel in the current tmux session.",
			"Set wait=true when the parent agent needs to block until the spawned agent completes its assigned task.",
			"Pass objectives, context, constraints, and definition of done to the spawned agent.",
			"Do not micromanage implementation steps unless the user explicitly asks for that level of instruction.",
		],
		parameters: SubagentParams,
		async execute(_toolCallId, params, signal, onUpdate) {
			onUpdate?.({ content: [{ type: "text", text: "Launching tmux subagent..." }] });

			const args: string[] = [];
			if (params.agent) {
				args.push("--agent", params.agent);
			}
			if (params.cwd) {
				args.push("--cwd", params.cwd);
			}
			if (params.windowName) {
				args.push("--window-name", params.windowName);
			}
			if (params.wait) {
				args.push("--wait");
			}
			args.push(params.prompt);

			try {
				const result = await runScript(pi, "spawn-pi-subagent", args, signal);
				return resultFromExec(result, "tmux subagent launched");
			} catch (error) {
				return {
					content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
					details: {},
					isError: true,
				};
			}
		},
	});

	pi.registerTool({
		name: "tmux_tworker",
		label: "Tmux Tworker",
		description:
			"Launch a separate pi worker in a new tmux session backed by a git worktree. Use this when the user wants an isolated worker/task branch instead of a same-session window. If wait is true, keep the spawned pi window interactive and wait until its initial task completes.",
		promptSnippet: "Launch a separate pi worker in a new tmux session and git worktree.",
		promptGuidelines: [
			"Use tmux_tworker when the user wants an isolated worker or task branch in a separate tmux session.",
			"Set wait=true when the parent agent needs to block until the worker completes its assigned task.",
			"Prefer short lowercase kebab-case branch names.",
			"Pass objectives, context, constraints, and definition of done to the worker.",
			"Do not do extra preflight work when tmux_tworker is the right tool; call it directly.",
		],
		parameters: TworkerParams,
		async execute(_toolCallId, params, signal, onUpdate) {
			onUpdate?.({ content: [{ type: "text", text: "Launching tmux tworker..." }] });

			const branch = params.branch && params.branch.trim().length > 0 ? params.branch.trim() : deriveBranchName(params.prompt);
			const args: string[] = [];
			if (params.agent) {
				args.push("--agent", params.agent);
			}
			if (params.windowName) {
				args.push("--window-name", params.windowName);
			}
			if (params.wait) {
				args.push("--wait");
			}
			args.push(branch, params.prompt);

			try {
				const result = await runScript(pi, "spawn-pi-tworker", args, signal);
				return resultFromExec(result, `tmux tworker launched on ${branch}`);
			} catch (error) {
				return {
					content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
					details: {},
					isError: true,
				};
			}
		},
	});
}
