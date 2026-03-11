# Dynamic GitHub runner registration flow

## Goal

Replace static host-held runner credentials with server-issued registration material.

## Basic flow

1. GitHub emits a `workflow_job` event for a queued job.
2. Tuist server matches the repository/account/job labels to a runner pool.
3. A host asks for work and receives an assignment.
4. The host requests registration material for that assignment.
5. The server mints either:
   - an org or repo registration token, or
   - a JIT config blob
6. The host writes the material to runtime-only paths and registers the runner.
7. The job runs.
8. The job completes.
9. The host deregisters, wipes work state, and returns to idle.

## GitHub registration options

### Option A: registration token

Endpoint examples:

- `POST /orgs/{org}/actions/runners/registration-token`
- repository equivalent also exists

Properties:

- expires quickly
- simple mental model
- good first dynamic path

Tradeoff:

- registration and subsequent runner shaping still happen in more than one step

### Option B: JIT config

Endpoint examples:

- `POST /orgs/{org}/actions/runners/generate-jitconfig`
- `POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig`

Inputs include:

- `name`
- `runner_group_id`
- `labels`
- `work_folder`

Properties:

- better fit for assignment-time registration
- lets the server decide labels/grouping at the last responsible moment
- lines up better with ephemeral runner design

Tradeoff:

- more orchestration complexity up front

## Recommendation

### Phase 1

- use dynamic registration tokens minted by `server/`
- keep one test host / one tenant

### Phase 2

- move to JIT config as the normal registration path
- use runner groups as the GitHub-side tenant boundary

## GitHub-side controls to use

### Runner groups

Use them for:

- repository allowlists
- tenant segmentation
- limiting which repos can land on which runner pool

### Labels

Use them for:

- capabilities (`macos`, `apple-silicon`)
- region (`par`, later others)
- Xcode version (`xcode-26-2`)
- workload class (`ios-tests`, `build-only`, `preview`)

Avoid using labels as the only tenant boundary.

## Runtime contract on the host

The host should keep only runtime state:

- `/var/run/tuist/github-runner.token` or a JIT config blob
- a per-assignment work directory
- logs and audit metadata

The host should not keep:

- long-lived GitHub PATs
- account-wide registration secrets in static config

## Cleanup contract

After each assignment:

- remove runner registration if needed
- wipe the work directory
- wipe temporary credentials
- clear simulator/device artifacts as much as practical
- report completion back to `server/`

## Open questions

- how much `workflow_job` data is sufficient for pre-assignment routing in practice
- whether repo-scoped JIT is needed as a first step for non-org installations
- whether GitHub App installation tokens alone have the exact permissions needed for all runner-management endpoints in every target topology
