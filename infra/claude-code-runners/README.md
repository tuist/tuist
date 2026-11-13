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
An orchestrator polls for spawn requests every 5 s (fixed, with 20% jitter),
so the Deployment runs two replicas to shorten the wait for the next poll;
Anthropic hands each request to one of them.
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
Dockerfile, `sbx-worker` and tart-kubelet (`internal/macosandbox/tools.go`,
whose test checks the pin against `sbx-worker`). macOS hosts download and
verify the pinned build once and share it with their VMs; a session copies
it from the share, and downloads it only when the host has not fetched it yet.

## Timing a session's start

- The orchestrator's container log has its polls, dispatches and hook
  outcomes (`[runner:orchestrator] ok ... (<n>ms)`), with session IDs and
  email addresses replaced by `-`. Its `/metrics` on port 8080, scraped by
  annotation, has `claude_code_self_hosted_orchestrator_session_queue_wait_seconds`
  (from the session's queueing to the orchestrator claiming its spawn request)
  and `..._spawn_hook_duration_seconds`.
- The server logs `sandboxes: claude code spawn request` when it answers
  (`spawn_result`, admission `duration_ms`), and `sandboxes: claude code
  runner started` with `placement_ms` (placement, carve-out growth and the
  VM's create or resume) and `spawn_ms` (request to started worker). The
  request log keeps only a sample of successful responses, so do not look
  for the spawn there.
- sandboxd logs the runner's own lines (`Registered`, `Picked up session`,
  `child spawned`, `a turn started`) as the worker's guest output.

## Startup and caches

- **Tuist cache:** the worker gets `TUIST_URL` and, when the account has an
  in-rack cache at the node's site, `TUIST_CACHE_ENDPOINT`. `sbx-worker`
  starts the runner with itself as `--exec-path`; that wrapper exports the
  session's `CLAUDE_CODE_SESSION_ACCESS_TOKEN` as `TUIST_OIDC_TOKEN` and execs
  Claude Code, so Tuist clients sign in with the session identity
  (`Tuist.OIDC`). The token is the one at spawn time (four hours by default).
- **Cached checkouts (macOS and Linux):** the hook sends
  `CLAUDE_RUNNER_PRIMARY_REPO_URL` as `repository_url`. When the account's
  GitHub installation reads that github.com repository, the worker starts
  with the repository's CI checkout volume: before the runner starts,
  `sbx-worker` copies the node's master of it to the runner's canonical clone
  (`<base-dir>/<owner>/<repo>`), so the runner fetches only what it lacks
  ([pre-warmed checkouts](https://code.claude.com/docs/en/self-hosted-environments-deploy#reuse-a-pre-warmed-checkout)).
  After the runner exits it exports the default branch's commit the server
  named at allocation, which the node verifies and builds the next master
  from, under the rules CI exports follow. macOS goes through a per-VM share,
  Linux through vsock to sandboxd and the runner-cache agent.
- **Setup script and repository snapshots (Linux):** an environment's
  optional `setup_script` (set on create or with `PATCH
  .../agent-environments/<id>`, at most 64 KB) prepares a repository: install
  toolchains and dependencies, prebuild. Sessions boot from the newest
  snapshot of their repository built with the current script, so the runner
  only fetches what changed. A session that finds none starts on the
  template as without a script and has one built in the background: a
  builder sandbox of the environment's shape clones the default branch with
  a contents-read token, runs the script there as `user` in a Bash login
  shell for up to an hour, with only the Tuist environment above (no Tuist
  or GitHub credential), and its disks are saved once it exits 0. No
  session waits for it. The script's output is in `~/.claude-code-setup.log`
  in the sessions. A failed script is logged and not built again for an
  hour. A changed script or a new template image on the nodes builds again
  on the next session; a new snapshot replaces the older ones of the
  repository, and one unused for 72 hours is deleted. macOS environments do
  not take a script yet.

`run-orchestrator.test.sh` and `spawn-runner.test.mjs` run in the sandbox-image
workflow. Not yet run end to end: a live session needs a Team or Enterprise
organization with a `ccpool_` environment, and the runner under `/Users/runner`
on macOS guests has not been qualified.
