# Runners (server)

Leaf node for `Tuist.Runners` dispatch and claims. Cache volumes have their
own node: [`cache_volumes/AGENTS.md`](cache_volumes/AGENTS.md). GitLab
acquisition: [`gitlab/AGENTS.md`](gitlab/AGENTS.md). Bitrise pools:
[`bitrise/AGENTS.md`](bitrise/AGENTS.md).

## Webhook account and spend boundaries

- A github.com `workflow_job` delivery resolves its account only through the
  installation row for its `installation.id` (`Dispatch.resolve_account/1`).
  Never fall back to the repository owner's login: the App is public, so an
  organization named like a Tuist handle (handles are citext) could otherwise
  queue work, bind runners and record billable windows for that account.
- A session binds one executed job and one job window. `RunnerSessions`
  ignores a later report naming another job or a second window.
- `Allowance.exhausted?/1` is checked at enqueue and again at claim, and
  `minutes_used/1` counts open sessions whose window is not recorded yet.

## Air fleet share

`AirShare` caps what Air accounts (no live paid or open source subscription, no
runner trial) hold together at `:runner_air_fleet_share_percent` (default 15,
`TUIST_RUNNER_AIR_FLEET_SHARE_PERCENT`) of each platform's Ready, schedulable
RunnerPool Nodes. `Claims.attempt/6` reads the budget before its transaction,
never the cluster under locks, and serialises Air admission per platform with
a non-blocking advisory lock. The scaling signals withhold Air jobs past the
share. An unreadable cluster leaves the share unenforced (fail open).

## Rack sites

The design and the alternatives considered are in [`sites.md`](sites.md).

- A rack job is bound to its Xcode and shape, never to a site. Dispatch queues
  it on the rack pool for its profile (`Catalog.site_pool_name/1`), which spans
  every site whose runners are on. Do not reintroduce a per-job site choice at
  dispatch or a worker that moves queued jobs between sites: a dark site is
  less capacity, which the runners-controller already sees.
- The claim decides the site: `Sites.claim_site/2` reads the claiming Pod's
  Node label `node.cluster.x-k8s.io/rack-site` (cached per Node, errors not
  cached), falling back to the pool's site (`Catalog.fleet_site/1`) for a Node
  without the label or that cannot be read. Never take the site from anything
  the guest reports.
- Everything site-specific follows that claim site: the Kura runner-cache
  endpoint in the claim response, `runner_claims.site`, and
  `runner_workflow_jobs.site` (set by every transition that binds a job to a
  Pod, including jobs GitHub places on the runner; cleared on requeue).
  `Kura.RunnerCache` attributes jobs to a site by that column, falling back to
  the pool's site for rows claimed before it existed.
- No cache-site preference at claim: a runner takes the oldest job it can,
  whichever site holds the account's runner cache. A 60-second preference was
  removed on 2026-11-23: an account with a cache at one site only (`tuist`, at
  larch) had most of its jobs wait out the full grace while idle runners at the
  other site sat by. A job claimed away from its account's cache node reaches
  it through the claim site's gateway entrance (`Kura.runner_cache_endpoint_url/3`).
- `SiteSpilloverWorker` is only the rented-fleet fallback, for an env that
  rents macOS hosts. The rack pool is down (`Sites.status/1`) only when no Node
  at any site fits or nothing claims.
- Rack pool names keep the home site (`<prefix>-ber1-<xcode>`). Rename them only
  together with turning a second site's runners on, and move queued rows in the
  same deploy.
- Tests: every routing rule above has ExUnit coverage in `sites_test.exs`,
  `claims_test.exs`, `runners_test.exs` and `kura/runner_cache_test.exs`. The
  Node-site cache is global and keyed by Node name, so tests use unique Node
  names.

## Linux cache paths

Linux profiles share one runner pool per shape and Ubuntu release
(`Catalog.pool_name/1`); accounts never get pools of their own. Every account uses
the existing regional Kura Service directly; vRack enrollment changes transport
at the host level. Keep profile sizing, fleet accounting and macOS site selection
independent. Old internal cohort labels remain hidden during rolling upgrades.

## GitHub Actions cache

`ActionsCache` is the index of the GitHub Actions cache Linux hosts and rack
Macs serve (see `infra/runner-cache/AGENTS.md`); only the Linux storage agent
and tart-kubelet call it.

- Scope comes from `Identity.github_run/1` for the Pod's executed job, cached
  per workflow run attempt. It reads the run the App's `workflow_run`
  `requested` webhook stored (`WorkflowRuns`, kept three days) and asks
  GitHub's API (two requests, about 750 ms) only for runs it lacks; both are
  GitHub's word, never the job's. A same-repository pull request saves under
  `refs/pull/<n>/merge` and reads its base branch; other runs of the repository
  save under `refs/heads/<head_branch>`; a run from a fork saves under
  `fork/<head repository ID>/<branch>`. Every job also reads the default branch.
  Never take a ref from the job.
- Matching follows GitHub per ref in read order: exact key, key prefix, then
  each restore key as a prefix, newest first. Escape LIKE wildcards.
- A save of an existing key and version in the job's ref is refused (409),
  except a reservation abandoned for an hour. Reservations are idempotent by
  the agent's entry ID, and commits by ID and node.
- A reservation is placed in the account's own storage, otherwise in a shard
  store (`actions_cache_bucket`) the node reaches (`Sites.actions_cache_location/1`):
  for a Linux node, its own site's store on the private network; for a rack Mac,
  a store whose `runner_endpoints` name its site, with the Mac's upload and
  download URLs signed for that entrance. Without one the save is refused and the job uses GitHub's
  cache. Lookups only match entries the node's site can read. An entry commits
  only once its store holds the object.
- Production serves an account only with `:runner_actions_cache`
  (`FeatureFlags.runner_actions_cache_enabled?/1`). `enabled/1` answers the
  host's health check per job, so a job without it keeps GitHub's cache; lookup
  and reserve refuse it too. Gate there, never in lookup alone: a job sent to
  the mirror and refused would miss instead of restoring from GitHub.
- `sweep/1` (hourly) deletes abandoned reservations, entries unused for seven
  days, a repository's least recently used entries beyond 200 GB, and a store's
  beyond 90% of its `actions_cache_bytes`, so the Garage quota stays a backstop.
  An entry's row goes only after its object was deleted, except in a store that
  is no longer configured.

## Linux OS versions

- A Linux profile's `os_version` selects its pool the way a macOS profile's
  Xcode does. The catalog default's pools keep the shape-only names; every
  other release appends its tag (`-ubuntu-22-04`), and
  `infra/helm/tuist/templates/runner-pool.yaml` applies the same rule. Never
  rename the default's pools: queued rows name them.
- Existing profiles are pinned to the release they ran (`ubuntu-24.04`);
  only new profiles take the default. Moving the default therefore moves no
  one, and the pinned release's pools gain a suffix in the same deploy, so
  rewrite unclaimed queued `fleet_name`s with it, as the Xcode retirements do.
- Helm tells the server only the releases it rendered pools for
  (`TUIST_RUNNER_LINUX_OS_VERSIONS`). Retiring a release needs a migration
  moving its profiles and unclaimed queued jobs first; see
  `infra/linux-runner-image/image-rollout.md`.
- OS does not change billing: metering is per shape (`billing_multiplier/3`).

## API jobs

`Tuist.Runners.APIJobs` serves forges and orchestrators without a runner
protocol (`POST /api/accounts/:handle/runners/jobs`, `provider = "api"`). Tuist
is the coordinator: the job is queued in the shared lifecycle, the claiming VM
runs it with `tuist-job-runner` (`infra/linux-runner-image/job-runner/`) and
reports through the job-scoped report endpoints, and outcomes reach the caller
as `runner_job.started` / `runner_job.completed` webhooks.

- Jobs are untrusted: no cache signing grant, no shared cache volumes.
- The encrypted payload (script, env, secrets, clone token) is cleared on
  completion, cancellation, lost Pod, and by `ExpireAPIJobWorker` a day after
  creation. Never log or return it.
- `idempotency_key` is unique per account; a reused key returns the existing
  job. Cancellation of a running job travels back on the executor's log-post
  response (`cancel_requested`), so the executor polls with empty batches.
- The VM reports its own outcome; the orphan sweep fails a job only once its
  Pod is gone.
