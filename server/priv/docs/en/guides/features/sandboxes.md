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
- **[The Tuist CLI](#cli)**: create sandboxes and run commands in them from your terminal, or from your own tools through the API.

## Get started with the CLI {#cli}

Create a sandbox and run commands in it from your terminal with `tuist sandbox`.

### 1. Log in {#cli-log-in}

Managing sandboxes requires an account administrator:

```bash
tuist auth login
```

### 2. Create a sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omit `--platform` for Linux. Pass `--vcpus` with `--memory-gb` for a larger [shape](#platforms), and `--workspace-gb` for a larger disk. The command returns once the sandbox is running and prints its details, including its ID. It uses the account of the Tuist project in the current directory; pass `--account` to choose another.

### 3. Run commands {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

The command runs with `bash -lc` in the sandbox, which resumes first if it's paused, and `tuist` exits with the command's status.

### Common tasks {#cli-tasks}

| Task | Command |
| --- | --- |
| List sandboxes | `tuist sandbox list` |
| Show one | `tuist sandbox show <id>` |
| Pause or resume | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Delete | `tuist sandbox delete <id> --yes` |
| See usage | `tuist sandbox analytics` |

Add `--json` for machine-readable output. See the <.localized_link href="/cli/sandbox">CLI reference</.localized_link> for every option. To drive sandboxes from code instead, use the same operations through the [Tuist API](https://tuist.dev/api/docs) under `/api/accounts/{account_handle}/sandboxes`, or let an agent use them through <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

## Linux and macOS {#platforms}

**Linux** sandboxes run Ubuntu 24.04:

- 2 vCPU, 4 GiB RAM (default)
- 4 vCPU, 8 GiB RAM
- 8 vCPU, 16 GiB RAM

**macOS** sandboxes run on Apple silicon with Xcode:

- 8 vCPU, 8 GiB RAM (default)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

## Security {#security}

- Each sandbox is its own virtual machine. Sandboxes don't share a file system, memory or processes with each other or with CI jobs.
- Sandboxes belong to an account, and only its administrators can manage them. Sessions from an integration only reach the sandboxes of the account the integration is connected to.
- Credentials you give Tuist to connect an integration, such as an Amp provider token or a Claude environment key, are stored encrypted and never shown again.
- A sandbox can reach the internet. Treat what an agent can access from it the way you would treat a CI job.
