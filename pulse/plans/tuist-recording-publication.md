# Tuist recording publication checkpoint

Pulse remains a headless storage/querying/alerting backend. This increment adds native recording publication; it does not enable Grafana imports, establish production source residency, or authorize a cutover.

## Implemented

- Explicit `promql_recording` rules through existing audited HTTP/MCP management, preview and evaluation. Closed configuration, disabled by default, tenant-local instant-vector inputs and metric outputs.
- Immutable result objects referenced by the rule-head CAS **before** metrics can become visible. Losing/stale evaluator candidates cannot publish. Completed timestamps and revision/state fences remain authoritative.
- A durable FIFO of at most 64 references survives edits, disable/delete, restoration and re-creation. Ordinary ticks stop at 63, reserving one slot for configuration retirement.
- Publication reconstructs the same committed records and uses a deterministic full-result-derived idempotency key with native S3 append. Segment PUT and manifest CAS precede queue acknowledgement. Ambiguous append/ack outcomes remain retryable, never re-evaluate an already committed result.
- Successful series disappearance, including an empty result, emits native stale markers. NaN remains an ordinary arithmetic value. Static empty label overrides remove labels; duplicate final label sets reject the whole result.
- Configuration retirement is conditionally published with the edit, strictly after the last completed timestamp. New recording ticks must be after the retirement fence, preserving past answers even when a mutation clock is behind the prior tick.
- Independent half-budgets for current output and its potential retirement guarantee a complete replacement fits the combined transition budget. No clipping, sample loss, or raised storage/query limits.
- Bounded catch-up (eight intents/two seconds of new work per visit) and automatic empty-queue gating prevent refill-neutral backlog. Missed ticks are skipped, not backfilled.
- Authoritative metrics-floor expiry retires an overtaken intent with a committed diagnostic event. Other failures stay pending, with bounded error diagnostics.
- State exposes pending count, last publication/expiry, blocked error and mutation fence. MCP state-resource fingerprints include publication progress even when the evaluation timestamp does not change.
- Authority-head reads enforce a 1 MiB download ceiling before decoding. Immutable reads enforce the committed reference size, including recording payloads, instead of discovering oversized responses after unbounded GET.

See `docs/alerting.md` for operator configuration, precise limits, synchronized-clock requirements and upgrade/rollback precautions. Publication requires S3. There is no new database, leader, WAL, dependency, externally supplied destination or remediation tool.

## Inventory evidence

All four original Kura recording queries execute through native PromQL, rule-head authority, Parquet/S3 publication and downstream PromQL reads in a controlled fixture:

1. `kura:pod_region` from `kura_node_geo_info`.
2. `kura:node_pool` from `kube_node_labels` and label replacement.
3. `kura:pool_region` from `kube_pod_info`, pod-region and node-pool producers.
4. `kura:node_region` from node-pool and pool-region producers.

The test explicitly evaluates/publishes this dependency order at one timestamp and checks output labels and values. It does **not** prove that the worker orders production groups, that every production source is resident, that all cardinalities fit, or that live numerical/client behavior matches Grafana. The original imports remain lossless and disabled; no automatic translation or datasource remapping is introduced.

## Adversarial review

Claude performed three source-only rounds with no edits, tests, builds, git mutations, network, probes or production access. The final scoped verdict is **no remaining Critical or High issues**.

Repairs driven by the review:

- Drain more than one intent and do not refill a still-pending queue in automatic mode.
- Reserve half the transition budget for stale markers before accepting a fresh set, eliminating admissible old/new churn wedges.
- Retire strictly after the last completed tick rather than at the same timestamp, where staleness-first conflict resolution would erase a historical sample.
- Surface permanent publication errors separately from successful query health.
- Follow Prometheus static empty-label removal.

Clock synchronization remains an explicit operator requirement, not a trusted cluster-clock protocol. Metadata-only edits retire outputs and may leave a cadence gap. Publication normally becomes visible on a subsequent worker visit. Recorded appends contribute to existing ingest counters. Unreferenced losing candidates are not authoritative and have no new GC implementation.

Review/validation artifacts: `/tmp/pulse-recording-next/`.

## Validation

- `mix precommit --max-cases 4`: **888 passed, 1 skipped, 33 excluded**.
- Codec Rust: **59 passed**; native source unchanged in this increment.
- Focused recording, repository and HTTP alert tests: **46 passed**.
- Strict Credo, warnings-as-errors compilation, formatting and diff checks are recorded alongside final logs.

Tests cover commit-before-visibility, lost append response/restart, concurrent different-valued candidates, stale disabled evaluators, delete/recreate drain, stale acknowledgements, ambiguous head responses, backlog/retirement reserve, retention expiry, nonfinite/stale distinctions, disappeared/empty sets, rich-label churn, clock-behind historical preservation, read-only preview, tenant isolation, corrupt/oversized payloads and heads, and state-resource progress.

No changes are committed or deployed. Existing production backends remain authoritative; merge backups and autostash are preserved.

## Still required for replacement

- Grafana condition graphs, source binding/translation, labels/templates and full no-data/error/missing-series/keep-firing lifecycle semantics.
- Recording group ordering, producer/source residency closure, same-tick freshness, metric ownership conflicts, sustained cardinality and capacity acceptance. The native limits are not a production workload promise.
- Routed/grouped/silenced durable delivery to Atlas, receiver deduplication and migration comparison.
- Trace/label postings, complete trace search/pagination/discovery/client contracts and node-wide admission.
- Separately authorized shadow delivery, live query/alert numerical comparison, node/process/object-store faults, multi-cycle maintenance, coherent restore and rollback rehearsal.

See `grafana-replacement.md`, `tuist-query-conformance.md`, `tempo-replacement.md` and `tuist-adversarial-review.md`.
