# ce-review run: kura backfill Release AB (2026-07-31)

- **Scope:** branch `tuist-bootstrap-v2` vs `origin/main` (be331c685e), 48 files, +18k/−2.8k
- **Mode:** autofix; plan: `docs/plans/2026-07-30-001-refactor-kura-backfill-plan.md` (plan_source: explicit)
- **Team:** correctness, testing, maintainability, project-standards, agent-native (always-on); security, performance, api-contract, reliability, adversarial (conditional). learnings-researcher skipped (no docs/solutions/ in repo).

## Findings and dispositions

| Sev | Reviewer | Finding | Disposition |
|-----|----------|---------|-------------|
| P1 | adversarial | Controller TOCTOU: pod flipping Ready mid-reconcile absent from backfill aggregation → false `complete` → move source destroyed | **Fixed**: probe all pods; unobserved replica caps aggregate at `unknown` (holds); pre-B absent-field behavior preserved; 4 new tests |
| P1 | performance | Per-stale-row WAL fsync in bodies serving, unbatched, on shared runtime | **Fixed**: batched retirement (1024/flush) per `delete_stale_action_cache_rows` precedent |
| P2 | reliability | Lifecycle mutex poisoning cascades into membership loop (kills peer discovery) | **Fixed**: poison-recovering lock helpers (claims.rs pattern) |
| P2 | adversarial | Rollback-forgiveness compounds unboundedly across repeated under-slack crash windows | **Fixed**: persisted `forgiven_seqs` ledger; rebuild when cumulative total exceeds slack |
| P2 | security | Unbounded per-cert-fingerprint metric cardinality on bodies counter | **Fixed**: 64-identity cap with `other` fold |
| P2 | testing | Memory-pressure shed path on backfill artifact/bodies endpoints untested | **Fixed**: two shed tests mirroring the replicate-endpoint pattern |
| P2 | adversarial | Writer-clock skew > 60s permanently excludes a recent entry, no signal | **Residual (advisory)**: needs a peer clock-skew signal on the wire; recorded as follow-up; the plan already documents version_ms comparability as a stated assumption |
| P2 | performance | 65,536-entry batches serialize per-tuple resolution server-side | **Residual (advisory)**: byte-bound dominates in practice; revisit with staging profiles during batch-size measurement (deferred item) |
| P2 | reliability | claims/lifecycle machine poisoning blast radius test gap | Partially addressed by poison recovery; targeted panic-injection test not added |
| P3 | correctness | `backfill_locally_covered` doc overclaims tombstone short-circuit post-purge | **Fixed**: doc corrected |
| P3 | reliability | Index task unsupervised vs membership loop | **Fixed**: `spawn_supervised("backfill_index", …)` |
| P3 | reliability | Degraded-alarm dedup resets per BEAM restart | **Fixed**: comment documents deliberate re-page-after-deploy semantics |
| P3 | maintainability ×4 | Stale `#[allow(dead_code)]` scaffolding; unreachable `run_backfill_pass` | **Fixed**: allows removed/re-scoped; wrapper deleted |
| P3 | performance | Per-peer gauges zeroed not removed (precedent-following) | **Residual (advisory)**: matches existing bootstrap-pass convention |
| P3 | project-standards | `src/backfill/` missing from kura/AGENTS.md boundaries | **Fixed** |
| P3 | project-standards | `infra` commit scope not in CLAUDE.md list | **Dismissed**: `fix(infra):` commits already conventional on main |
| P1/P2/P3 | agent-native | Operator docs: abort path, flag-flip procedure, index-build observability | **Fixed**: README "Backfill operations" section + AGENTS.md updates |

## Requirements completeness (explicit plan)

R1–R13 all addressed (Units 1–9b, 11 checked in the plan). Release C units (10, 12) intentionally open — gated on fleet convergence.

## Residual actionable work

- Peer clock-skew observability (adversarial P2): follow-up before broad tenant flips.
- Serving-side pipelining of per-tuple resolution for large batches (performance P2): revisit with batch-size profiling (plan's deferred item).
- Panic-injection tests for lifecycle lock poisoning (reliability testing gap).
- Compatibility harness (`kura/test/e2e/kura_compatibility_rollout.sh`) is a documented manual pre-release gate, not in CI — must be run before tagging each kura release.

## Verdict

Ready with fixes applied. All P0/P1 resolved; remaining items are advisory/follow-up.
