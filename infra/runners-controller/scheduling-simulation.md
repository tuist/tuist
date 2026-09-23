# Comparing runner assignment policies

This reproducible offline experiment isolates the effects of polling,
fairness, cache placement, account quotas and externally supplied warm capacity.
The result supports targeted policy work before replacing live dispatch. The
initial experiment exposed missing repository-specific cache affinity in shadow
policy v1. Policy v2 fixes that omission; the results below were rerun with v2.

**These are synthetic counterfactuals, not a replay or forecast of production.**
The sampled production logs do not contain enough arrival, completion, budget,
residency and capacity history for an honest production replay. The live shadow
collector, endpoint and deployment configuration have since been removed. This
offline experiment remains available; it cannot operate or observe the fleet.

## What was compared

| Name in output | Assignment trigger | Selection and placement |
|---|---|---|
| `pull_current` | Per-runner polling every two seconds | Model of current FIFO, account admission and macOS volume affinity |
| `push_current` | Events plus assumed delivery delay | Same current per-runner selection rule; removes polling without adding global matching |
| `pull_shadow_policy` | Per-runner polling every two seconds | Retained `assignment.Propose` called with that polling runner and the shared queue/usage |
| `push_shadow_policy` | Events plus assumed delivery delay | Retained `assignment.Propose` sees all compatible ready runners |

The middle two variants distinguish policy from transport. A fairness gain
that also appears with `pull_shadow_policy` does not require push assignment.
The `push_current` adapter processes ready hosts in the same seeded priority
used for polling; it is a control experiment, not another implemented service.

Source baseline: repository revision
`ea74dd7235ab9a0aa7285a16750c5dc2221936f4`, reviewed on 2026-09-22, plus the
repository-affinity v2 change for the alternative policy.
The model ports the decision semantics from:

- [`Runners.claim_and_serve`](../../server/lib/tuist/runners.ex): 16 claim attempts,
  exclude an account after capacity rejection, Linux FIFO, macOS oldest-20 candidates.
- [`VolumeAffinities.select_candidate`](../../server/lib/tuist/runners/volume_affinities.ex):
  prefer repository or account master residency; stop bypassing the head once
  its whole-second queue age exceeds 30 seconds. A resident head remains resident
  even when overdue.
- [`Claims.attempt`](../../server/lib/tuist/runners/claims.ex): account/platform
  CPU and memory admission, shared across pools; capacity remains charged until release.
- [`dispatch-poll.sh`](../runner-image/dispatch-poll.sh): two-second idle polling.

The alternative executes the retained pure policy,
[`assignment.Propose`](internal/simulation/assignment/policy.go), now isolated
under the offline simulator:
normalized dominant usage, oldest-first override at two minutes, exact pool/shape
matching, virtual budget accounting, and repository/account cache placement. It does
not simulate executing plans every 30 seconds; that was the observer's sampling
interval, not a viable assumption for live dispatch.

## Results that inform a decision

Default central decision/delivery delay is **250 ms**, an assumption rather than
a measurement. Values below are means across **30 paired poll-phase seeds**.
Fourteen scenarios and four policies produced 1,680 runs at each delay; sensitivity
runs at 1 ms and 1,000 ms bring the total to **5,040 runs**. These are not 5,040
independent production traces: most scenarios are controlled bursts, and the two
mixed-arrival traces use one fixed arrival/runtime seed each.

| Experiment and metric | Current pull | Push, current selection | Pull, shadow policy | Push, shadow policy |
|---|---:|---:|---:|---:|
| Sparse Linux: mean queue wait | 0.72 s | 0.25 s | 0.72 s | 0.25 s |
| Account limited to two jobs: mean queue wait | 451.11 s | 452.12 s | 451.11 s | 452.12 s |
| Competing burst: account 2 mean queue wait | 193.76 s | 188.75 s | 45.76 s | 43.62 s |
| Same burst: account 1 mean queue wait | 83.38 s | 80.88 s | 108.04 s | 105.06 s |
| Busy macOS with account masters: mean arrival-to-completion | 102.91 s | 101.12 s | 110.89 s | 78.62 s |
| Repository-only cache counterexample: mean arrival-to-completion | 30.96 s | 30.25 s | 56.96 s | 30.25 s |
| Mixed Linux arrivals: mean queue wait | 65.21 s | 60.64 s | 68.17 s | 64.99 s |
| Mixed macOS arrivals: mean arrival-to-completion | 143.35 s | 135.60 s | 152.00 s | 146.52 s |

### Polling alone is not the main lever in these cases

Removing polling saves about half a second for sparse Linux demand under the
250 ms assumption. Under a two-job account quota, changing dispatch leaves a
roughly 451-second mean queue essentially unchanged. Doubling that quota from
two to four jobs reduces current-pull mean queue to **211.35 seconds** with the
same 16 ready slots. This is a mechanism test, not a recommendation to raise a
particular production account's limit.

A separate controlled pair retains claims for 30 seconds after each 30-second
job finishes. Current-pull mean queue grows from **165.90 to 330.51 seconds**;
the central shadow alternative gives **166.62 to 331.62 seconds**. Both obey
the same charged usage. This demonstrates the value of correct release accounting
without asserting that production has delayed claim releases.

### Fairness is a policy tradeoff that can retain pull dispatch

When account 1 submits 48 jobs and account 2 submits eight five seconds later,
the fair pull variant cuts account 2's mean queue from **193.76 to 45.76 seconds**.
Account 1 pays for that: its mean rises from **83.38 to 108.04 seconds**.
Fleet-wide mean queue remains **99.15 seconds** for both pull variants, and p95
increases from **196.03 to 201.03 seconds**. This is redistribution, not a
throughput improvement. Push adds a smaller latency reduction on top.

When the same slots only become available at 180 seconds, both accounts' jobs
have crossed the shadow policy's two-minute aging threshold. Shadow selection
then falls back to oldest-first and the fairness gain disappears. The aging
override is therefore a material policy choice to revisit before treating this
implementation as a fairness solution.

### Fleet-wide cache matching and the repository-affinity fix

In the busy macOS scenario, each of two accounts has four of eight hosts holding
an account cache master. With a **hypothetical 45-second cold materialization
cost**, central shadow matching raises modeled warm placements from **75% to 100%**
and reduces mean arrival-to-completion from **102.91 to 78.62 seconds** (24%).
Changing only the pull fairness rule makes mean completion worse in this case.
This is the clearest mechanism favoring global host selection, conditional on
the residency pattern and cold cost actually occurring.

Live dispatch also recognizes repository-specific cache masters. Version 1 of
the shadow collector/policy only understood account masters. In a deliberate
two-host counterexample, each host holds one of two repositories for the same
account. Live-policy selection gets both jobs warm; account-only shadow placement
chose the wrong hosts. With a hypothetical 60-second cold cost, mean completion
was **30.96 seconds for current pull versus 90.25 seconds for central shadow v1**.

Version 2 receives the same hashed cache-volume identity used by live dispatch
and recognizes account-scoped repository masters plus the account-wide fallback.
Central shadow now completes in **30.25 seconds**, with **100% warm placements**
across all 30 seeds. A regression test pins this result. At one-second central
delay it completes in **31.00 seconds**, close to current pull's **30.96 seconds**.

The pull-shadow variant stays at **56.96 seconds**: it sees only the polling
runner and keeps the oldest feasible demand rather than selecting a later warm
repository job like live dispatch. Recognizing affinity does not make the two
selection policies identical. The central policy remains greedy over currently
compatible hosts; it does not solve a global matching optimization or wait for
future residency.

Both the old cold assignment and the corrected warm assignment choose the same
account, so the observer can label either `same_account`. That remains an account
agreement measure, not cache or performance validation. These synthetic results
establish mechanisms and a regression fix, not their frequency in production.

### Mixed workloads and latency sensitivity temper the headline gains

The fixed-seed mixed Linux trace shows almost no overall improvement from
central shadow policy at 250 ms: mean completion changes by **-0.22 seconds**,
and the direction differs across poll seeds. The corresponding macOS trace
worsens **3.17 seconds** on average with v2 (v1 improved 4.56 seconds).
Additional affinity choices change later placement, completion and available
capacity; locally preferring residency is not a guarantee of a better whole trace.
In both mixed traces, push with the existing selection rule performs better
on mean latency than push with the shadow fairness policy; fairness shifts
benefits toward smaller accounts rather than minimizing fleet-wide mean time.

At a **one-second** central delay, central shadow policy worsens mean completion
by **2.93 seconds on mixed Linux** and **6.98 seconds on mixed macOS**, relative
to current pull. The busy macOS locality benefit remains about 22 seconds,
while the repository-only regression is removed. The controlled cache benefit
survives this sensitivity check; smaller transport gains do not.

With cold cost set to zero in the sparse macOS pair, central matching improves
modeled residency but yields only the polling-scale timing difference. Locality
is valuable only to the extent that it actually changes execution/materialization
cost, which these synthetic penalties cannot establish for the fleet.

## Recommendation

1. Preserve live dispatch while defining the objective: mean completion, smaller
   accounts' latency, or cache efficiency. These objectives produce different winners.
2. For fairness, evaluate the same policy in the existing centralized server
   admission path. The simulation shows that push transport is not necessary;
   choose acceptable per-account tradeoffs and revisit the aging override first.
3. Repository affinity is represented in the retained offline policy. Before central
   assignment, measure actual cold cost/residency and evaluate placement choices
   together with fairness. The mixed macOS result still regresses; the two-host
   fix alone does not justify executing this policy.
4. For the observed long production queues, verify quota settings and time spent
   charged before changing assignment. Fixed limits and missing compatible warm
   capacity remain constraints under every policy here.

The simulator provides concrete comparisons without waiting for more sparse
shadow samples. The live observer has been removed: same-account agreement was not a useful
performance score for these objectives.

## Model assumptions and limits

- Millisecond discrete events for arrivals, completions, claim release, replacement
  VM readiness, polling and central decisions. Policies receive only state available
  at that simulated time. Future runtimes are used exclusively to schedule completion.
- Slots are fixed to hosts/pools/shapes; all are healthy once ready. All policies
  get the same initial availability schedule and two-second replacement delay.
  This models a capacity slot launching a fresh VM, not VM reuse between jobs.
- Actual Kubernetes scheduling, fleet autoscaling, draining, host fragmentation,
  boot distributions and image downloads are **not simulated**. The incompatible
  capacity case supplies matching slots at 180 seconds to every policy; it cannot
  answer whether a different provisioning policy would make them available earlier.
- Claims are serialized and admitted perfectly; there are no database races,
  request costs, JIT/provider failures, webhook lag except the explicit release-lag
  treatment, or GitHub job remapping. This is a model of current decision rules,
  not execution of the Phoenix/PostgreSQL path. Both policies assign the chosen job.
- All jobs may use their modeled caches. Initial account/repository residency is
  exact. Completion adds the job's repository master on that host. No eviction,
  disk pressure, replication, repository-master seeding cost, stale host labels,
  network contention or cache trust failures are modeled.
- A seeded phase in `[0, 2s)` is assigned per slot and reused for replacement
  incarnations; it defines the pull poll offset and the push-current host order.
  Event-triggered central decisions take the specified delay and coalesce events
  arriving while a decision is pending. Neither policy knows future arrivals.
- Queue wait ends at assignment; completion includes execution plus any explicit
  cold penalty. Queue time is attributed first to account quota, then compatible
  ready capacity, then decision wait. That precedence is an accounting convention,
  not proof that quota and capacity shortages cannot overlap.
- Reported p95 values are the average of per-seed nearest-rank p95s. Synthetic
  results do not estimate production effect size, operational overhead, HA costs
  or failure recovery. The central latency values are sensitivity inputs.

## Reproduce and extend

The production observer has been retired. Deploy the chart change removing its
arguments before or together with the controller image that removes the flags;
an older controller with no shadow arguments is already inactive. Do not run a
new controller with the old chart arguments. Removing the server endpoint first
can temporarily produce snapshot errors from an old observer, without changing
live dispatch. Rollback must likewise pair a flag-emitting chart with an image
that supports those flags. There is no schema migration or assignment state to
clean up, and historical logs expire through the existing retention policy.

From `infra/runners-controller`:

```sh
go test -race ./...
go run ./cmd/simulate-scheduling -seeds 30 -push-delay-ms 250 \
  -export-scenarios /tmp/scheduling-inputs.json \
  -json /tmp/scheduling-results.json > /tmp/scheduling-results.md
go run ./cmd/simulate-scheduling -seeds 30 -push-delay-ms 1
go run ./cmd/simulate-scheduling -seeds 30 -push-delay-ms 1000
```

`-scenarios /path/to/inputs.json` accepts the exported scenario schema, allowing
controlled modifications or a future sanitized trace with explicit arrivals,
runtime assumptions, quotas, host residency and readiness. A production job's
observed duration includes effects of its original placement; do not silently
reuse it as both a warm and cold runtime in a counterfactual replay.

The simulator records every job's assignment/completion, selected slot/host,
cache eligibility, and queue-time components in JSON. Tests enforce job
conservation, both resource budgets, compatible nonoverlapping slot occupancy,
exact queue-time attribution, deterministic input-preserving runs, analytical
single-slot timing, current-policy affinity boundaries, and no duration lookahead.
The complete runner-controller race suite was run alongside these new tests.
