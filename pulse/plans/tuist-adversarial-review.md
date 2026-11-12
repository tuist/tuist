# Tuist backend adversarial review checkpoint

## Scope and verdict

Reviewed the uncommitted trace implementation and PR #32 reconciliation against `origin/main` (`ada01bf`). Claude performed a source-only review with four independent reviewers covering ingestion, native queries, lifecycle/paging and Tuist contracts, followed by three fix reviews. No production changes, secret retrieval, or cutover occurred. Source-only review is not independent runtime or provider conformance.

**Not ready for a Tuist cutover.** Pulse remains headless, supplying storage, querying and alerting; IRM/incident management moves to Atlas. Grafana's UI is not a Pulse deliverable. Compatibility endpoints and dashboard concurrency are acceptance requirements only for clients Tuist elects to retain, not a requirement to build a UI.

The final Claude check found no remaining critical/high findings in the reviewed paths. The original reports and final check are local artifacts under `/tmp/pulse-tuist-adversarial*.md`.

## Findings addressed

- **Index/expiry headroom:** capped trace leaf blooms at 2 KiB and complete service summaries at 512 encoded bytes; complete references cap at 4 KiB, degrading optional summaries instead of rejecting data. Owner batches cap new wire entries at 64 KiB / 256 segments / four buckets. Live byte/count reserves cover the final bounded spill and expiry. Non-affected capacity failures cannot poison another bucket; expiry omits summaries and drains older near-full layouts.
- **Compaction cleanup/progress:** only definitive preparation failures, after fresh authority proves a unique replacement unpublished and before CAS, allow immediate upload reclamation. Ambiguous outcomes retain objects. Paged failures rotate the bucket cursor best-effort; lost-response recovery remains unchanged.
- **Lookup capacity:** wide ID sets use versioned, identical-geometry canonical blooms rather than partial hashes. Unknown/legacy sets scan. Exact lookup scales metadata-byte fanout with overlapping live buckets, capped at 32 MiB, never raising explicit configured limits.
- **Floor-race delivery:** unkeyed OTLP publication expiry after semantic filtering returns retryable 503, allowing the original retry to reject expired spans individually instead of permanently losing fresh siblings. Keyed fingerprints and permanent expiry remain unchanged. No ambiguous post-PUT split is introduced.
- **Buffer splitting:** definite pre-PUT failures split with eight Runtime-scoped tasks, immediate per-caller replies and reservations held through completion; task raises/exits become retryable failures.
- **Signal isolation:** window sizing and grace validation require the signal explicitly. A trace-only compaction grace change no longer changes logs/metrics capacity.
- **Flat metadata:** omit complete ID hashes unused by flat lookups. Retain-forever catalogs remain unbounded; migration of older small-batch history conservatively scans until it expires. Prefer enforcing the chosen trace policy before first ingest into a new scope.
- **Resource/accounting robustness:** LIST-derived trace row counts are unknown and recovered from Parquet footers; only explicit limits up to 5,000 bypass candidate preflight, not assembly/no-limit sentinels. Known bytes are prechecked and segment GETs are bounded by remaining scan bytes. Metadata cache refs and data recursively detach strings from larger arenas. Retention CAS retries use bounded jitter.
- **Transport/input robustness:** reject repeated tenant/idempotency headers and dot-path tenants, map owner/buffer exits to trace 503, and deduplicate MCP projection fields before native construction.
- **Unconfigured scopes:** inspect a zero-duration flat scope once, retaining durable pending cleanup and managed-scope work rather than repeatedly decoding it for every stage.

## Validation

- `mix precommit --max-cases 4`: **851 passed, 1 skipped, 33 excluded**.
- Codec Rust: **59 passed**; strict Clippy and Rust formatting passed.
- Strict Credo: **232 files, no issues**; warnings-as-errors compilation and Elixir formatting passed.
- Helm lint and trace-retention/compaction opt-in rendering passed; `git diff --check` clean.
- Deterministic regressions cover a checksummed old index exactly 40 bytes below its former live ceiling, unrelated-bucket publication and expiry, leaf-slot admission before upload, definitive compaction reclamation/cursor progress, 320-ID native compaction, 5,000-ID no-false-negative summary parity, >8 MiB index fanout, explicit byte limits, footer counts, cache arena detachment, signal-specific graces, repeated headers and retryable unkeyed expiry. The public native S3/MCP regression also verifies 64 repeated projection fields; the final seven-test HTTP/MCP rerun passed.

A prior full run at 36 concurrent cases hit local fixture/time-limit failures. The final precommit used four concurrent cases and passed. Synthetic catalog fixtures exercise invariants, not production capacity. Excluded provider/integration tests were not run.

## Remaining limits and follow-ups

These are not hidden by the review or passing tests:

- Trace bucket byte capacity can bind far below the nominal 1,024-reference count; dense windows can return retryable capacity errors until rollover.
- Bloom saturation, unknown/migrated history and long windows can exhaust query budgets. Complete trace-ID and label postings remain required for workload-shaped lookup guarantees.
- Flat catalogs grow indefinitely; finite retention is required for the implemented bounded-catalog path.
- A paged compaction cursor rotates; deterministic failures in flat catalogs still need a bounded group-skipping policy. Cached-floor freshness and malformed-but-privileged manifest defense remain hardening topics. A concurrent CAS reload can still reject a mixed waiter batch on one bucket's capacity; the response is transient and no data is acknowledged, but finer per-waiter rejection is a fairness follow-up.
- JSON/protobuf policy differences around invalid zero parents, numeric-string doubles and unknown status fields need an independent OTLP conformance decision, not guesses from source review.
- No node-wide ingest admission or production memory/capacity claim.
- Withdrawal from both maintenance eligibility groups on timeout is intentional: the shared worker cannot advertise capacity while native work remains outstanding. The earlier claim that an exactly 64 KiB array necessarily produces a second leaf was withdrawn.

## Tuist acceptance still required

1. **Required query contracts:** actual PromQL/LogQL expressions and numerical/client conformance, trace regex/resource selection and `most_recent`, discovery endpoints where retained clients use them, trace pagination/completeness beyond current ceilings, and indexes at representative cardinality.
2. **Alerting:** the checked-in complete rule/routing inventories, not the older metadata-only listing. Used recording dependencies, log rules, condition graphs, templates, no-data/error/keep-firing behavior, routing/grouping/silences and webhook delivery to Atlas are not implemented by native threshold evaluation. ClickHouse and Grafana-usage rules need explicit external-source or retirement decisions; IRM belongs to Atlas.
3. **Deployment/client integration:** independently validate Tuist SDK -> Alloy/Collector -> Pulse OTLP/HTTP, remote write and Loki pipelines, authentication, batching, retries, tenant labels, MCP client version compatibility and release NIF artifacts. Choose and test the availability topology; the chart defaults to one replica.
4. **Operational evidence:** authorized staging dual-shipping with existing stores authoritative, sustained peak/headroom measurements, several lifecycle cycles, node/process loss, object-store outage and lost responses, coherent backup restore, compatible upgrade/rollback rehearsal, independent monitoring, query/alert comparisons and measured storage costs.

Follow `tempo-replacement.md` and `grafana-replacement.md`. Start with a separately authorized shadow, not a production switch or paging cutover.
