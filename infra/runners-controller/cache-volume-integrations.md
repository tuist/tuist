# Cache volume integrations

GitHub Actions, Buildkite and GitLab CI share entry points for Linux and native
macOS jobs, with server identity adapters. They share private per-job local image clones, per-volume
capacity (see [Size](#size)), seven-day idle expiry, generation fencing, teardown checks and the dashboard.
macOS uses the [APFS backend](../tart-kubelet/custom-cache-volumes.md), including
for the managed `tuist-xcode` and `tuist-module` volumes. Provider and platform namespaces never share data implicitly.

| Provider | Entry point | Publication policy after a successful job |
| --- | --- | --- |
| GitHub Actions | `tuist/cache-volume@v1`, key, one or more paths (one per line) and `cache-hit` output | Same-repository push, schedule, workflow_dispatch or pull request on any branch, narrowed by the runner profile |
| Buildkite | `tuist/cache-volume#v1` plugin with a list of volumes, each with a key and one or more paths | Webhook or schedule on any branch, no tag; PRs only from the pipeline's repository; narrowed by the runner profile |
| GitLab CI | Installed `tuist-cache-volume` command or reusable before_script include | Push, schedule or web branch pipeline on any branch, no tag; MR pipelines only for same-project MRs with a connection API token; narrowed by the runner profile |

All three entry points are packaged and automatically released from `main`.
The initial distribution-repository setup and local-image/Kata fleet smoke gates remain
rollout work. Publishing a wrapper does not enable storage on the fleet.
Neither packaging nor fake-coordinator tests establish live storage compatibility.

## Workflow interfaces and distribution

The GitHub action source is in
[`.github/actions/cache-volume`](../../.github/actions/cache-volume/README.md).
It uses `github.action_path`, so the standalone package requires no monorepo
checkout. The wrapper uses the installed native or job-container client.

The Buildkite plugin is in
[`ci/cache-volume/buildkite`](../../ci/cache-volume/buildkite/README.md).
Its `pre-command` hook parses `BUILDKITE_PLUGIN_CONFIGURATION` as JSON, validates
all volumes before attaching, and invokes the installed client once per
volume with one `--path` per configured path. It propagates failures and does not run a publication hook. The Linux
image persists pod routing into the staged job environment before Buildkite
sanitizes inherited variables; the global environment hook exports it again.
See [plugin hooks](https://buildkite.com/docs/pipelines/integrations/plugins/writing).

`.github/workflows/cache-volume-action.yml` tests and packages all integrations
on PRs. Relevant pushes to `main` automatically release them together using the
existing `release:check cache-volume` and git-cliff version calculation. A shared
`cache-volume@1.0.0` monorepo release tracks matching `v1.0.0` distribution tags:

- `tuist/cache-volume`: standalone GitHub action.
- `tuist/cache-volume-buildkite-plugin`: Buildkite plugin with executable hook.
- `tuist/cache-volume-gitlab`: reusable `cache-volume.yml` for `include:remote`.

As a one-time bootstrap, create those repositories with a `main` branch and give
`TUIST_RELEASE_GITHUB_TOKEN` write access. Each release pushes the generated main
branch, immutable version tag and moving major tag atomically. The monorepo tag
is recorded only after all three pushes succeed. Releases are serialized;
stale runs predating the latest monorepo release are rejected.

If publication is interrupted, rerun the workflow or dispatch it on current main.
`prepare-release.sh` reads the incomplete immutable distribution tags and rebuilds
all packages from their original `SOURCE_COMMIT`, without relying on old workflow
artifacts. Conflicting source commits fail closed. After recovery records that
version, the workflow dispatches a new main run to release any later changes.
Rolling back consumers means pinning an earlier immutable tag or
commit; a code rollback on main produces a new release instead of rewriting tags.

The [GitLab include and example](../../ci/cache-volume/gitlab/README.md) compose
an attachment snippet into `before_script` without replacing other setup.
The embedded shell executor explicitly forwards only the three pod-local volume
routing variables. Job `image:` does not create a Docker executor.
[`cache:`](https://docs.gitlab.com/ci/caching/) remains archive caching and restores
before attachment, as do artifacts; remove overlapping paths to avoid the
nonempty-directory check. Unrelated archive cache entries keep working.
A vendorable include works on self-managed GitLab too; a GitLab.com-only Catalog
component would not, because [components require the same instance](https://docs.gitlab.com/ci/components/).

Buildkite native commands and GitLab shell jobs work on Linux and macOS.
macOS mounts remain inside the guest and do not automatically enter a separate
Docker VM. On Linux, Docker child containers require explicit mapping of
`/home/runner/work/_tuist_cache` to the same absolute path, alongside the checkout,
because attached directories are symlinks. Automatic Docker-plugin wiring is
not included. Validate those mounts and execution UID separately; GitHub's
container smoke does not prove other container integrations.

## Identity and trust

`CacheVolumes.allocate/1` resolves the running Linux or macOS pod through its live
`RunnerSession.executed_workflow_job_id`. Buildkite/GitLab acquisition already
records that exact assigned job. The new `CacheVolumes.Identity` adapter
retrieves provider metadata; the storage lifecycle never accepts scope or save
permission from the mount request or job environment.

- **GitHub:** retain the existing installation-authenticated run/repository
  lookup, including run attempt and source repository checks.
- **Buildkite:** before returning the job acquisition token, retrieve the account-owned job UUID through the existing
  [Stacks job API](https://buildkite.com/docs/apis/agent-api/stacks). Check job,
  build, build number, organization slug and pipeline slug against the assignment.
  Scope by the server-returned organization UUID, pipeline UUID and SHA-256 of
  the repository URL. Renames preserve identity; repointing a pipeline changes
  scope. The API's [protected environment fields](https://buildkite.com/docs/pipelines/configure/environment-variables)
  supply branch, default branch, PR, tag and source. Never inspect the plugin's
  environment for this decision. Manual/API builds remain read-only because a
  manually supplied branch is not guaranteed to contain the requested commit.
  Persist only the normalized scope and save decision on the account-owned job
  mapping: Stacks returns 404 for the full payload once its agent has acquired
  the job. Mounts use that snapshot with the live executed-job binding and an
  enabled installation. Failed refreshes clear prior authority. No additional
  API token is needed.
- **GitLab:** use the encrypted acquired job token for
  [GET /job](https://docs.gitlab.com/api/jobs/#retrieve-a-job-by-job-token), checking
  the assigned job ID, project ID, running status and commit SHA. Scope by the
  canonical instance digest and immutable project ID. Find the exact branch
  with an escaped anchored regex through the
  [branches listing API](https://docs.gitlab.com/api/branches/); its
  `default` flag marks a default-branch writer. Any branch pipeline with an
  allowed job `pipeline.source` and `tag == false` carries its ref as the writer
  branch the runner profile matches. The job token cannot read merge requests,
  so merge request pipelines save only when the connection has an optional
  `api_token`: the ref (`refs/merge-requests/N/...`) names the merge request,
  and its source project must be the project itself. The writer branch is its
  source branch. A missing token or failed lookup leaves the job read-only. Use the top-level `source` only when the nested field is absent;
  an unknown or denied nested source cannot fall back to a permissive value.
  Both endpoints are available to [job tokens](https://docs.gitlab.com/ci/jobs/ci_job_token/).
  `CI_PROJECT_ID`, `CI_DEFAULT_BRANCH` and other overridable variables grant
  no authority. A GitLab instance without the source field cannot grant save
  permission. Missing credentials, identity mismatch or denied API access
  decline attachment instead of guessing. Calls retain SSRF pinning,
  response bounds, no redirects and no automatic acquisition retry.

The verified identity and `can_publish` decision are persisted when allocating;
later purging GitLab's temporary assignment does not lose them. PR/MR and other
non-writer jobs can reuse data in their project/pipeline scope without saving.
Forks in a separate GitLab project have a separate scope.

All providers require a successful recorded job outcome and local pod/writer
teardown. The GitLab executor's zero process exit after a reported job failure
does not authorize publication. Failed/cancelled jobs, clear-generation fences,
orphan reconciliation and acknowledged deletion use the common existing logic.

## Size

A volume's capacity is chosen by the server for each use. The guest may send
`requested_volume_bytes` (a whole number of decimal GB, 1 to 100 GB) with its
acquire request; hosts drop any other value and never fail a request because of
it. Hosts forward a valid request and always send `max_volume_bytes`, their
largest accepted volume: 32 GB on Linux (`--max-volume-gb`,
`runnersFleetLinux.cacheVolumes.maxVolumeGB`) and 100 GB on macOS
(`--custom-cache-max-volume-gb`) by default. A server answer of 507 means the
volume exceeds that maximum: the host does not retry and the job continues
cold (macOS mailbox reason `capacity`, Linux status 503). A volume without a server-chosen size is
created at the host default of 20 GB.

A cold branch is created at its capacity. A warm copy smaller than the capacity
is grown before the job sees it and never shrunk: Linux extends the cloned image
and grows ext4 online after mounting it on the host; macOS extends the private
sparse image with `hdiutil resize -imageonly` and the guest grows the APFS
container after attaching. A copy that cannot grow attaches warm at its saved size.

The managed `tuist-xcode` (30 GB by default) and `tuist-module` (20 GB) volumes
follow the same rules. Their entry points send the size as `--size` to the
runner image's `tuist-runner-cache`, which attaches the volume and then sets the
cache's own limit (`COMPILATION_CACHE_LIMIT_SIZE`, `TUIST_CACHE_MAX_BYTES`) and
the teardown compilation-cache prune from the capacity the guest measures on the
mounted image, so a copy that could not grow is bounded at its saved size.

Admission scales with the volume. Linux requires the `--min-free-gb` floor
raised by however much the volume exceeds `--volume-gb`: with the defaults, the
larger of 40 GB and the capacity plus 20 GB. macOS reserves the capacity for a
cold branch, the larger of the capacity and twice the head's measured used
bytes (`head_size_bytes`) for a warm one, and twice the head's used bytes for a
prefetch. Without a known head size, warm attaches and prefetches reserve twice
the capacity. Guest usage reports and expanded downloads are bounded by the host
maximum, so a host accepts grown masters.

## Migration and rollback

The migration adds provider, provider instance and immutable scope to volume
identity and its unique index. Existing rows become GitHub/github.com/repository
ID identities while retaining volume UUIDs, generations and physical snapshots.
Account, key, architecture and execution UID remain part of the unique identity.
The numeric repository ID becomes optional for Buildkite; its actual identity is
the organization/pipeline/repository scope, not a fabricated GitHub ID.

Indexes are built concurrently. Downgrade refuses non-GitHub rows: first disable
new provider allocations and clean those volumes through the normal physical
cleanup path. Do not discard metadata while storage journals still reference it.
The data-export inventory documents the extra identity fields.

## Validation and fleet acceptance

Local suites cover provider metadata mismatches, untrusted sources, spoofed CI
variables, cross-account resolution, API rejection, project/instance isolation,
pipeline rename/repointing, per-provider warm reuse, quoted workflow inputs,
Buildkite environment sanitization, and GitLab execution outcomes.
The migration is exercised in an isolated schema with a pre-existing GitHub row,
including its downgrade guard.

Before enabling a fleet, run each actual packaged entry point through cold/warm
reuse across hosts, simultaneous clones, failure/cancellation, PR/MR and other
branches, clear during a job, and delayed cleanup. Validate local filesystem provisioning,
local-image/Kata mount propagation and capacity failure behavior. Keep the feature
disabled until those checks pass; the live fleet must pass the local-image rollout gates.
