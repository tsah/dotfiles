---
name: customize-opencode
description: Use ONLY when editing or creating opencode configuration, opencode.json, opencode.jsonc, .opencode files, ~/.config/opencode files, opencode agents, subagents, skills, plugins, MCP servers, or permission rules.
---

# Customizing opencode

opencode validates its own config strictly and refuses to start when a field
is wrong. The shapes below cover the common surface area, but they are a
summary, not the source of truth.

## Full schema reference

The authoritative list of every config option, with field types, enums,
defaults, and descriptions, lives in the published JSON Schema:

https://opencode.ai/config.json

If a field is not documented in this skill, or you need to confirm an exact
shape before writing config, fetch that URL and read the schema directly
rather than guessing. opencode hard-fails on invalid config, so the cost of a
wrong shape is a broken startup.

Every `opencode.json` should declare:

```json
{
  "$schema": "https://opencode.ai/config.json"
}
```

## Applying changes

Config is loaded once when opencode starts and is not hot-reloaded. After
saving changes to `opencode.json`, an agent file, a skill, a plugin, or any
other config-time file, tell the user to quit and restart opencode for the
changes to take effect. The running session keeps using already-loaded config.

## Where files live

| Scope | Path |
| --- | --- |
| Project config | `./opencode.json`, `./opencode.jsonc`, or `.opencode/opencode.json` |
| Global config | `~/.config/opencode/opencode.json` |
| Project agents | `.opencode/agent/<name>.md` or `.opencode/agents/<name>.md` |
| Global agents | `~/.config/opencode/agent(s)/<name>.md` |
| Project commands | `.opencode/command/<name>.md` or `.opencode/commands/<name>.md` |
| Global commands | `~/.config/opencode/command(s)/<name>.md` |
| Project skills | `.opencode/skill(s)/<name>/SKILL.md` |
| Global skills | `~/.config/opencode/skill(s)/<name>/SKILL.md` |
| External skills | `~/.claude/skills/<name>/SKILL.md`, `~/.agents/skills/<name>/SKILL.md` |

Configs from each scope are deep-merged. Project overrides global. Unknown
top-level keys in `opencode.json` are rejected with `ConfigInvalidError`.

## opencode.json

Every field is optional.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "username": "string",
  "model": "provider/model-id",
  "small_model": "provider/model-id",
  "default_agent": "agent-name",
  "shell": "/bin/zsh",
  "logLevel": "DEBUG",
  "share": "manual",
  "autoupdate": true,
  "snapshot": true,
  "instructions": ["AGENTS.md", "docs/style.md"],
  "skills": {
    "paths": [".opencode/skills", "/abs/path/to/skills"],
    "urls": ["https://example.com/.well-known/skills/"]
  },
  "references": {
    "docs": {
      "path": "../docs",
      "description": "Use for product behavior and documentation conventions"
    }
  },
  "agent": {
    "my-agent": {
      "model": "anthropic/claude-sonnet-4-6",
      "mode": "subagent",
      "description": "...",
      "permission": { "edit": "deny" }
    }
  },
  "command": {
    "deploy": { "description": "...", "template": "..." }
  },
  "provider": {
    "anthropic": { "options": { "apiKey": "..." } }
  },
  "disabled_providers": ["openai"],
  "enabled_providers": ["anthropic"],
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp"],
      "enabled": true,
      "env": {}
    }
  },
  "plugin": [
    "opencode-gemini-auth",
    "./local-plugin.ts",
    ["opencode-bar", { "option": "value" }]
  ],
  "permission": {
    "edit": "deny",
    "bash": { "git *": "allow", "*": "ask" }
  },
  "formatter": false,
  "lsp": false,
  "experimental": {
    "primary_tools": ["edit"],
    "mcp_timeout": 30000
  },
  "tool_output": { "max_lines": 200, "max_bytes": 8192 },
  "compaction": { "auto": true, "tail_turns": 15 }
}
```

Shape notes worth being explicit about:

- `model` always carries a provider prefix: `anthropic/claude-sonnet-4-6`.
- `skills` is an object with `paths` and/or `urls`, not an array.
- `references` is an object keyed by alias.
- `agent` is an object keyed by agent name, not an array.
- `command` is an object keyed by command name, not an array.
- `plugin` is an array of strings or `[name, options]` tuples, not an object.
- `mcp[name].command` is an array of strings, never a single string. `type` is required.
- `permission` is either a string action or an object keyed by tool name.

## Skills

opencode's skill loader scans for `**/SKILL.md` inside skill directories. The
file is named `SKILL.md` exactly, and lives in its own folder named after the
skill:

```text
.opencode/skills/my-skill/SKILL.md
```

Frontmatter:

```markdown
---
name: my-skill
description: One sentence covering what this skill does AND when to trigger it. Front-load likely keywords or filenames.
---

# My Skill

(skill body in markdown: instructions, examples, references)
```

- `name` is required, lowercase hyphen-separated, up to 64 chars, and matches the folder name.
- `description` is effectively required: skills without one are filtered out and never surfaced to the model.
- Optional fields include `license`, `compatibility`, and `metadata`.

Register skills from non-default locations via `skills.paths` and `skills.urls`.

## References

References make local directories and Git repositories outside the active
project available as supporting context. Configure them under `references`,
keyed by the alias used in `@` autocomplete:

```json
{
  "references": {
    "docs": {
      "path": "../product-docs",
      "description": "Use for product behavior and terminology"
    },
    "effect": {
      "repository": "Effect-TS/effect",
      "branch": "main",
      "description": "Use for Effect implementation details"
    }
  }
}
```

Local `path` values may be relative to the declaring config, absolute, or use
`~/`. Git `repository` values accept Git URLs, host/path references, and GitHub
`owner/repo` shorthand. `branch` is optional. Both forms support optional
`description` and `hidden` fields.

- Only references with a `description` are advertised to agents in system context.
- `hidden: true` removes a reference from TUI `@` autocomplete only.
- Reference directories are automatically allowed through the external-directory boundary.
- String shorthand is supported: use `"docs": "../docs"` or `"effect": "Effect-TS/effect"`.

## Agents

Two ways to define an agent. Use the file form for anything non-trivial.

Inline `opencode.json` form:

```json
{
  "agent": {
    "my-reviewer": {
      "description": "Reviews PRs for style violations.",
      "mode": "subagent",
      "model": "anthropic/claude-sonnet-4-6",
      "permission": { "edit": "deny", "bash": "ask" },
      "prompt": "You are a strict PR reviewer..."
    }
  }
}
```

File form:

```text
.opencode/agent/my-reviewer.md
.opencode/agents/my-reviewer.md
```

```markdown
---
description: Reviews PRs for style violations.
mode: subagent
model: anthropic/claude-sonnet-4-6
permission:
  edit: deny
  bash: ask
---

You are a strict PR reviewer. Focus on...
```

The file body becomes the agent's `prompt`. Do not also put `prompt:` in the
frontmatter.

`mode` is one of `primary`, `subagent`, or `all`.

Allowed top-level frontmatter fields are `name`, `model`, `variant`,
`description`, `mode`, `hidden`, `color`, `steps`, `options`, `permission`,
`disable`, `temperature`, and `top_p`. Unknown fields are routed into `options`.

To disable a built-in agent, use `agent: { build: { disable: true } }`, or in a
file, `disable: true` in frontmatter.

`default_agent` must point to a non-hidden, primary-mode agent.

Built-in agents include `build`, `plan`, `general`, and `explore`. Hidden
internal agents include `compaction`, `title`, and `summary`.

## Commands

opencode's command loader scans for `**/*.md` inside command directories. The
file is named after the command, and lives directly inside the `command` folder:

```text
.opencode/command/deploy.md
```

Frontmatter:

```markdown
---
description: One sentence describing what the command does.
agent: build
model: anthropic/claude-sonnet-4-6
---

(command body in markdown: the prompt opencode runs, with $ARGUMENTS for the user's input)
```

- `template` is the command body and is required. Do not also put a `template:` key in frontmatter.
- `$ARGUMENTS` is replaced with everything typed after the command.
- `$1`, `$2`, and later positional arguments pull individual arguments.
- Optional fields include `description`, `agent`, `model`, `variant`, and `subtask`.

## Plugins

`plugin` is an array. Each entry is one of:

```json
{
  "plugin": [
    "opencode-gemini-auth",
    "opencode-foo@1.2.3",
    "./local-plugin.ts",
    "file:///abs/path/plugin.js",
    ["opencode-bar", { "key": "val" }]
  ]
}
```

Auto-discovered plugins need no config entry when they are `*.ts` or `*.js`
files in `.opencode/plugin/` or `.opencode/plugins/`.

A plugin module exports `default` or any named export of type `Plugin`. The
export is a function, not a plain object literal, and the function returns an
object. Return `{}` if there is nothing to register.

```ts
import type { Plugin } from "@opencode-ai/plugin"

export default (async ({ client, project, directory, $ }) => {
  return {
    config: (cfg) => {
      // cfg is the live merged config; mutate fields here.
    },
    "tool.execute.before": async (input, output) => {
      // mutate output.args before the tool runs.
    },
  }
}) satisfies Plugin
```

Hook surface mutates `output` in place and returns `void`:

- `event(input)`: every bus event.
- `config(cfg)`: once on init with the merged config.
- `chat.message`, `chat.params`, `chat.headers`.
- `tool.execute.before`, `tool.execute.after`, `tool.definition`.
- `command.execute.before`.
- `shell.env`.
- `permission.ask`.
- `experimental.chat.messages.transform`, `experimental.chat.system.transform`, `experimental.session.compacting`, `experimental.compaction.autocontinue`, `experimental.text.complete`.

Special object-shaped hooks include `tool: { my_tool: { ... } }`, `auth: { ... }`,
and `provider: { ... }`.

## MCP servers

`mcp` is an object keyed by server name. Each server is discriminated by `type`:

```json
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp"],
      "enabled": true,
      "env": { "BROWSER": "chromium" }
    },
    "github": {
      "type": "remote",
      "url": "https://...",
      "enabled": true,
      "headers": { "Authorization": "Bearer {env:GITHUB_TOKEN}" }
    },
    "old-server": { "enabled": false }
  }
}
```

`command` is an array of strings. `type` is required. Use `enabled: false` to
disable a server inherited from a parent config. Header token strings support
`{env:VAR}` and `{file:path}` interpolation; shell-style `${VAR}` is not
substituted.

## Permissions

```json
{
  "permission": {
    "edit": "deny",
    "bash": { "git *": "allow", "rm *": "deny", "*": "ask" },
    "external_directory": { "~/secrets/**": "deny", "*": "allow" }
  }
}
```

Actions are `allow`, `ask`, and `deny`.

Per-tool value forms are an action string shorthand or an object of pattern to
action. Within an object, insertion order matters. opencode evaluates the last
matching rule, so put broad rules first and narrow rules last.

`permission: "allow"` at the top level is shorthand for allowing everything
and is rarely what the user wants.

Known permission keys include `read`, `edit`, `glob`, `grep`, `list`, `bash`,
`task`, `external_directory`, `todowrite`, `question`, `webfetch`, `websearch`,
`lsp`, `doom_loop`, and `skill`. Some of these only accept a flat action, not a
per-pattern object.

`external_directory` patterns are filesystem paths using `~/`, absolute paths,
or globs like `~/projects/**`.

Per-agent `permission` overrides top-level `permission`. Plan Mode lives on the
`plan` agent's permission ruleset.

## Escape hatches

When config is broken and opencode will not start, these environment variables help:

- `OPENCODE_DISABLE_PROJECT_CONFIG=1`: skip the project's local config.
- `OPENCODE_CONFIG=/path/to/file.json`: load an additional explicit config.
- `OPENCODE_CONFIG_CONTENT='{"$schema":"https://opencode.ai/config.json"}'`: inject inline JSON.
- `OPENCODE_DISABLE_DEFAULT_PLUGINS=1`: skip default plugins.
- `OPENCODE_PURE=1`: skip external plugins entirely.
- `OPENCODE_DISABLE_EXTERNAL_SKILLS=1`: skip external skill scans.
- `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`: skip `~/.claude` and `~/.agents` skill scans.

## When proposing edits

- Validate against the schema before writing. If unsure of a field's exact shape, fetch `https://opencode.ai/config.json`.
- Preserve `$schema` and existing fields the user did not ask to change.
- For agent, command, skill, and plugin definitions, prefer creating files in the correct location over inlining everything in `opencode.json`.
- If config is malformed, point the user at the escape-hatch environment variables.
- After saving any config change, remind the user to quit and restart opencode.
