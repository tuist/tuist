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

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: run your Amp workspace's orbs on Tuist, or give any Amp thread a Mac for Xcode builds with the <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac plugin</.localized_link>.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: run Claude Managed Agents sessions and Claude Code cloud sessions (claude.ai, the desktop and mobile apps, and `claude --cloud`) on Tuist.
- **[The Tuist CLI](#cli)**: create sandboxes and run commands in them from your terminal, or from your own tools through the API.

## Get started with the CLI {#cli}

Create a sandbox and run commands in it from your terminal with `tuist sandbox`.

### 1. Log in {#cli-log-in}

Any member of the account can create and manage its sandboxes:

```bash
tuist auth login
```

### 2. Create a sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omit `--platform` for Linux. Pass `--xcode` with a version, such as `--xcode 26.1.1`, for a Mac with that [Xcode](#xcode); it implies `--platform macos`. Pass `--vcpus` with `--memory-gb` for a larger [shape](#platforms), `--guaranteed-vcpus` to guarantee a Linux sandbox more [CPU](#guaranteed-cpu), and `--workspace-gb` for a larger disk. The sandbox runs for two hours from creation, and again from each resume; pass `--lifetime-minutes` for between 5 minutes and a day. When its lifetime ends, its running commands are cancelled and it's paused and archived, keeping its files, so a forgotten sandbox stops using your account's capacity. The command returns once the sandbox is running and prints its details, including its ID. When every host is busy, such as while CI jobs hold the shared Macs, the server waits 25 seconds for one before the create fails with `fleet_busy`; pass `--wait-timeout 5m` to keep trying for up to 5 minutes (at most an hour), with the reason repeated on stderr about once a minute. It uses the account of the Tuist project in the current directory; pass `--account` to choose another.

### 3. Run commands {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

The command runs with `bash -l` in the sandbox, which resumes first if it's paused. `tuist` streams its output however long it runs and exits with the command's status; Ctrl-C cancels it in the sandbox. Pass `--cwd`, `--env NAME=VALUE` and `--timeout` (up to six hours) as needed.

The command runs detached from `tuist`, so it survives a dropped connection. To fit a long build into a tool call with a time limit, such as an agent's, pass `--wait <seconds>`: when they pass first, `tuist` leaves the command running, exits with 75 and prints the `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` command that continues its output where it stopped and exits with the command's status.

### Common tasks {#cli-tasks}

| Task | Command |
| --- | --- |
| List sandboxes | `tuist sandbox list` |
| Show one | `tuist sandbox show <id>` |
| Pause or resume | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Keep it running past its expiry | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Mirror the local Git worktree's files into it | `tuist sandbox sync <id>` |
| Screenshot the booted iOS Simulator or the whole screen of a macOS sandbox | `tuist sandbox screenshot <id> --out shot.png`, `tuist sandbox screenshot <id> --screen --out screen.png` |
| Copy files out or in | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Delete | `tuist sandbox delete <id> --yes` |
| See usage | `tuist sandbox analytics` |

Add `--json` for machine-readable output. See the <.localized_link href="/cli/sandbox">CLI reference</.localized_link> for every option. To drive sandboxes from code instead, use the same operations through the [Tuist API](https://tuist.dev/api/docs) under `/api/accounts/{account_handle}/sandboxes`, or let an agent use them through <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

Tools that can't log in interactively, such as an agent plugin that builds in a macOS sandbox, can authenticate with an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `account:sandboxes:write` scope instead. It can do what a member of the account can: create sandboxes, run commands in them, and pause, resume, archive and delete them. Integration settings, and running commands in sandboxes that serve an integration, stay with account administrators.

### Tuist inside the sandbox {#tuist-in-sandbox}

macOS sandboxes come with the Tuist CLI. When your project pins Tuist through mise (`mise.toml` or `.tool-versions`), `tuist` runs that version instead, installed the first time a command needs it. Every command you start with `tuist sandbox exec` has mise's shims (`$HOME/.local/share/mise/shims`) first on `PATH` and the image's Tuist last, so `tuist` and your other mise tools run in your commands and in Xcode build phases, such as a scheme's post-actions. Each Mac also carries a guide for coding agents at `/opt/tuist/agent-guide.md`, generated from its image: its Xcode and simulators, where the repository is, and what a ready snapshot holds. Claude Code, Codex and Amp running on the Mac find it from their instruction files.

Every command you start with `tuist sandbox exec` also gets what a Tuist runner gets, so builds in the sandbox use your account's <.localized_link href="/guides/features/cache">cache</.localized_link> without you passing credentials:

- `TUIST_URL` and, where the sandbox's host reaches it, such as on macOS, the `TUIST_CACHE_ENDPOINT` of the cache in the same rack.
- `TUIST_OIDC_TOKEN`, a short-lived identity token for that command. Tuist CLI 4.218.0 and later sign in with it on their own; with 4.215.0 to 4.217.x, run `tuist auth login` first in the same command.

The token is minted for each command and can only be exchanged for a Tuist token while that command runs, so a sandbox never holds a long-lived credential. It never grants more than the person or token that started the command can do with the cache: members of an account whose cache only tokens can write get read access, and an account token needs cache scopes, such as `ci`, alongside `account:sandboxes:write` for the sandbox to use the cache at all. Variables you pass with `--env` take precedence.

## Build on a Mac from a coding agent {#coding-agents}

A coding agent that runs on Linux, such as a cloud agent session, can build, test and run Apple-platform code on a macOS sandbox while it keeps editing files where it runs. In Amp, install the <.localized_link href="/guides/features/sandboxes/amp#remote-mac">Tuist Mac plugin</.localized_link>. For other agents, such as Claude Code or Cursor:

1. Connect the agent to the Tuist <.localized_link href="/guides/features/agentic-coding/mcp">MCP server</.localized_link>. Its `create_sandbox` tool tells the agent how to drive the Mac.
2. Install the Tuist CLI where the agent runs, for example in the environment's setup script: `mise use -g tuist@latest`, or `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (`tuist-linux-aarch64` on ARM).
3. Authenticate the CLI. The MCP server's sign-in doesn't carry over to it, so either run `tuist auth login` as an account member, or set `TUIST_TOKEN` to an <.localized_link href="/guides/server/authentication#account-tokens">account token</.localized_link> with the `account:sandboxes:write` scope.
4. If the environment restricts network access, allow `tuist.dev`. The CLI uploads files to the Mac through it, so it needs no other domain.
5. Optionally, let the agent create and delete Macs without asking each time. Agents ask before calling `create_sandbox` because a Mac counts toward your account's limits, and before `delete_sandbox` because it can't be undone. In Claude Code, allow both in `.claude/settings.json`, using the name you registered the MCP server under (`tuist` here):

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

To have the agent do the setup, give it this prompt:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

The agent creates one Mac per task, with the [Xcode](#xcode) the project pins: `create_sandbox` lists the Xcodes it can pick and tells the agent to read the project's pin, such as `.xcode-version`. Before each command, it runs `tuist sandbox sync`. It copies the files Git doesn't ignore, committed or not, and afterwards only the ones that changed. The Mac already has [Tuist](#tuist-in-sandbox), the project's pinned version when it pins one, signed in to your account's cache, and the agent reads the Mac's guide once. The agent then runs commands such as `xcodebuild` with `tuist sandbox exec`, launches the app in the Simulator and shows it to you with the MCP server's `get_sandbox_screenshot` or `tuist sandbox screenshot`, copies results such as a built app back with `tuist sandbox cp`, and deletes the Mac when the task is done. A Mac stays running for 10 minutes after its last command, so the next one starts at once; `tuist sandbox pause` gives it back sooner. A Mac left behind then pauses, is archived when its two-hour lifetime ends, and is deleted after 14 days; the agent extends the lifetime before a long build.

## Linux and macOS {#platforms}

**Linux** sandboxes run Ubuntu 24.04. Every Linux sandbox has 16 vCPUs and bursts into the idle cores of the machine it runs on, so its shape picks its memory:

- 2 GiB RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB RAM (`--vcpus 2 --memory-gb 4`, default)
- 8 GiB RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB RAM (`--vcpus 16 --memory-gb 44`)

**macOS** sandboxes run on Apple silicon with Xcode:

- 8 vCPU, 8 GiB RAM (default)
- 8 vCPU, 16 GiB RAM
- 8 vCPU, 24 GiB RAM

### Guaranteed CPU {#guaranteed-cpu}

A Linux sandbox is guaranteed a quarter of a vCPU per GiB of its memory, such as 2 vCPUs for 8 GiB, and uses as much more as its machine has idle, up to its 16 vCPUs. That suits an agent, which mostly waits and then builds in bursts. When a build needs more steady CPU even on a busy machine, guarantee it 1, 2, 4 or 8 vCPUs when the sandbox is created; it gets the larger of that and its memory's guarantee:

| Where | How |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API and MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **A guarantee is a floor, not a cap.** A sandbox with 4 guaranteed vCPUs still bursts to 16 when cores are idle. Under contention, each sandbox gets CPU in proportion to its guarantee.
- **It's billed as a minimum.** A running sandbox is billed for the CPU it uses, but never for less than its guarantee.
- **A sandbox keeps its guarantee for life.** To change it, create a new sandbox.
- **macOS sandboxes always have their whole shape**, so they don't take a guarantee.

### Choose an Xcode {#xcode}

Each macOS sandbox runs one Xcode, which you choose when it's created. It boots the same image as the <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> profile for that Xcode, so an agent builds with the same toolchain and simulators as your CI. On tuist.dev, macOS sandboxes currently offer:

- `26.6` (default)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Choose one with `xcode_version` (`--xcode` in the CLI), using the exact version, as runner profiles do:

| Where | How |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API and MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Tuist Mac plugin for Amp | `tuist_mac_start` with `xcode` |
| Amp orbs | The orb type `macos-xcode-26-1-1` (see <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code and Claude Managed Agents | `xcode_version` on the environment, or per Managed Agents session (see <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Without a version**, a Mac gets the default.
- **A version Tuist doesn't offer is refused**, and the error lists the versions you can choose, so you know what is available right now.
- **Tuist doesn't read your repository's `.xcode-version`.** You, or the agent that asks for the Mac, choose the version. The MCP tool and the Tuist Mac plugin tell agents to match the version the project pins.
- **A sandbox keeps its Xcode for life.** To build with another Xcode, create a new sandbox. `xcodebuild -version` shows which Xcode a Mac runs.

## Security {#security}

- Each sandbox is its own virtual machine. Sandboxes don't share a file system, memory or processes with each other or with CI jobs.
- Sandboxes belong to an account, and any of its members can use and manage them. Sandboxes that serve an integration, such as an Amp orb or a Claude Code session, hold that session's work and credentials: members can see, pause, resume, archive and delete them, but only administrators can run commands in them or upload files to them. Only administrators connect integrations. Sessions from an integration only reach the sandboxes of the account the integration is connected to.
- Credentials you give Tuist to connect an integration, such as an Amp provider token or a Claude environment key, are stored encrypted and never shown again.
- A sandbox can reach the internet. Treat what an agent can access from it the way you would treat a CI job.
