# Automatic Flaky Test Resolution Plan

## Decisions already made

- Start the automation when a test case is threshold-marked as flaky, not on the first flaky run.
- V1 only supports GitHub-connected projects.
- V1 opens a draft PR in the project's GitHub repo.
- V1 creates one draft PR per flaky test case.

## Goal

When `server/` marks a test case as newly flaky, it should automatically kick off a remote fix workflow on the macOS machine, try to fix the test with OpenCode + the `fix-flaky-tests` skill, and end with a draft PR in the project's GitHub repo.

## Recommended architecture

### 1. Trigger from the existing flaky threshold flow

Hook into `Tuist.Alerts.Workers.FlakyThresholdCheckWorker` right after `Tests.update_test_case/3` succeeds and the test case becomes flaky for the first time.

Why this is the right trigger:

- it already represents "this is a real flaky test" in product terms
- it avoids spending runner time on one-off noise
- it gives us the final `test_case_id` we want to track end-to-end

### 2. Use Oban as the orchestration layer

Do not add a dedicated `flaky_fix_jobs` table for V1.

Instead, make this just be an Oban job with a unique key on `test_case_id` so we do not stampede the runner for the same flaky test.

Recommended worker behavior:

- queue one job per newly marked flaky test case
- keep the job args lean
- use the Oban job id as the correlation id for runner callbacks
- if we later want durable UI/history, add a real table in phase 2 or 3

### 3. Add a dedicated Oban worker in `server/`

Create something like `Tuist.Tests.Workers.EnqueueFlakyFixWorker`.

Flow:

1. Load the project with `vcs_connection`.
2. Skip unless the project is connected to GitHub.
3. Build a small payload with just enough info for the runner to start.
4. POST a signed webhook to the macOS runner service.

This should mirror the existing external processor pattern already used by `Tuist.Builds.Workers.ProcessBuildWorker`.

### 4. Add a new runner webhook endpoint in `server/`

Expose something like `/webhooks/flaky-fix-runner` using the existing `TuistWeb.Plugs.WebhookPlug`.

The runner will call this endpoint to report state changes:

- `running`
- `failed`
- `pr_opened`

Payload should include:

- `job_id`
- `status`
- `branch`
- `pr_url`
- optional `message`

This keeps the server as the source of truth while the machine does the actual fixing.

For V1, the callback handler can stay very lightweight:

- log `running` / `failed` / `pr_opened`
- correlate by Oban job id
- optionally emit telemetry or send a Slack message later

We do not need a whole persistence layer before the happy path works.

## Runner service on the macOS machine

Build a very small long-running HTTP service on `m1@51.159.120.232`.

Responsibilities:

- accept signed webhook jobs from `server/`
- maintain a local checkout cache per repo
- run the agentic fix flow
- push a branch
- create a draft PR with `gh`
- send a completion webhook back to `server/`

No sandboxing, no multi-tenant hardening, no fancy queueing for V1.

### Suggested runner flow

1. Receive webhook with job payload.
2. Resolve local checkout path for `owner/repo`.
3. If missing, clone it.
4. If present, fetch latest refs.
5. Checkout the target base branch.
6. Create a fresh fix branch, e.g. `auto/fix-flaky-test/<test-case-id>`.
7. Run OpenCode with the `fix-flaky-tests` skill and a prompt containing the Tuist test case URL/id plus repo context.
8. Let the agent use:
   - `tuist test case show ...`
   - `tuist test case run list ... --flaky`
   - `tuist test case run show ...`
   - local source edits
   - repeated test execution
9. If files changed, commit, push, and run `gh pr create --draft`.
10. POST the resulting PR URL back to `server/`.

### Clone strategy

Recommended default:

- use `project.vcs_connection.repository_full_handle`
- clone with `gh repo clone owner/repo`
- cache repos under `~/tuist-flaky-fixes/owner/repo`

No config map for V1. Just put repos in a predictable place and keep moving.

## Payload shape from server to runner

The payload should stay lean. The runner/OpenCode flow can pull the heavy flaky-test context itself via Tuist CLI.

Recommended payload:

- `job_id`
- `account_handle`
- `project_handle`
- `test_case_id`
- `test_case_url`
- `repository_full_handle`
- `repository_url`
- `base_branch`

Everything else should be discovered on the machine with:

- `tuist test case show ...`
- `tuist test case run list ... --flaky`
- `tuist test case run show ...`

This keeps the runner dumb and fast.

## How OpenCode should be used

The runner should invoke OpenCode as the main agent, using the existing `skills/skills/fix-flaky-tests/SKILL.md` workflow.

Recommended prompt ingredients:

- the test case URL or `test_case_id`
- the repo path already checked out locally
- the branch name to work on
- an instruction to end with a draft PR-ready commit
- an instruction to report back `branch`, `commit`, and `pr_url`

Also worth aligning the server MCP prompt and the skill if we refine the workflow during implementation.

## Minimal server changes

- new Oban worker to enqueue remote fixes
- make that worker unique per `test_case_id`
- call site inside `FlakyThresholdCheckWorker`
- new env vars for runner URL + shared secret
- new webhook controller for runner callbacks
- optional UI surface later to show fix status / PR link on the flaky test page

If we do add UI later, the simplest useful shape is probably a small card on the flaky test detail page with:

- latest auto-fix status badge
- runner branch name
- draft PR link
- last attempted at timestamp

## Minimal runner changes

- lightweight webhook server
- local repo cache management
- OpenCode invocation wrapper
- git/gh PR helper
- callback client back to `server/`
- maybe a tiny log file per job for debugging

## Rollout plan

### Phase 1: make the happy path real

- trigger a job when a test case becomes flaky
- deliver webhook to the mac runner
- auto-clone into `~/tuist-flaky-fixes/...`
- run OpenCode with the flaky-test skill
- create a branch and draft PR
- report PR URL back to server

### Phase 2: make it usable

- make sure we do not open multiple PRs for the same still-open flaky test
- show job status / PR link in the server UI
- add a tiny durable record only if we actually need history in product

### Phase 3: make it less janky

- automatic clone for any GitHub-connected repo
- stale branch cleanup on the runner
- basic retry / timeout handling

## Machine preflight

I re-checked the machine and these are now available:

- `opencode` -> `/opt/homebrew/bin/opencode`
- `gh` -> `/opt/homebrew/bin/gh`
- `tuist` -> `/opt/homebrew/bin/tuist`

So the runner service should either run through a login shell or just call those absolute paths directly.

## Best first implementation slice

If we want the fastest route to something magical working:

1. add `EnqueueFlakyFixWorker`
2. make it unique per `test_case_id`
3. add signed webhook from `server/` to the mac runner
4. clone/fetch the target repo into `~/tuist-flaky-fixes/...`
5. run OpenCode with `fix-flaky-tests`
6. push branch + open draft PR
7. callback PR URL into `server/`

That gets us from "new flaky test detected" to "draft PR exists" with the smallest amount of infrastructure.
