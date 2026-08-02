---
name: agent-coordination
description: >-
  Coordinate existing visible agent sessions through the Waystation agent API.
  Use when the user asks to find or list agents or workers, inspect agent status
  or progress, monitor or wait for a worker, send instructions or follow-ups,
  steer or redirect an agent, retrieve its result or response, collect worker
  output, keep tabs on agents, or orchestrate multiple running workers. Never
  communicate with agents through tmux input or pane capture.
---

# Agent Coordination

Operate on existing visible agents through Waystation's stable agent API. This
skill does not create workers; use `handoff` when a new isolated worktree worker
is required.

## Non-negotiable rules

1. Use the stable `agentId` for every operation. Session, window, and pane names
   are display/focus metadata, not orchestration identity.
2. Check advertised capabilities before waiting, sending, steering, or reading a
   result.
3. Use generation-aware waits so an old completion cannot satisfy a new task.
4. Treat timeout as nondestructive and leave the worker/worktree available.
5. Never use `tmux send-keys`, `load-buffer`, `paste-buffer`, or `capture-pane`
   for agent communication or monitoring.
6. Never silently fall back when a harness lacks a native capability. Report the
   limitation and offer supported alternatives.
7. In-process harness subagents are not Waystation agents; use that harness's
   own result/steering tools for them.

## Intent mapping

| User intent | Command |
|---|---|
| list, find, discover, show workers | `waystation agent list` |
| check status, progress, monitor, keep tabs | `waystation agent status AGENT_ID` |
| ask what operations are supported | `waystation agent capabilities AGENT_ID` |
| wait, await, notify when finished | `waystation agent wait AGENT_ID` |
| tell, ask, message, instruct, follow up | `waystation agent send AGENT_ID` |
| interrupt, redirect, steer now | `waystation agent send AGENT_ID --delivery steer` |
| retrieve, collect, show response/result | `waystation agent result AGENT_ID` |

## Discover and resolve identity

Prefer current-worktree discovery when the request concerns the current project:

```bash
waystation agent list --cwd "$PWD"
```

Use global discovery only when the user asks across projects:

```bash
waystation agent list
```

If exactly one agent matches the requested worktree/harness/name, use it. If
multiple plausible agents remain, show a compact choice containing harness,
name, worktree, state, and `agentId`; do not guess. Reuse a known `agentId`
returned by a handoff instead of rediscovering by name.

## Inspect and monitor

```bash
waystation agent status "$agent_id"
waystation agent capabilities "$agent_id"
```

For a status check, return the snapshot immediately. For “monitor” or “keep tabs
on,” inspect status and then wait if the user wants completion. Avoid rapid
polling; `wait` is the lifecycle-aware primitive.

Before waiting, capture the current settlement baseline:

```bash
status=$(waystation agent status "$agent_id")
# Read settledGeneration from the JSON response.
waystation agent wait "$agent_id" --after "$settled_generation"
```

If the worker is already settled and the user only asks for its current result,
do not wait for a hypothetical new generation; retrieve the result directly.

## Send instructions

Use stdin so arbitrary multiline instructions remain one argument-safe payload:

```bash
printf '%s' "$message" | waystation agent send "$agent_id"
```

Default delivery is appropriate for normal instructions: idle agents begin
immediately and busy Pi agents queue a native follow-up.

Use explicit follow-up when the user says “after you finish,” “next,” or
“follow up”:

```bash
printf '%s' "$message" |
  waystation agent send "$agent_id" --delivery follow-up
```

Use steering only when the user explicitly wants to interrupt or redirect the
current work:

```bash
printf '%s' "$message" |
  waystation agent send "$agent_id" --delivery steer
```

When the user wants the response, prefer the correlated operation:

```bash
printf '%s' "$message" |
  waystation agent send "$agent_id" --wait --timeout 600
```

Only one unsettled external Waystation message is admitted per Pi agent. If a
send is rejected because another message is awaiting settlement, wait for that
message or ask the user whether to retry afterward.

## Wait and retrieve results

Wait for a known baseline:

```bash
waystation agent wait "$agent_id" --after "$settled_generation" --timeout 600
```

Retrieve the latest result:

```bash
waystation agent result "$agent_id"
```

Retrieve a specific historical generation when correlating multiple turns:

```bash
waystation agent result "$agent_id" --generation "$generation"
```

A worker result with a nonzero status is still a valid structured result. Report
its stop reason/error and preserve the worker for follow-up.

## Capability and error handling

Capabilities are authoritative. Current expected support is:

- Pi: status, report wait, native send, structured result
- Claude/Codex: status and report wait; no verified native send/result
- OpenCode: monitor-only until its native lifecycle/mutation contract is enabled

Do not hardcode that matrix in orchestration logic; inspect `capabilities`
because support can evolve.

Waystation errors are versioned JSON on stderr:

- exit `3`: unknown or ambiguous ID — rediscover or ask the user
- exit `4`: unsupported capability — report it without fallback
- exit `5`: unavailable/mismatched native endpoint — suggest `/reload` or restart
  for an older Pi process, then rediscover
- exit `124`: nondestructive timeout — report that the agent remains available

## Multiple-agent orchestration

For several workers:

1. Retain each launcher's `agentId` with its assigned task.
2. Inspect capabilities and status independently.
3. Use each agent's own settlement generation as its wait baseline.
4. Collect results by ID and generation, not completion order.
5. Send review feedback only to agents that advertise native send.
6. Summarize which workers are working, waiting, ready, failed, timed out, or
   unsupported without collapsing those states together.
