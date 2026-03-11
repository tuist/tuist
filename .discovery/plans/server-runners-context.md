# `server/lib/tuist/runners` context plan

## Goal

Add a server-side control plane that turns the existing GitHub App integration into a multi-tenant runner service.

The key split is:

- `/runners` owns host bootstrap
- `server/` owns tenancy, job assignment, dynamic registration, and lifecycle

## Existing primitives to reuse

- `Tuist.GitHub.App`
  - mints and caches installation access tokens
- `Tuist.GitHub.Client`
  - already wraps authenticated GitHub REST calls
- `Tuist.VCS.GitHubAppInstallation`
  - binds one GitHub App installation to one Tuist account
- `Tuist.Projects.VCSConnection`
  - binds one Tuist project to one GitHub repository inside that installation
- `TuistWeb.Plugs.WebhookPlug`
  - reusable HMAC webhook verification
- `TuistWeb.Webhooks.GitHubController`
  - existing pattern for GitHub event dispatch

## Main design constraint

The current VCS model is good enough to resolve:

- account
- installation
- repository

but not yet enough to manage runners cleanly at scale.

Notably missing for runner orchestration:

- installation target type (`Organization` vs `User`)
- installation target login/handle
- runner pool metadata
- host capability inventory
- per-job lease state

## Proposed context layout

### Context

- `server/lib/tuist/runners.ex`

### Schemas

- `server/lib/tuist/runners/runner_pool.ex`
- `server/lib/tuist/runners/runner_host.ex`
- `server/lib/tuist/runners/runner_assignment.ex`
- optional later: `server/lib/tuist/runners/runner_webhook_delivery.ex`

### Workers

- `server/lib/tuist/runners/workers/assignment_timeout_worker.ex`
- `server/lib/tuist/runners/workers/host_reaper_worker.ex`
- `server/lib/tuist/runners/workers/cleanup_worker.ex`

### API/Webhook surface

- `server/lib/tuist_web/controllers/api/runners_controller.ex`
- `server/lib/tuist_web/controllers/webhooks/github_runners_controller.ex`

## Proposed schema shapes

### `runner_pools`

One logical pool of runners for one Tuist account and one GitHub scope.

Suggested fields:

- `account_id`
- `github_app_installation_id`
- `provider` (`github`)
- `scope_type` (`organization`, `repository`)
- `scope_handle` (e.g. `tuist`, `owner/repo`)
- `github_runner_group_id` nullable
- `registration_mode` (`registration_token`, `jit_config`)
- `isolation_mode` (`bare_metal`, `vm_per_assignment`)
- `regions` / routing metadata
- `labels_template` JSON
- `status`

Why it matters:

- pool is the unit that bridges account tenancy and GitHub runner scope

### `runner_hosts`

One physical Mac or one VM worker host.

Suggested fields:

- `runner_pool_id`
- `hostname`
- `provider_host_id` nullable
- `public_ip`
- `private_ip`
- `region`
- `platform` (`macos`)
- `architecture` (`arm64`)
- `xcode_versions` JSON or array
- `capabilities` JSON
- `status` (`idle`, `busy`, `offline`, `draining`, `errored`)
- `last_heartbeat_at`
- `last_seen_version`

Why it matters:

- host is the schedulable capacity unit until VM-per-assignment is introduced

### `runner_assignments`

One GitHub workflow job leased to one host.

Suggested fields:

- `runner_pool_id`
- `runner_host_id`
- `project_id` nullable
- `vcs_connection_id` nullable
- `repository_full_handle`
- `workflow_job_id`
- `workflow_run_id`
- `workflow_name`
- `job_name`
- `requested_labels` JSON
- `github_runner_id` nullable
- `status` (`queued`, `leased`, `registered`, `in_progress`, `cleanup`, `completed`, `failed`, `cancelled`)
- `queued_at`
- `leased_at`
- `started_at`
- `completed_at`

Why it matters:

- assignment becomes the audit trail and cleanup boundary for per-run execution

## Recommended API surface for hosts

### Host bootstrap

- `POST /api/runners/hosts/register`
  - host presents bootstrap credential
  - server returns pool membership and policy

### Heartbeat

- `POST /api/runners/hosts/:id/heartbeat`
  - updates health, Xcode inventory, and current load

### Assignment polling

- `POST /api/runners/hosts/:id/next-assignment`
  - returns either no work or a lease payload

### Dynamic registration material

- `POST /api/runners/assignments/:id/registration`
  - server mints GitHub registration token or JIT config on demand

### Completion and cleanup

- `POST /api/runners/assignments/:id/complete`
  - host reports terminal state and cleanup result

## Mapping onto the validated Tart worker flow

The host-side worker lifecycle is now concrete enough to map onto these APIs:

1. `register` -> host receives pool membership and base-image policy
2. `next-assignment` -> host receives assignment metadata
3. local worker clones a disposable Tart VM for the assignment
4. local worker prepares cache access and guest readiness
5. `registration` -> host fetches dynamic GitHub runner material
6. guest runs the assignment
7. `complete` -> host reports outcome and destroys the clone

This means the future `Tuist.Runners` context should think in terms of:

- assignment -> disposable VM -> cleanup

not:

- assignment -> long-lived shared host process

## Recommended GitHub webhook surface

### New handler

- `TuistWeb.Webhooks.GitHubRunnersController`

### Event of interest

- `workflow_job`

Server responsibilities:

- when a compatible job is queued, create a pending assignment candidate
- when it starts, mark the assignment in progress
- when it completes, trigger cleanup and release capacity

## Important modeling decision

### Organization vs repository scope

GitHub supports JIT configuration at both:

- organization scope
- repository scope

Recommended policy:

- prefer organization-scoped runner pools when the installation target is an org
- use repository-scoped fallback for smaller or unsupported cases

This implies one useful schema/migration follow-up:

- enrich `github_app_installations` with target type/login metadata, or fetch and cache it lazily

## Suggested implementation order

1. Add `Tuist.Runners` context and schemas.
2. Add host registration and heartbeat endpoints.
3. Add GitHub API wrapper functions for registration token and JIT config minting.
4. Add `workflow_job` webhook handling.
5. Add assignment leasing and cleanup workers.
6. Only then enable dynamic runner activation on the Mac hosts.

## Data compliance note

When these schemas are implemented for real, `server/data-export.md` must be updated because runner pools, assignments, repository mappings, and execution metadata will be customer data.
