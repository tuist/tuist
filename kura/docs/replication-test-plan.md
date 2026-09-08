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
cd kura && mise exec -- cargo test replication::     # push path for non-pulling peers
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
| A-18 | Per-peer flip rule | pushes only to non-pulling peers; pulls from pulling peers by role |
| A-19 | Drain gate waits for the sibling cursor, bounded; region of one exits at once | shutdown duration under both shapes |
| A-20 | Readiness: settled bootstrap + cursor within one page | `/ready` transitions |
| A-21 | INV-6 serve gate on young entries with an absent blob | miss served; old entries untouched |
| A-22 | Limiter bypass for same-region peers | limiter untouched on the sibling link |
| A-23 | `origin_region` additive on the wire | old-format frames decode; new frames carry it |
| A-24 | Watermark seed from `backfill/wm/` rows | first read starts at the seeded value |
| A-25 | Push exception for a pulling peer that cannot dial back (§11.2) | a pulling peer whose advertised view omits us stays a push target, leaves once it names us, and never earns D-20's stickiness before that; `/_internal/status` carries the view |
| A-27 | Bootstrap failure budget survives a link respawn (§3.6) | a peer that leaves and re-enters the view continues its failure count; readiness settles after the budget however often the link reopens |
| A-26 | Peer bodies limits are configuration (§11.1) | the configured per-peer slot count admits exactly that many; the (N+1)th request across distinct identities is refused as `rejected_node_busy` |

## Ring B — docker compose end-to-end (minutes, laptop)

```bash
cd kura && docker compose build && mise exec -- shellspec spec/e2e/sync_spec.sh
cd kura && mise exec -- shellspec spec/e2e/discovery_spec.sh spec/e2e/backfill_spec.sh spec/e2e/rollout_spec.sh
```

`sync_spec.sh` topologies (compose overrides under `test/e2e/`):

| # | Topology | Scenario | Observable |
| --- | --- | --- | --- |
| B-1 | 2 replicas, 1 region, pull on | write on A → read on B | converges < 2 s; `kura_sync_forward_cursor_lag_entries` ≈ 0; outbox empty |
| B-2 | same | stop B, write 10k on A, start B | B converges via forward feed; no `410` |
| B-3 | same, cap = 100 | stop B, write 1k on A, start B | `410`, backward pass, forward; all records present |
| B-4 | same | SIGUSR1 on A with B lagging | A exits after B's cursor reaches head; `drain_timeout_total` == 0 |
| B-5 | 2 regions × 2 replicas, pull on | write in region 1 → read in region 2 non-gateway | arrives; only gateways carry cross-region connections |
| B-6 | same | restart region-2 gateway | role moves to the sibling; watermark preserved; no full re-walk |
| B-7 | same | namespace delete in region 1 | tombstone applied everywhere |
| B-8 | 2 regions, pull on in region 1 only | mixed mesh | region 2 still pushes; region 1 pulls from region 1 peers; all records converge |
| B-9 | region of one + 2-replica region | co-located instance | region of one pulls from the gateway; no feed on the region of one |
| B-10 | serverless 3 nodes, 2 regions, no server | roles derived locally | exactly one gateway per region in `/status/cluster` |
| B-11 | 2 nodes, 1 region, pull on, one-way membership (d2 lists d1, d1 lists nobody) | §11.2's push exception under the runner-region shape | a write on d1 reaches d2 by pull; a write on d2 reaches d1 by push, with d2's outbox back to zero |

## Ring C — k01 clusters (tens of minutes per setup)

Clusters are created with `~/.config/tuist/k01/mvm create k0N` and the
server-backed setups deployed with `CLUSTER=k0N mise x -- bash
~/.config/tuist/k01/deploy.sh` (run from the repo root so `helm` resolves).
The lab scripts live under `~/.config/tuist/k01/replication/` (the harness
repo):

| Script | Purpose |
| --- | --- |
| `serverless.sh apply k0N <tag-us> [<tag-eu>] [pull]` | the serverless 2 × 2 mesh (`kura-mesh` namespace), image tags from the host registry; `wipe` removes it |
| `regions.sh flip k0N true\|false` / `add k0N eu ap` | flip `KURA_REPLICATION_PULL` on the deployed instances; add two-replica regions |
| `mint-jwt.sh k0N` | an HS512 token the deployed nodes accept for `tuist/kura` writes |
| `sync-bench.sh` | the burst + convergence + cAdvisor/du deltas table (`KURA_BENCH_TOKEN` for authenticated nodes) |
| `rollout-check.sh` | C-5/C-6: roll an instance to a new image while writing, watch the gateway role |
| `rebuild-check.sh` | C-8: recreate a node on an empty volume, watch the `410 incarnation` re-bootstrap |
| `stall-check.sh` | SIGSTOP a node, burst elsewhere, compare outbox growth and catch-up time |
| `remote-selfhosted.sh` | C-3: a self-hosted node in another cluster enrolling with the server (see the implementation log for why the lab cannot complete enrollment) |

| # | Setup | What it exercises | Pass criterion |
| --- | --- | --- | --- |
| C-1 | Self-hosted, no server: 2 nodes × 2 regions (`KURA_PEERS` + `KURA_REGION`) | serverless role derivation, feed, region sync | writes on any node reach every node; one gateway per region; outbox stays empty |
| C-2 | Self-hosted with a self-hosted server: 1 KuraInstance (2 replicas) + 1 self-hosted node, all one cluster | enrolled peer roles from the server, flip via the account flag | flag flip observed in `/_internal/status`; pushes stop; convergence continues |
| C-3 | Self-hosted node pointing at a hosted-style server on another cluster | server-published roles across clusters | roles identical on both sides; region sync over the hairpin |
| C-4 | Self-hosted server + 2 more regions × 2 replicas (3 KuraInstances, 3 regions) | gateway clique, origin-filtered forward reads, buffer | every write reaches all 6 nodes; cross-region connections == gateways only |
| C-5 | 1 managed region (controller-managed KuraInstance, 2 replicas) | controller `peerRoles`, peer Service pinned to the gateway, drain gate on a rollout | rollout loses no recent write; `drain_timeout_total` == 0 |
| C-6 | 2 managed regions | primary/gateway complement in both regions, role moves across a deploy | `kura_gateway_role_changes_total` step per deploy, no continuous climb |
| C-7 | Mixed versions: main image in one region, branch image in the other | ship/flip compatibility | both directions converge; old region keeps push; new region pulls |
| C-8 | Volume rebuild (delete a data PVC's pod on an empty volume) | new incarnation, `410 incarnation`, bootstrap from the sibling | `fell_behind_total{reason="incarnation"}` == 1; readiness after bootstrap |

Each ring-C run records, per node, before/after: RSS and anon memory
(`kura_process_resident_bytes`), data-dir size, CPU seconds
(`process_cpu_seconds_total`), bytes on the peer plane
(`kura_replication_bytes_total`, `container_network_*` from cAdvisor), and the
convergence time of a fixed write burst (`scripts/sync-bench.sh`). The same
burst runs against a `main`-built image on the same cluster for the
comparison in `replication-implementation.md` §3.
