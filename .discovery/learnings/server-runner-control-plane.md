# Server-backed runner control plane

## Key correction

The productized runner architecture should not rely on static GitHub runner credentials stored in machine configuration.

For a multi-tenant service, the control plane should live in `server/` and mint runner registration material dynamically from the existing GitHub App integration.

## Existing server modules that matter

### GitHub App auth and token minting

- `server/lib/tuist/github/app.ex`
  - generates GitHub App JWTs
  - exchanges them for installation access tokens
  - caches installation tokens with TTL

- `server/lib/tuist/github/client.ex`
  - already makes authenticated GitHub API calls using installation IDs
  - follows the pattern `installation_id -> get_installation_token() -> GitHub API`

### Tenant/account scoping

- `server/lib/tuist/vcs/github_app_installation.ex`
  - one GitHub App installation is linked to one Tuist account

- `server/lib/tuist/projects/vcs_connection.ex`
  - a project is linked to a specific repository and GitHub App installation

- `server/lib/tuist_web/live/integrations_live.ex`
  - UI flow for connecting repositories through an account-scoped GitHub installation

### Setup and webhook patterns

- `server/lib/tuist_web/controllers/github_app_setup_controller.ex`
  - creates the account-scoped installation record after GitHub app setup

- `server/lib/tuist_web/plugs/webhook_plug.ex`
  - generic HMAC webhook verification plug

- `server/lib/tuist_web/controllers/webhooks/github_controller.ex`
  - example of account/repo-scoped webhook handling for GitHub events

## What this implies for runners

### Control plane boundary

`/runners` should stay the host bootstrap layer.

`server/` should own:

- tenant-aware runner provisioning
- dynamic registration token minting
- job assignment policy
- runner pool ownership by account/org/project
- lifecycle cleanup after each run

### Recommended scoping model

- Account owns the GitHub App installation.
- Projects map to repositories through `vcs_connections`.
- Runner pools should be account-scoped first.
- Jobs can then be restricted to project/repository subsets inside the account.

This matches the current server data model better than host-scoped or repo-scoped runners only.

## Recommended control-plane flow

1. A runner host boots with Nix and phones home to Tuist server.
2. The server authenticates the host as part of a runner pool for one account.
3. The server uses the account's GitHub App installation to mint short-lived registration material.
4. The host writes that material to the runtime token path only.
5. The host registers a runner just-in-time or ephemerally.
6. After one workflow run, the host tears down runner state and asks for the next assignment.

## GitHub API pieces that fit this design

### Registration options

- Organization registration token endpoint
  - `POST /orgs/{org}/actions/runners/registration-token`
  - returns a time-limited token that expires after about one hour
  - acceptable for a basic dynamic-registration flow

- Organization JIT configuration endpoint
  - `POST /orgs/{org}/actions/runners/generate-jitconfig`
  - requires:
    - runner `name`
    - `runner_group_id`
    - `labels`
    - optional `work_folder`
  - stronger fit for per-assignment registration

### Grouping and tenancy controls

- Organization runner groups support:
  - selected repository visibility
  - explicit repository membership
  - explicit runner membership
  - custom labels on specific runners

This is the cleanest GitHub-side primitive for mapping Tuist account/project tenancy to runner eligibility.

### Job lifecycle signal

- The `workflow_job` webhook is the key GitHub event to watch for queued, in-progress, and completed jobs.
- The server should subscribe at the org level and use these events to:
  - create assignments when jobs are queued
  - mark leases active when jobs start
  - trigger cleanup and deregistration when jobs complete

## Recommended mapping into Tuist server

### GitHub-side scope

- one GitHub App installation per Tuist account already exists
- one or more GitHub runner groups per account is the natural next layer
- selected repositories in those groups should be derived from `vcs_connections`

### Tuist-side scope

- account-scoped runner pool
- host records inside a pool
- ephemeral assignment records keyed to GitHub workflow jobs
- repository/project allowlist per pool or group

## Suggested phase order

### Phase 1

- dynamic org registration token minted by `server/`
- one tenant per test host
- no static runner token in machine config

### Phase 2

- JIT config generation from `server/`
- `workflow_job`-driven assignment lifecycle
- tighter group/repository restrictions

### Phase 3

- VM-backed execution per assignment
- host becomes only a VM worker, not the direct runner boundary

## Why this is better than static tokens

- no long-lived runner PAT in host config
- account-level GitHub authorization already exists in server
- easier tenant isolation and revocation
- better fit for ephemeral runners and per-run sandboxing

## Sandboxing implications

### Week 1

- host bootstrap in `/runners`
- runner service disabled by default until control plane is ready
- one-account test host only
- per-run cleanup and narrow labels

### Product path

- runner registration should be per-assignment, not static
- workflow execution should be isolated per run
- the server should own assignment state and revocation

### Realistic isolation levels

- bare-metal persistent runner: not acceptable for broad multi-tenant service use
- ephemeral runner on shared host: better, but still weak if filesystem and simulator state persist
- VM-per-run or equivalent strong host reset: most aligned with the service goal

On this exact 8 GB M1 host, VM-per-run is likely a phase-2 or phase-3 path, not the week-1 baseline.

## Recommended next server-side building blocks

- new `Tuist.Runners` context in `server/lib/tuist/`
- account-scoped runner pool schema
- runner host schema with lease/heartbeat state
- job assignment schema keyed by account/project/repository/workflow run
- webhook or polling bridge for GitHub Actions `workflow_job` lifecycle
- endpoint for hosts to fetch short-lived registration material

## Important conclusion

The right architecture is:

- `/runners`: reproducible host bootstrap
- `server/`: multi-tenant control plane and dynamic GitHub integration

Any static token stored in host config should be treated as a temporary experiment only, not the service design.
