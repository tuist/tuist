# Shadow runner assignment

The opt-in shadow scheduler evaluates a central policy against queued demand
and healthy, already-warm Linux and macOS runners. It records proposals without
changing dispatch, claims, replicas, reservations, Pods or host placement.

## What version 1 evaluates

Every 30 seconds, the elected runners-controller reads a server snapshot and
fresh Kubernetes RunnerPools, runner Pods and Nodes. It excludes busy,
unbooted, deleting, draining and stale-template Pods, unhealthy or incompatible
hosts, and shapes whose actual runner requests no longer match the pool.
macOS uses the existing guest-heartbeat test: a stale/claimed beat excludes a
VM, while an absent beat retains the existing compatibility behavior.

The pure policy selects feasible demand across pools using each account's
dominant CPU/memory usage as a fraction of its platform limits. Each proposed
assignment charges that virtual budget before selecting the next demand.
Accounts with larger configured limits therefore receive proportionally more
capacity under this experiment. Within equal shares, oldest demand wins; after
two minutes of waiting, age takes precedence over share. An unplaceable demand
does not prevent a compatible demand from using a different warm runner.

Pool identity preserves shape/Xcode boundaries. Existing claims exclude both
their original demand and the job GitHub actually assigned. Cache-master Node
labels prefer a resident host among matching macOS runners; they never cause
the planner to wait for a warm cache. They do not establish fork trust or prove
that a cache will be usable by the job.

This version does **not** propose new VMs, move Pods, drain hosts, predict job
durations, reserve future capacity, or replace provider/billing/credential
checks. Its scope is account-aware assignment of existing warm capacity. It
cannot answer how a different provisioning policy would change queue latency.

## Enable and stop

1. Deploy a server containing `GET /api/internal/runners/shadow_snapshot` and a
   controller image supporting `--shadow-snapshot-url` and `--shadow-interval`.
2. The canary overlay sets `runnersController.shadowScheduler.enabled: true`
   with `intervalSeconds: 30`. The chart supplies the in-cluster URL. No RBAC changes
   are needed; authentication requires the exact configured controller SA.
3. Verify snapshot collection, authentication, logging and overhead in canary
   before enabling production to evaluate proposals against real demand and
   subsequent assignments. Staging, production and the chart default remain off
   until explicitly enabled. Production observations measure policy differences;
   they do not establish queue-time improvements without trace replay or a
   separately reviewed rollout.
4. Set `enabled: false` to stop. No reservations, assignments or persisted state
   need cleanup. Disable before rolling back to a controller without the flags.

The manager adds the observer only when a snapshot URL is configured. Its
read-only collector runs independently of production reconcilers, on the leader
only, with a ten-second collection timeout. Each HTTP call has a five-second
timeout and re-reads the projected token. Intervals below ten seconds are
rejected by both the chart and binary.

## Bounds and consistency

The endpoint returns at most 1,000 queued demands within live dispatch's shared
lookback window and 10,000 active claims.
Exceeding either bound produces `complete: false` and empty lists. The policy
refuses incomplete, malformed, unsupported or older-than-15-second snapshots,
more than 1,000 warm runners, and timestamps over five seconds in the future.
There are at most 100 assignments per evaluation and 1,000 pending comparisons.
Unknown legacy demand shapes and missing account limits are explicitly deferred.

PostgreSQL reads and Kubernetes lists are not one atomic snapshot. A concurrent
claim, completion, rollout or account-limit edit can disagree with a proposal.
No decision is executed, so this uncertainty only limits interpretation. Server
claims override potentially older queue/Pod state where that evidence exists.
The input uses the same PostgreSQL lifecycle store and queue lookback as live
dispatch, rather than the asynchronous analytics replica.

## Read the output

Search the runners-controller Pod logs in Loki for:

- `shadow scheduler plan`: policy version, server capture time, evaluation time,
  queued/warm counts, assignments and deferred counts by reason. Assignments
  contain account/job identifiers, Pod UID/name, Node, pool/platform, queue age
  and potential cache residency. `no_warm_runner` means no matching remaining
  warm VM, not a claim that physical fleet capacity is exhausted.
- `shadow scheduler observation`: the **first** outstanding proposal for that
  Pod incarnation, proposal time and a later observed claim outcome.
  `same_account` means actual dispatch assigned the proposed account;
  `different_account` means it assigned another account. Both are observations,
  not success/failure scores. `unobserved` means the Pod disappeared/was replaced,
  a claim predates the proposal, or two minutes elapsed without a comparison.
- `shadow scheduler skipped snapshot`: input failure or a bound/version/freshness
  check prevented evaluation. This must not be interpreted as an empty queue.

For example, start with the controller stream selected in Grafana and filter
`|= "shadow scheduler observation" | json`. Inspect
`observation.proposal.account_id`, `observation.actual_account_id` and
`observation.outcome` in the parsed JSON. The exact stream selector depends on
the environment's release/namespace labels. Identifier fields remain log fields,
not metric labels.

Compare disagreement and observation coverage by platform/pool, account share,
queue age, and potential locality. Short jobs may be missed entirely between
samples; report that coverage gap. Agreement does not prove fairness, and a
disagreement does not prove a faster schedule. Queue-time improvement needs a
trace replay including execution/boot durations or a separately reviewed rollout.
Repeated plans are successive observations, not additional demand or executed
assignments. Restarts lose pending comparisons and do not affect running jobs.

The pure `shadow.Propose(snapshot, runners, now)` entry point can replay a fixed
input in tests; it requires no database, Kubernetes or network. Unit scenarios
cover burst sharing, cross-pool limits, aging, unavailable shapes, locality,
GitHub remapping and observation gaps. The bounded-input benchmark exercises
1,000 demands against 1,000 warm runners. Full production trace collection and
counterfactual execution simulation are follow-up work.

Logs follow the existing Grafana Cloud stack retention; see
`server/data-export.md` for account-correlated export handling. The feature adds
no database tables, object-store files, or durable assignment state.
