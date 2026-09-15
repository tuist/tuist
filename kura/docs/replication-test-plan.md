# Kura replication redesign — test plan

Re-run this plan after every implementation step, bug fix, or design
adjustment. Each item names the command that runs it and the observable that
decides pass/fail, so a run is a checklist rather than a judgement call.
Results of a run are appended to `replication-implementation.md` under the
task they verify, never edited into this file.

Three rings, cheapest first. A change must clear ring A before ring B is
worth running, and ring B before ring C.

---

## Ring A — unit and endpoint tests (seconds to minutes, laptop)

```bash
cd kura && mise exec -- cargo test sync::            # feed, cursor, watermark, role rules
cd kura && mise exec -- cargo test backfill::        # backward pass unchanged + buffer
cd kura && mise exec -- cargo test http::tests::internal_sync   # endpoint contract
cd kura && mise exec -- cargo test replication::     # membership loop, peer body streaming
cd kura && mise run clippy && mise run format -- --check
```

CI parity before a push: `cd kura && mise run test-unit` (Bazel).

What ring A must prove, one test per line (test names in the code carry
the same `A-n` tag):

| # | Rule | Observable |
| --- | --- | --- |
| A-1 | Feed row per client write, region apply, namespace delete | row count == commits; descriptor equals the index descriptor |
| A-2 | Echo rule | a change applied from the sibling writes no row; a no-op apply writes no row |
| A-3 | Seq monotonic across reopen; incarnation stable across reopen, new on an empty dir | values compared across `Store::open` |
| A-4 | Trim below the consumer cursor; floor meta advances; range delete | rows below cursor gone, floor == cursor |
| A-5 | Cap drops oldest, never blocks a write | write succeeds at cap; oldest row gone; dropped counter +1 |
| A-6 | Activation by `{head}`; off after the stale window | no rows before the first `{head}`; rows after; rows dropped after the window |
| A-7 | Endpoint four cases | `{entries,next,head}` / `{head}` / `410 floor` / `410 incarnation` |
| A-8 | Long-poll wakes on commit, returns on `wait` | latency < wait when a commit lands; == wait when idle |
| A-9 | Cursor advances only when the whole page resolved | a failing body leaves the cursor; retry re-applies idempotently |
| A-10 | `410` → snapshot, backward pass, forward | records committed before and after the snapshot both arrive |
| A-11 | Region watermark per origin, advanced only by own-origin records; max merge | two origins interleaved; one watermark moves |
| A-12 | Watermark advances travel as feed rows in commit order | sibling adopts the watermark only after the rows that earned it |
| A-13 | Ascending read: origin filter, full-key cursor, `now`, settle guard | page contents and cursor ties across a millisecond |
| A-14 | Capacity rule on ascending reads: declined entries count as observed | watermark advances past a declined entry; nothing fetched |
| A-15 | Pass-start buffer `horizon.max(watermark - buffer)` | `compute_window` result |
| A-16 | Local role derivation: lowest URL per region, Ready and non-draining only, overlap over gaps | role table for synthetic views |
| A-17 | Server `peer_roles` overrides local derivation | node role follows the published entry |
| A-18 | Every present peer is pulled from | siblings by region, gateways by role, whatever a peer advertises; a peer answering 404 to the feed settles as `unsupported` and counts as a capability gap, not degraded |
| A-19 | Drain gate waits for the sibling cursor, bounded; region of one exits at once | shutdown duration under both shapes |
| A-20 | Readiness: settled bootstrap + cursor within one page | `/ready` transitions |
| A-21 | INV-6 serve gate on young entries with an absent blob | miss served; old entries untouched |
| A-22 | Limiter bypass for same-region peers | limiter untouched on the sibling link |
| A-23 | `origin_region` additive on the wire | old-format frames decode; new frames carry it |
| A-24 | Watermark seed from `backfill/wm/` rows | first read starts at the seeded value |
| A-25 | The membership view is advertised (§11.2) | `/_internal/status` carries `peers`, the view this node holds, for a pre-pull peer's own per-pair rule |
| A-27 | Bootstrap failure budget survives a link respawn (§3.6) | a peer that leaves and re-enters the view continues its failure count; readiness settles after the budget however often the link reopens |
| A-26 | Peer bodies limits are configuration (§11.1) | the aggregate follows the membership view (`max(8, peers × slots)`) unless pinned; the configured per-peer slot count admits exactly that many; the (N+1)th request across distinct identities is refused as `rejected_node_busy` |
| A-28a | Feed stamps and the frontier (§4.1, D-24) | stamps are non-decreasing in seq; `frontier_ms` is the lowest in-flight stamp while one is in flight and `now` once every ticket resolves, including an aborted one |
| A-28b | Server-generated versions come from the feed ticket (D-24) | a write's `version_ms` equals its feed row's `arrived_at_ms`; concurrent writes are versioned in seq order; a replicated apply and a replicated tombstone keep the version they arrived with, a local delete is stamped |
| A-28c | The ascending listing stops at the serving bound (D-24) | with a replica link's frontier held below an entry, the entry is withheld and the page's cursor still reaches it once the frontier passes — no skip |
| A-28d | No feed, no links: the bound is the settle window (D-6) | a region of one lists nothing younger than `now − KURA_SYNC_REGION_SETTLE_MS`, unchanged |
| A-28e | Three nodes, two regions (D-24) | the gateway's replica link reports a frontier past what it delivered; an entry held at that frontier is absent from the gateway's ascending listing and arrives at the remote once the link refreshes |
| A-29a | An exhausted forward page reports the head (D-26) | with two aborted allocations at the sibling's head, the page above the cursor is empty and reports `next == head` with no lag; a page cut short by the limit still reports its last row |
| A-29b | A gap at the sibling's feed head does not freeze the link frontier (D-26) | after the gap opens on a quiet sibling, the puller's frontier passes its own later write, the write becomes listable, and the link reports no lag |
| A-29c | A link that gave up its bootstrap stops bounding the listing (D-25) | while within the budget the bound is 0 and the lag gauge saturates at 86400; once the budget is spent the link is settled and abandoned, the bound follows the settle window again, and a later reported frontier bounds the listing once more |
| A-30 | A forward response captures one feed state | `head` and `frontier_ms` are read under the allocation lock, so the frontier cannot cover a sequence above the response head |
| A-31 | Capacity decisions on arrival-ordered pages are per entry | an old entry below the next evictee is declined, then a newer entry in the same page is fetched and applied; the pass does not latch capacity completion |
| A-32 | Feed reactivation invalidates old cursors | a consumer caught up at the old head receives `410 floor` after deactivate and reactivate; writes made while disabled arrive through the required bootstrap |
| A-34 | The persisted feed owns the drain obligation | an already-enabled feed remains active for a sibling until the stale window expires and shutdown gates on the feed itself |
| A-35 | Self-hosted peer views do not expose managed pod roles | a self-hosted credential receives an empty `peer_roles` list even when the account has stored internal pod roles; the managed credential still receives them |
| A-36 | Endpoint permission skew holds evacuation | a forbidden core Endpoints read returns “not served” without an error, so the controller retains the pod until its chart permissions catch up |
| A-37 | Slow regional role reads do not serialize a tick | two blocked peer-role observations both start before either is released, under the reconciler's bounded worker group |

## Ring B — docker compose end-to-end (minutes, laptop)

```bash
cd kura && docker compose build && mise exec -- shellspec spec/e2e/sync_spec.sh
cd kura && mise exec -- shellspec spec/e2e/discovery_spec.sh spec/e2e/backfill_spec.sh spec/e2e/rollout_spec.sh
```

`sync_spec.sh` topologies (compose overrides under `test/e2e/`):

| # | Topology | Scenario | Observable |
| --- | --- | --- | --- |
| B-1 | 2 replicas, 1 region | write on A → read on B | converges < 2 s; `kura_sync_forward_cursor_lag_entries` ≈ 0 |
| B-2 | same | stop B, write 10k on A, start B | B converges via forward feed; no `410` |
| B-3 | same, cap = 100 | stop B, write 1k on A, start B | `410`, backward pass, forward; all records present |
| B-4 | same | SIGUSR1 on A with B lagging | A exits after B's cursor reaches head; `drain_timeout_total` == 0 |
| B-5 | 2 regions × 2 replicas | write in region 1 → read in region 2 non-gateway | arrives; only gateways carry cross-region connections |
| B-6 | same | restart region-2 gateway | role moves to the sibling; watermark preserved; no full re-walk |
| B-7 | same | namespace delete in region 1 | tombstone applied everywhere |
| B-8 | 2 regions, one on the previous release with push | mixed versions (`test/e2e/kura_compatibility_rollout.sh`) | the previous region pushes into the current one and pulls from it; all records converge |
| B-9 | region of one + 2-replica region | co-located instance | region of one pulls from the gateway; no feed on the region of one |
| B-10 | serverless 3 nodes, 2 regions, no server | roles derived locally | exactly one gateway per region in `/status/cluster` |
| B-11 | 2 nodes, 1 region, one-way membership (d2 lists d1, d1 lists nobody) | §11.2 under the runner-region shape | a write on d1 reaches d2 by pull; d1 opens no link and nothing pushes to it, so d2's write reaches it only through the rest of a mesh it can see |

## Ring C — k01 clusters (tens of minutes per setup)

Clusters are created with `~/.config/tuist/k01/mvm create k0N` and the
server-backed setups deployed with `CLUSTER=k0N mise x -- bash
~/.config/tuist/k01/deploy.sh` (run from the repo root so `helm` resolves).
The lab scripts live under `~/.config/tuist/k01/replication/` (the harness
repo):

| Script | Purpose |
| --- | --- |
| `serverless.sh apply k0N <tag-us> [<tag-eu>] [pull]` | the serverless 2 × 2 mesh (`kura-mesh` namespace), image tags from the host registry; `wipe` removes it |
| `regions.sh add k0N eu ap` | add two-replica regions (`flip` is a no-op on a pull-only image) |
| `mint-jwt.sh k0N` | an HS512 token the deployed nodes accept for `tuist/kura` writes |
| `sync-bench.sh` | the burst + convergence + cAdvisor/du deltas table (`KURA_BENCH_TOKEN` for authenticated nodes) |
| `rollout-check.sh` | C-5/C-6: roll an instance to a new image while writing, watch the gateway role |
| `rebuild-check.sh` | C-8: recreate a node on an empty volume, watch the `410 incarnation` re-bootstrap |
| `stall-check.sh` | SIGSTOP a node, burst elsewhere, compare feed lag growth and catch-up time |
| `remote-selfhosted.sh` | C-3: a self-hosted node in another cluster enrolling with the server (see the implementation log for why the lab cannot complete enrollment) |

| # | Setup | What it exercises | Pass criterion |
| --- | --- | --- | --- |
| C-1 | Self-hosted, no server: 2 nodes × 2 regions (`KURA_PEERS` + `KURA_REGION`) | serverless role derivation, feed, region sync | writes on any node reach every node; one gateway per region |
| C-2 | Self-hosted with a self-hosted server: 1 KuraInstance (2 replicas) + 1 self-hosted node, all one cluster | enrolled peer roles from the server | the self-hosted node is pulled by the region's gateway and pulls from it; convergence continues |
| C-3 | Self-hosted node pointing at a hosted-style server on another cluster | server-published roles across clusters | roles identical on both sides; region sync over the hairpin |
| C-4 | Self-hosted server + 2 more regions × 2 replicas (3 KuraInstances, 3 regions) | gateway clique, origin-filtered forward reads, buffer | every write reaches all 6 nodes; cross-region connections == gateways only |
| C-5 | 1 managed region (controller-managed KuraInstance, 2 replicas) | controller `peerRoles`, peer Service pinned to the gateway, drain gate on a rollout | rollout loses no recent write; `drain_timeout_total` == 0 |
| C-6 | 2 managed regions | primary/gateway complement in both regions, role moves across a deploy | `kura_gateway_role_changes_total` step per deploy, no continuous climb |
| C-7 | Mixed versions: previous-release image (push-capable) on a self-hosted node, current image in the regions | push removal compatibility | flag on: both directions converge with no push; flag off or a pre-pull release: the old node's pushes land on the receivers, the new nodes stay Ready with `capability=1` (`unsupported` link) and the old node sees their writes only on its own backward passes |
| C-8 | Volume rebuild (delete a data PVC's pod on an empty volume) | new incarnation, `410 incarnation`, bootstrap from the sibling | `fell_behind_total{reason="incarnation"}` == 1; readiness after bootstrap |

Each ring-C run records, per node, before/after: RSS and anon memory
(`kura_process_resident_bytes`), data-dir size, CPU seconds
(`process_cpu_seconds_total`), bytes on the peer plane
(`kura_replication_bytes_total`, `container_network_*` from cAdvisor), and the
convergence time of a fixed write burst (`scripts/sync-bench.sh`). The same
burst runs against a `main`-built image on the same cluster for the
comparison in `replication-implementation.md` §3.

## Ring D — sustained REAPI load on k01 (tens of minutes)

Ring C answers "does a burst converge". Ring D answers "does the mesh stay
converged, and at what cost, while a client keeps writing and reading through
the REAPI surface for ten minutes". It is the only ring that drives Kura the way
Bazel does — gRPC through the public ingress, ActionCache plus ByteStream,
outputs from a few KiB to a few MiB — rather than through the key-value API.

The scripts live in the harness repo under
`~/.config/tuist/k01/replication/load/` (`README.md` there lists them):

```sh
CLUSTER=k02 mise x -- bash ~/.config/tuist/k01/deploy.sh   # server + kura-controller + region `local` (2) + `sh` (1)
~/.config/tuist/k01/replication/regions.sh add  k02 eu     # region `eu` (2 replicas, own public host)

~/.config/tuist/k01/replication/load/setup.sh k02 200      # loader image + workspace + JWT, on the host
~/.config/tuist/k01/replication/load/mesh-state.sh k02     # baseline: roles, links, phases, lag
python3 ~/.config/tuist/k01/replication/load/collect-metrics.py k02 tuist "$RUN" 15 900 &
~/.config/tuist/k01/replication/load/run-load.sh k02 600 75 4
~/.config/tuist/k01/replication/load/verify.sh  k02 <run-id> 8
python3 ~/.config/tuist/k01/replication/load/summarise.py "$RUN"
```

**Load shape.** A generated workspace of 200 `genrule`s writes pseudo-random
bytes derived from `(--define seed, index)`, in fixed size tiers from 8 KiB to
2 MiB — 68.3 MiB of incompressible payload per full build. Each iteration runs
`bazel clean`, a **write** build of a fresh seed (every action a miss, every
output a new CAS blob, uploads on), and a **read** build of the *previous*
iteration's seed with uploads off. The endpoint alternates between the two
regions per iteration, so the seed a read asks for was always written through
the *other* region: every read hit had to cross regions. Iterations are paced to
a fixed period so the rate is steady rather than a back-to-back burst.

**What is measured.** Every 15 s, per kura pod: cAdvisor CPU seconds, working
set and network rx/tx, plus from the pod's own `/metrics`
`kura_sync_forward_cursor_lag_entries`/`_seconds`,
`kura_sync_forward_index_entries`, `kura_region_watermark_age_seconds`,
`kura_region_sync_last_success_age_seconds`, `kura_region_sync_bytes_fetched`,
`kura_backfill_bodies_peer_requests_total` by outcome, `kura_gateway_role` and
its change counter, `kura_peer_connection_failures_total`, the REAPI artifact
read/write byte counters, memory pressure and the capacity-shed counters, and
process RSS/anon (`pods.csv`). Per Bazel iteration: elapsed time, actions,
remote cache hits and local executions, and Bazel's own network sampler
(`iterations.csv`). After the run, every seed is read back from the region that
did not write it (`verify.csv`), and the data-dir size of every pod is compared
against the pre-run figure.

**Pass criteria.**

| # | Criterion |
| --- | --- |
| D-1 | Every link stays `forward` and `settled` for the whole run. |
| D-2 | `kura_region_watermark_age_seconds` is a sawtooth that resets within ~10 s of the other region's write finishing — it never ratchets upward across iterations. |
| D-3 | `kura_gateway_role_changes_total` does not move, and `kura_peer_connection_failures_total` stays 0, under steady load. |
| D-4 | Every pod's data dir grows by approximately the full payload written in the run, whichever region it was written through. |
| D-5 | The post-run cross-region read (`verify.sh`) hits on every action of every seed. |
| D-6 | No capacity shed, no memory-pressure state above 0, and CPU well under one core on the busiest pod. |

**Chaos sequence.** A second batch re-runs the same load and injects four events
into it (`chaos.sh k0N <outdir> <t0>` in the harness, offsets from the load
start), with `/ready` polled every 2 s and `/status/cluster` plus a `/metrics`
slice every 5 s from a pod inside the cluster (`probe-pod.sh`), and every kura
pod's log followed across the rolls (`log-tail.sh` — the controller recreates a
deleted pod under the same name with a new UID, so `kubectl logs --previous`
never holds a rolled pod's shutdown lines). `analyse-chaos.py` turns the two
logs into readiness transitions, role moves, convergence windows and a recovery
time per event.

| offset | event | what it exercises |
| --- | --- | --- |
| +2:00 | delete the pod the region's client Service points at | Service failover to the standby, the standby taking client writes, and the recreated pod bootstrapping from its sibling |
| +4:00 | `SIGSTOP` the `kura` process in a region's gateway for 60 s, then `SIGCONT` | role move to the sibling within a membership tick and catch-up from the watermark on resume, without a container restart |
| +6:00 | delete whichever pod holds that gateway role | role move plus re-bootstrap, and whether the restarting node's buffered backward pass repairs earlier cross-region skips |
| +8:00 | `SIGSTOP` the third same-region replica for 90 s, then resume | a replica falling behind the feed and catching up |

Note that with the shipped probe settings (`/up`, 20 s period, 3 failures, 5 s
timeout) a freeze longer than about 55 s is converted into a container restart
by kubelet, so the 90 s event is a restart test, not a freeze test.

| # | Criterion |
| --- | --- |
| D-7 | Every event returns the mesh to "every link `forward`/`settled`, `lag_entries` 0 on every pod" within 3 minutes of the event, and every Bazel iteration that overlaps an event still exits 0. |
| D-8 | No container restart and no pod replacement other than the ones the sequence injects. A roll caused by the controller's CPU-request band change counts as a finding to record, not a pass. |
| D-9 | `kura_sync_forward_drain_timeout_total` does not move on any pod, and `kura_sync_forward_fell_behind_total` records no reason other than the ones the events make unavoidable (`incarnation` on a pod whose volume was rebuilt). |
| D-10 | Cross-region misses present before a gateway restart are repaired by it: a seed that read short during the run reads whole in `verify.sh` after the gateway of the region that wrote it has restarted, and the two verify passes (immediately after the run, and after every pod has been stable for 3 minutes) agree. |
