# Claude Code cloud sessions on Tuist sandboxes

Claude Code (web, desktop, mobile and the CLI) runs cloud sessions in a
[self-hosted environment](https://code.claude.com/docs/en/self-hosted-environments)
when one is selected. The environment fixes the OS: an account connects one
environment per platform, and users pick Linux or macOS by picking the
environment.

## Setup

1. A Claude Team or Enterprise Owner creates a self-hosted environment per OS
   on claude.ai (admin settings → Cloud environments), for example `Tuist Linux`
   and `Tuist macOS`, and copies each one's `ccpool_...` ID and environment
   secret.
2. A Tuist account admin connects each one:

   ```sh
   curl -X POST "$TUIST_URL/api/accounts/$ACCOUNT/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H 'Content-Type: application/json' \
     -d '{"kind": "claude_code", "platform": "darwin", "name": "Tuist macOS",
          "anthropic_environment_id": "ccpool_...", "environment_key": "<environment secret>"}'
   ```

   Omit `platform` (or pass `linux`) for the Linux one. Shape fields
   (`template`, `vcpus`, `memory_mb`, `workspace_gb`) and `max_idle_seconds`
   (default 1800 for Claude Code) work as for Managed Agents environments.

## Choosing the OS

- **Claude Desktop, web and mobile:** pick `Tuist Linux` or `Tuist macOS` in
  the environment selector of a new cloud session.
- **Claude Code CLI:** pick the environment by name with `/remote-env`; later
  `claude --cloud "<task>"` runs on it. `--environment ccpool_...` picks one for
  a single session, and `remote.defaultEnvironmentId` in Claude Code settings
  sets a default for a repository or team.
- **Managed Agents API:** Managed Agents environments are separate (`env_...`);
  see `infra/tart-kubelet/macos-sandboxes.md` for per-session `platform` and the
  `tuist_platform` metadata key.

## How it runs

`Tuist.Sandboxes.ClaudeCodeReconciler` keeps one Deployment per connected
environment (`claude-code-<id>` in the Amp provider namespace) running this
image: `claude self-hosted-runner orchestrator` with the environment secret.
When a session needs a runner, the orchestrator's `hooks/spawn-runner` posts the
work order to `/api/internal/claude-code-runners/spawn` with the Deployment's
projected service-account token (audience `tuist-claude-code-runners`). The
server answers before the VM boots (202 accepted, 204 already running, 409/429/503
retry later). It creates or resumes the session's sandbox on the environment's
platform and starts `sbx-worker` with the work order, and `sbx-worker` runs
`claude self-hosted-runner` for that one session in the workspace. The runner
exits after `max_idle_seconds` without activity, which pauses the sandbox; the
session's next message resumes the same sandbox.

Claude Code is pinned to one version in this Dockerfile, the template
Dockerfile and `sbx-worker`; macOS guests download and verify the pinned binary
on first use.

`run-orchestrator.test.sh` and `spawn-runner.test.mjs` run in the sandbox-image
workflow. Not yet run end to end: a live session needs a Team or Enterprise
organization with a `ccpool_` environment, and the runner under `/Users/runner`
on macOS guests has not been qualified.
