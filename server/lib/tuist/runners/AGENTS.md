# Runners (server)

Leaf node for `Tuist.Runners` dispatch and claims. Cache volumes have their
own node: [`cache_volumes/AGENTS.md`](cache_volumes/AGENTS.md). GitLab
acquisition: [`gitlab/AGENTS.md`](gitlab/AGENTS.md).

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
- Cache affinity is a bounded claim preference only
  (`Sites.prefer_cache_site/3`): a runner passes over a job whose account's
  runner cache is warm at another site, and none at its own, for the job's
  first 60 seconds in the queue. Never let it hold a job longer; it must not
  stall work when the warm site is busy or dark. It reads nothing while no
  available private region is at another site, so one site costs no query.
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

Linux profiles and legacy labels keep one shared runner pool. Every account uses
the existing regional Kura Service directly; vRack enrollment changes transport
at the host level. Keep profile sizing, fleet accounting and macOS site selection
independent. Old internal cohort labels remain hidden during rolling upgrades.
