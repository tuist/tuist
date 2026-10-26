# Rack sites: bind jobs to Xcode and shape, pick the site at claim

Status: agreed with Marek on 2026-10-26 and implemented. The rules that code
must keep are in [`AGENTS.md`](AGENTS.md).

## Problem

A rack runner job is bound to its site when it is queued. Dispatch
(`Tuist.Runners.Dispatch.profile_pool_name/2`) picks a site pool,
`<prefix>-<site>-<xcode>[-<shape>]`, writes it to
`runner_workflow_jobs.fleet_name`, and only runners of that RunnerPool claim
it (`Jobs.pick_queued_top_k/5` filters on `fleet_name`). Each site's pools
select only that site's minis (`tuist.rackSiteFleetName`, #14752). A site
going dark leaves its queued jobs behind, so something has to notice the
outage (`Tuist.Runners.Sites.status/1`: no fitting Node, or a 10 to 30 minute
stall) and move them (`SiteSpilloverWorker`, `WorkflowJobs.move_queued/3`).

With a second rack (larch), that turns into a placement scheduler in the
server: pick a site per job, detect a down site, move its queue. The cluster
already knows which Mac minis are Ready and has an autoscaler that sizes
pools to the capacity it can see. A dark rack should just be less capacity.

## What is already decided at claim, not at dispatch

Reading the code, the site-specific parts of a job are already resolved when a
runner Pod claims it (`Tuist.Runners.dispatch_for_sa/3`), from the claiming
Pod, not from the job:

- **Kura runner-cache endpoint.** `RunnersController.dispatch_response/7`
  calls `Kura.runner_cache_endpoint_url(account, platform,
  Catalog.fleet_site(pod_fleet))` in the claim response. The "dispatch" the
  Kura drain rule talks about ("dispatch handed its endpoint to running jobs")
  is this claim response.
- **Cache volumes.** `VolumeAffinities.select_candidate/3` scores queued jobs
  against the claiming Node (`node_name` from the Pod), masters live in object
  storage, and `VolumePrefetch` is per Node. Nothing is per site.
- **Egress, image mirrors, the VM firewall's Kura gateway
  (`vmCacheGatewayCIDRs`).** Host configuration, so they follow the Node.

So the only thing tying a job to a site is the RunnerPool it is queued on.

## Design

### 1. One rack pool per Xcode and shape, spanning sites

Every site whose runners are enabled joins the same capacity domain:

- Its Mac minis carry the rack fleet's `tuist.dev/fleet` (today only
  `rackFleet.site`'s do). A site with runners disabled keeps its own Node
  fleet, `<rack fleet>-<site>`, as #14752 renders it, so its minis get no
  runners. Turning a site's runners on is moving its hosts onto the rack fleet.
- The chart renders the rack catalog once (one placement), not once per site.
  Its pools select the rack fleet, so they span every enabled site.
- The site of a Node is its `node.cluster.x-k8s.io/rack-site` label (set on the
  Machine by `RackHostReconciler.machineLabels`, synced to the Node by Cluster
  API).

A job is queued exactly as today: dispatch resolves the profile to the rack
pool for its Xcode and shape (`Catalog.site_pool_name/1`). Nothing in the
queue names a site. `TUIST_RUNNERS_SITE_POOLS` keeps its `<pool>=<site>:<platform>`
format, where the site is the rack's home site; the server uses it only to
know which pools are rack pools and as the fallback site for a Node with no
site label (a host lent to staging or canary registers in their cluster).

Why one pool rather than per-site pools sharing one queue: the
runners-controller sizes a pool from its queue (`desired_replicas`) and
apportions guest slots per `(OS, fleetSelector)`. With per-site pools reading
the same queue, every site would scale for the whole queue, and the server
would have to split demand between sites without seeing which Pods the
scheduler could not place. With one pool, the autoscaler counts the queue
once, the allocator's budget is the sum of Ready, schedulable minis at every
site (a NotReady or `tuist.dev/power-budget`-tainted Node already drops out,
`nodeFilterReason`), the per-shape placement caps are per Node, and
kube-scheduler puts Pods wherever there is room. A dark rack is a smaller
budget. No job moves.

The constraint this adds: every site racking a pool runs the same guest for
it (`rackFleet.runners.guestShapes`, `stackedImages`, the racked shapes),
because a RunnerPool has one pod size. `rackFleet.sites.<site>.runners` may set
only `enabled`, or repeat the rack's own values.

### 2. The claim identifies its site from the Node

`dispatch_for_sa/3` already reads the polling Pod (`check_not_stale/3`
returns its `node_name`). The claim reads that Node's site label (cached per
Node), falling back to the pool's site. The site then drives:

- the Kura endpoint in the claim response
  (`runner_cache_endpoint_url(account, platform, node_site)`);
- a new `runner_workflow_jobs.site` column, written in the same transaction
  as `queued -> claimed` (`WorkflowJobs.transition_claimed`) and cleared when
  the job is requeued;
- the claim-time preference below.

No runner image change: `dispatch-poll.sh` sends nothing new. The server
trusts the Node it reads over anything the guest could report.

### 3. Cache affinity is a claim preference with a bound

A runner at site S that picks a queued job whose account has an active
private runner-cache node at another site and none at S skips that job until
it has queued for 60 seconds (one more filter in `pick_affine_candidate`, over
the top-K candidates it already fetches, with one query for their accounts'
cache sites). So:

- while the warm site has an idle runner, it gets the job first;
- while it is busy or dark, the job runs elsewhere after at most 60 seconds;
- an account with no rack runner cache, or one at S, is never deferred.

With one site this never triggers. Volume affinity stays per Node as it is
(`select_candidate/3`, its 30 second tolerance). Placement can later prefer a
Node at the account's cache site in `preferred_nodes` the same way it prefers
Nodes holding a job's volumes; that is not needed for correctness.

### 4. Kura region rules follow the recorded site

`Kura.RunnerCache` reads the job's site instead of mapping its pool to a site:

- Admission to a site's region (`site_job_runs/4`): the account's jobs
  claimed at that site in the last seven days.
- Drain (`region_pool_condition/1`, `drained_nodes/2`): a draining node waits
  for the account's in-flight jobs claimed at the region's site before
  `drain_started_at`, because those are the jobs the claim handed its
  endpoint to.
- The region without a site keeps taking jobs claimed on non-rack pools.

A row claimed before the column existed has no site and counts at its pool's
site, which is ber1 for every rack row in production.

### 5. Down sites and the rented fleet

Site-to-site spillover goes away (it never landed on `main`; #14757 is cut
down to the larch Kura region). `Sites.status/1` and `SiteSpilloverWorker`
stay as the rented-fleet fallback for an env that rents macOS hosts: with one
pool spanning sites, the pool is down only when no Node at any site fits or
the queue stalls everywhere. No managed env rents macOS hosts today
(`runnersFleet.hostCount: 0` in staging, canary and production), so there the
worker is a no-op, as it is now.

### 6. Controller changes

- Idle Pods on a Node that `nodeFilterReason` filters out (NotReady, not just
  cordoned or over its power budget) are retired like a cordoned Node's
  (`reapIdlePodsOnCordonedNodes`). Without it, a dark rack's warm Pods count as
  capacity until the taint-based eviction about five minutes later, and the
  autoscaler creates no replacements at the live rack in that window. Pods
  running jobs are left alone, as today.
- A RunnerPool can pin a site (`spec.site` -> nodeSelector
  `node.cluster.x-k8s.io/rack-site`), for the `ber1` smoke pool, which tests one
  rack and must not land on another once larch joins the rack fleet.

## ber1 alone

Until a second site enables runners, nothing changes for ber1: the same pools
with the same names select the same fleet, every claim resolves to ber1 (Node
label or fallback), the Kura endpoint is the same, no job is ever deferred,
and the Kura rules see the same jobs. The new code paths are the Node read
(cached) and the `site` column write.

## Alternatives considered

- **Keep dispatch-time binding, add site-to-site spillover** (#14757 as
  drafted). Dispatch picks a site per job (queue depth, then cache affinity),
  and a worker moves a down site's queued jobs. It works, but it is a second
  scheduler: a job queued at a site that just went dark waits out the
  detection window (no Node fits, or 10 to 30 minutes of stall), queue depth
  is a guess at capacity the controller already knows, and a busy site and a
  broken site look alike until the stall bound.
- **Per-site pools claiming from one shared queue.** Keeps #14752's per-site
  pools and per-site guest sizes, but each site's pool sees the whole queue,
  so both scale for it, and splitting demand in the server cannot see which
  Pods the scheduler refused at which site.
- **The guest reports its site** (`dispatch-poll.sh` posts it). Needs an image
  release, and it is input from the VM. The Node label is authoritative and
  already one read away.

## Decisions

1. **Pool names.** The rack pools keep `<prefix>-ber1-<xcode>` in this change.
   Renaming them to a site-free name drains every rack pool and strands queued
   rows on the old names unless they move in the same deploy, so the rename, if
   any, happens together with turning larch's runners on.
2. **Cache-site grace.** 60 seconds, to be tuned later with queue-time and
   hit-rate data.
3. **Guest shapes at a second site.** Not assumed. The chart refuses to turn a
   second site's runners on while its `rackFleet.sites.<site>.runners` sets
   `guestShapes`, `shapes`, `stackedImages`, `autoscaling`, `rollout` or
   `xcodeOverrides` differently from `rackFleet.runners`, names its own
   `nodeFleet`, or the rack's runners are off. Host sizing (`rackFleet.machine`)
   is fleet-wide already. ber1's minis are M5 Pro (Z1UD001N2: 18-core CPU,
   64 GB, 2 TB).
4. **Unreachable Nodes.** The controller retires idle Pods on a Node NotReady
   for two minutes, long enough to ride out a kubelet restart.
