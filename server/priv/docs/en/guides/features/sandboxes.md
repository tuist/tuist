---
{
  "title": "Sandboxes",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Tuist Sandboxes are persistent Linux and macOS virtual machines for coding agents such as Amp and Claude. Each agent session gets its own machine, which pauses when the agent is idle and resumes with its files intact."
}
---
# Sandboxes {#sandboxes}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Sandboxes, both Linux and macOS, are currently invite-only while we scale capacity. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account. Pricing will be announced when Sandboxes become generally available.

A sandbox is a virtual machine where a coding agent runs its commands and edits its files. Each agent session gets its own sandbox, which keeps its checkout, build products and installed tools for the life of the session. When the agent goes idle, the sandbox pauses; the next message resumes it where it left off.

Sandboxes run on the same fleet as <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, next to your team's <.localized_link href="/guides/features/cache">cache</.localized_link>, so an agent's builds can use the same cached artifacts as your CI and local machines.

You can use sandboxes from:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: run your Amp workspace's orbs on Tuist.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: run Claude Managed Agents sessions and Claude Code cloud sessions (claude.ai, the desktop and mobile apps, and `claude --cloud`) on Tuist.
- **[The API](#api)**: create sandboxes and run commands in them yourself.

## Linux and macOS {#platforms}

Every sandbox runs one platform for its whole life. Each integration lets you choose the platform per session.

**Linux** sandboxes are Ubuntu 24.04 virtual machines with Git, the GitHub CLI, Node.js, [mise](https://mise.jdx.dev) and a headless browser installed. The workspace is `/workspace`.

- 2 vCPU, 4 GiB RAM (default)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandboxes are macOS virtual machines on Apple silicon with Xcode and the tooling of the Tuist macOS runner image. The workspace is `/Users/runner/work`.

- 8 vCPU, 8 GiB RAM (default)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

The workspace disk is 10 GB by default and can grow up to 100 GB.

macOS sandboxes share Apple silicon hosts with Tuist's macOS runners, and CI jobs come first. When the hosts are busy with CI, a new or resumed macOS sandbox waits until a host frees up, and it starts more slowly than a Linux one.

## Lifecycle {#lifecycle}

A sandbox is in one of these states:

- **Running**: the agent is working, or just finished a turn.
- **Paused**: the agent has been idle, so the sandbox was stopped with its disk kept. It resumes automatically when the agent's next turn arrives, with its files intact.
- **Archived**: a paused Linux sandbox was moved to object storage, either because you archived it or, for Amp orbs, because it stayed paused for a long time. It resumes like a paused one, after a slower restore.

A sandbox that stays paused, or in an error state, for 14 days is deleted. A session that comes back after that gets a fresh sandbox with its repository checked out again. <.localized_link href="/guides/features/sandboxes/amp">Amp orbs</.localized_link> follow Amp's own lifecycle instead. You can always pause, resume or delete a sandbox yourself from the dashboard or the API.

## Dashboard {#dashboard}

Open **Sandboxes** in your account's dashboard to see:

- The integrations connected to the account, and the controls to connect <.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>.
- Usage: vCPU-hours, sandboxes created, session and start-up durations, and peak usage against your account's limits.
- Every sandbox with its status, platform, shape and the session it serves, with actions to pause, resume, archive or delete it.

Only account administrators can see and manage sandboxes, because a sandbox runs arbitrary commands.

## API {#api}

The sandboxes API is part of the [Tuist API](https://tuist.dev/api/docs) under `/api/accounts/{account_handle}/sandboxes`. It requires an account administrator. Authenticate with `tuist auth login` and pass the token that `tuist auth token` prints:

```bash
export TUIST_TOKEN=$(tuist auth token)

# Create a macOS sandbox (omit "platform" for Linux).
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{"platform": "darwin"}'

# Run a command in it. A paused sandbox resumes first.
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/$SANDBOX_ID/exec" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{"command": "xcodebuild -version", "timeout_ms": 60000}'
```

- `POST /sandboxes`: Boots a sandbox. Optional `platform` (`linux` or `darwin`), `vcpus`, `memory_mb` and `workspace_gb`.
- `GET /sandboxes`, `GET /sandboxes/{id}`: Lists sandboxes, or gets one.
- `POST /sandboxes/{id}/exec`: Runs a command with `bash -lc` and returns its exit code, stdout and stderr (up to 1 MiB each). Times out after `timeout_ms`, 60 seconds by default and 10 minutes at most.
- `POST /sandboxes/{id}/pause`, `/resume`: Pauses or resumes the sandbox.
- `POST /sandboxes/{id}/archive`: Moves a paused Linux sandbox to object storage.
- `DELETE /sandboxes/{id}`: Deletes the sandbox and its files.
- `GET /sandboxes/analytics`: Usage for a time range.

Most of these operations are also available to agents as <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link> tools.

## Security {#security}

- Each sandbox is its own virtual machine. Sandboxes don't share a file system, memory or processes with each other or with CI jobs.
- Sandboxes belong to an account, and only its administrators can manage them. Sessions from an integration only reach the sandboxes of the account the integration is connected to.
- Credentials you give Tuist to connect an integration, such as an Amp provider token or a Claude environment key, are stored encrypted and never shown again.
- A sandbox can reach the internet. Treat what an agent can access from it the way you would treat a CI job.
