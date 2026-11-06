# Pulse deployment plan for Tuist

Status: implementation started. Deployment and replacement gates remain open. Based on the repositories inspected on October 2, 2026.

## Product direction: proactive reliability workflow

The first intended Tuist experience is now an external GPT workflow reacting to
Pulse reliability signals, investigating through read-only MCP, and proposing or
taking separately authorized actions. The target periodically assesses bounded
log/metric/trace summaries per service, including ordinary unflagged windows,
through an opt-in decision model. Keep model assessment, incremental object
work and external investigation allowances separate; use durable reservations,
episode coalescing and fleet-wide external concurrency limits, not a workflow
per event/window. Existing error-change polling and native alert replay are
integration controls, not the only gate to investigation. See the
[reliability-first plan](reliability-first.md) for the implementation sequence.

Full Grafana Cloud replacement is a separate optional-archive/client-compatibility
track, not a prerequisite for this workflow. Preserve all replacement and paging
gates below if that track is pursued. The older milestones describe that track,
not the critical path for proving signal-driven value. Keep enough raw history
for today's derived projections until durable processing/evidence is decoupled;
this design does not authorize reducing existing retention or changing production.
The external runtime owns workflow checkpoints, investigative GPT/tool spend,
action policy and human approval; Pulse's proposed assessment calls have their
own constrained provider boundary. No companion repository or deployment is
changed by this plan.

## Current continuation checkpoint

The broad protocol/storage increment landed in PR #34 (`f7a3ebe`). The milestone
baseline and early validation notes below are historical, not an up-to-date
unsupported-feature list. Use [protocol coverage](../docs/protocol-coverage.md),
[protocol follow-ups](protocol-breadth.md) and the signal-specific operator pages
for the current implementation boundary.

The next reliability increment adds atomic per-instance live-tail admission,
explicit retryable closure on follower loss, safe startup failure responses and
correct test-owned follower/storage shutdown ordering. It does not make tails a
complete changefeed or satisfy a production gate. Its full test run passes
1,618 tests; the preceding compaction-peer startup timeout remains diagnostically
open despite successful same-seed replay. Details and evidence limits are in the
[follow-up checkpoint](protocol-breadth.md#live-tail-reliability-follow-up).

**Tuist cutover remains blocked on acceptance, not just missing endpoints:**

- Workload-shaped selective query/index capacity and aggregate ingest/provider
  pressure, including cold history and multiple serving instances.
- Actual retained client/collector pipelines, retry queues, MCP transport and
  tenant authorization through their deployed gateways.
- Required alert/recording dependencies, lifecycle and delivery contracts,
  alongside explicit decisions for retained external sources and incident tooling.
- Authorized dual shipping, completeness/query/alert comparisons, provider fault
  recovery, coherent restore, compatible rollout/rollback and measured cost.

Continue with bounded Pulse-local implementation and reproducible acceptance
harnesses. Companion deployments, production routing and paging moves require
separate authorization and evidence; passing local tests does not authorize them.

## Execution progress

- Validation for the metrics compatibility slice: `mix precommit` with Prometheus 3.5.0 conformance enabled passed 677 tests (33 real-provider integration tests excluded); strict Credo, the codec's 59 Rust tests, Rust formatting, Helm lint, the documented `Recreate` render, and whitespace checks passed. Claude's adversarial review reproduced eight defects covering parser backtracking, metric names, rollout/rollback guidance, compensated sums, histogram bounds/counts, ranking parameters, and keyword/literal parsing. All are fixed with regressions; two focused follow-ups also verified fixes for cross-metric histogram grouping and negative ranking parameters, with no remaining material defect. Storage iteration can still cause last-bit or extreme-overflow differences in floating sums; NaN histogram boundaries are not meaningful supported instrumentation. This is local compatibility evidence, not a production rollout gate. Crossing the non-finite storage compatibility boundary requires the documented non-overlapping upgrade and a compatible reader for rollback.
- Implemented the Pulse-local metrics compatibility slice of milestone 5: scalar/vector arithmetic and comparisons, set operators and explicit matching, classic histogram quantiles, label replacement, clamps, ranking/sorting, rounding, and time functions. Stale markers and IEEE non-finite values now survive remote write, Parquet, and compaction; this supersedes the earlier per-sample non-finite rejection below. Native histograms and exemplars remain unsupported but are explicitly counted as rejected. A versioned fixture inventories 378 checked-in Tuist dashboard expressions (357 PromQL and 21 LogQL), with Grafana variables normalized for replay. Parsing the inventory is not proof of query-result or deployed-dashboard parity. Selected-sample/work accounting is expression-wide; object scan accounting is still per selector. Production collector delivery, discovery-variable requests, alert compatibility, capacity, and deployment remain unverified.

- Pulse-local milestone 3 query safeguards now share supervised admission across Prometheus Query Language, LogQL, raw query tools, and Loki label discovery. A node starts with four task slots, reserves one from interactive work, limits each tenant to two requests, and limits raw and discovery work to one request per class. Log and raw storage reads inherit candidate-object, byte, row, deadline, and heap budgets; explicit raw result limits retain their requested semantics. Label discovery fails explicitly above 5,000 matching records instead of returning an incomplete list. Native log regular expressions are validated before storage, so unsupported patterns remain client errors. The implementation does not yet provide aggregate scan accounting across every selector in one expression, a bounded admission queue, or posting indexes. Local verification passed 602 tests (one skipped, 33 integration tests excluded), strict Credo, and before/after headless-browser checks of native regular-expression rejection. No Tuist deployment was involved.
- The stale-sample replay passed `mix precommit` after rebasing onto the latest target with 608 tests passed, one skipped, and 33 object-store integration tests excluded. The Rust codec's 57 unit tests, Rust formatting, strict Credo, and whitespace checks passed. A local headless Chrome replay of a mixed finite and stale batch returned 500 [before](../docs/verification/stale-sample-before.png) and 204 with one rejected sample [after](../docs/verification/stale-sample-after.png). Claude's adversarial review exposed whole-batch loss from an initial 400 response; per-sample rejection resolved it. Its follow-up found no material defect, and subsequent low-severity findings led to exact rejection counts for parsed samples in discarded series, a reproducible legacy fixture, and a distinct stored-data query error. Real collector delivery and full stale-series behavior remain unverified.
- Completed the Pulse-local stale-marker and non-finite replay. The existing decoder raised an argument error when a stale marker reached Erlang. Prometheus remote write now counts each stale marker, other not-a-number value, or infinity as a rejected sample while preserving finite samples in the same batch and returning 204 with `X-Pulse-Rejected-Records`. Segment encoding refuses absent values and decoding fails cleanly on non-finite legacy data. The replay defines the current partial-rejection behavior, not stale-series semantics or production completeness; the pilot must compare staleness and rejection counts against its reference destination.
- Reconciled this branch with `main`'s independently shipped self-monitoring implementation. The endpoint retains the canonical layer-based summaries, accepted/decoder-rejected/publication-failed record counts, object payload totals, worker-wait outcomes, and combined publication queue gauge. Detailed operation/histogram/compaction families use distinct `pulse_detailed_` names, while receiver-only delivery counts use `pulse_ingest_delivery_records_total`; purpose-aware bytes, deadline counters, and separate queue/runtime gauges are preserved. Both views observe one execution of each operation, not duplicate storage work. Read [self-monitoring](../docs/self-monitoring.md) for the distinct contracts and do not add overlapping views or query layers together. Merge validation: `mix precommit` passed 597 tests (one skipped, 33 integration tests excluded), the focused suites from both implementations passed 88 tests, strict Credo passed, and both Prometheus parsers accepted 19 uniquely named, correctly typed families without duplicate samples.
- `main`'s self-monitoring validation before this merge covered all 16 focused tests, native object-store fixture calls, partial ingestion for all receivers, publication backlog during stalled I/O, and worker deadlines. Its final precommit passed 550 tests (seed 593827), with one skipped and 33 integration tests excluded; an earlier admission-cleanup race passed on same-seed replay and remains separate lifecycle work. Deployment and real-provider validation remain pending.
- Claude's adversarial self-monitoring review reproduced four defects: Prometheus family headers separated from samples, router-equivalent paths escaping counters, nonexistent label routes counted as queries, and meaningless object-byte direction series. All four are fixed with regressions. Follow-ups now count background compaction deadlines before stalled native work completes, precompute bucket strings, clarify that unknown tools are rejected before MCP dispatch, and require path-aware metrics denial/authentication whenever ingest shares a public listener. Network policy cannot separate paths on one port. Validation: `mix precommit` passed 580 tests (one skipped, 33 integration tests excluded), all 71 focused monitoring/compaction tests passed, strict Credo and whitespace/formatting checks passed, and both `promtool` and Python's `prometheus_client` accepted the exposition with all 12 metric families correctly typed. Claude independently reproduced the fixes and reran the full/focused suites and parser checks; its follow-up found no remaining material defects. Consolidating histogram counters into one ETS update remains an optional optimization, not a pilot blocker. Tuist rollout and real-provider integration remain unvalidated.
- Completed the next Pulse-local milestone 2 task and removed it from the pending list: independently scraped self-monitoring at `GET /metrics`. Node-local, finite-label counters and latency histograms cover acknowledged/rejected decoded records, ingest requests (including parser failures), public query failures (including MCP errors over HTTP 200), logical object operations/body bytes/CAS outcomes, and compaction/cleanup. Live gauges expose manifest mailboxes, in-flight publication batches, PromQL slots, and VM pressure without waiting for storage. Reporting never uses Pulse storage. See [self-monitoring](../docs/self-monitoring.md) for independent scraping, private-network access, and counting limitations: pre-decode failures count requests, retries are deliveries rather than unique records, and logical bytes are not provider billing. No Tuist deployment or collector configuration was changed; milestone 1 still needs workload inventory and production measurements.
- Self-monitoring validation: `mix precommit` passed with 574 tests passed, one skipped, and 33 object-store integration tests excluded; `mix credo --strict`, formatting checks, and `git diff --check` passed. The 65 focused monitoring/compaction tests cover all receiver formats, parser/gzip rejection, MCP failures, concurrent counters, metrics restart, logical object bytes/CAS outcomes, and scraping while manifest publication is blocked in native I/O. Prometheus 3.5.0's `promtool check metrics` accepted a generated exposition containing counters, histograms, and gauges. Real-provider integration and Tuist rollout validation remain pending.
- Validation for ingest budgets: `mix precommit` passed with 556 tests passed, one skipped, and 33 object-store integration tests excluded; `mix credo --strict` reported no issues. The Rust codec's 57 unit tests and Rust formatting check passed. Regression coverage includes all four receiver variants, exact boundaries, duplicate entries, UTF-8 sizes, aggregate bytes, structured values, empty containers, gzip, and authentication precedence. No Tuist or production-collector validation was performed.
- Implemented the remaining milestone 2 per-request record-count and attribute budgets in Pulse, without companion repository changes. OTLP JSON logs, Loki JSON/Snappy protobuf, and Prometheus remote write now reject over-budget batches with HTTP 413 before storage writes. Defaults are 10,000 records, 128 attributes per set, 256-byte keys, 16 KiB values, and 64 KiB aggregate attribute bytes; JSON trees also have depth and node budgets. Raw rejected records and repeated attribute entries count before normalization, and empty containers have their own work ceiling. Native preflight runs after one bounded decompression and before record expansion. Runtime overrides and exact counting rules are documented in `docs/ingest-limits.md`. JSON parsing remains pre-authentication under existing byte caps; this does not implement ingest admission, rate limiting, or establish collector retry behavior.
- Completed the first Pulse tool-contract task in milestone 2: all four query tools advertise read-only annotations, and calls validate the published argument types, required fields, numeric bounds, and enums before querying. Empty tenants and expressions, reversed time ranges, and incomplete Prometheus range queries return explicit argument errors. Optional null fields preserve existing defaults; integer-valued decimal numbers are normalized to integers, and unknown fields remain allowed by the published schemas.
- Adversarial review by Claude found unbounded log-metric step enumeration and raw metric pattern crashes. The implementation now shares the 11,000-step ceiling with Prometheus evaluation, rejects invalid or oversized metric patterns before storage reads, caps step conversion, authorizes the tenant before query validation, and handles earliest-timestamp windows safely. Regression tests cover native decoding at signed timestamp boundaries and schema vocabulary drift. Broader scan, row, heap, and admission limits remain milestone 3 work.
- Validation: compilation with warnings treated as errors, formatting checks, and `mix credo` passed. The full suite passed 473 tests with seed 586804, with one skipped and 33 integration tests excluded. After adding the final regular-expression boundary and compatibility-endpoint checks, all 76 focused tool, request, and evaluator tests passed. Object-store integration and companion-repository rollout validation remain pending.
- Claude's follow-up review found no remaining material defects in this change. It independently reproduced an intermittent admission-test cleanup race in the existing Prometheus evaluator tests, attributing it to unchanged slot lifecycle code. One full run hit that race before the same-seed replay passed. Keep cleanup synchronization and admission lifecycle hardening as separate follow-up work; this change does not claim to resolve that race.
- Completed three more Pulse-side milestone 2 items. The Model Context Protocol endpoint was first aligned with 2025-06-18 (superseded by the stateless 2026-07-28 transport below). Gzip request bodies inflate incrementally under a cumulative 16 MiB budget (413 beyond it), preserve multi-member semantics, and reject truncated streams; the compressed body cap is now 4 MiB. `/healthz` reports liveness and `/readyz` reports readiness from a background object-store listing probe (so a missing bucket fails), never issuing storage requests per probe.
- Codex's adversarial review of these changes found six defects (gzip multi-member truncation, unvalidated gzip trailers, a missing bucket passing readiness, overlapping and orphaned probes, and batches accepted under 2025-06-18); all are fixed with regression tests. The record-count and attribute-size limits, self-monitoring metrics, and stale and non-finite sample replay have since been completed. Configuration documentation remains tied to the deployment chart.
- Replaced that transport: the MCP endpoint now implements only the stateless `2026-07-28` revision over Streamable HTTP. There is no `initialize` handshake, session, or `ping`; every request carries its protocol version and client capabilities in `_meta` and mirrors the version, method, and tool name in headers. `server/discover` and a minimal `subscriptions/listen` (empty acknowledgement, then graceful completion) are implemented. Batches are rejected, notifications return 202 without executing, GET and DELETE return 405, and a pre-parse gate rejects disallowed origins (403) and non-JSON bodies (415) on the percent-decoded path. `Plug.MethodOverride` was removed from the endpoint so JSON bodies cannot change the HTTP method. A dual-era server was considered and rejected: Atlas's proxy speaks `2025-03-26` and requires an `Mcp-Session-Id`, so no sessionless legacy branch would have kept it working.
- Codex drafted the transport plan, and Claude amended it to be modern-only. Two adversarial review rounds by Codex reproduced six defects over a live listener: an encoded-path origin bypass, an IPv6 origin collision, a crash on non-ASCII origin bytes, form bodies reaching tool execution, generic parse errors on encoded aliases, and `_method` overriding JSON requests. All six are fixed with regression tests, and the reproduction scripts were rerun against the fixes. `mix precommit` passed 519 tests (1 skipped, 33 integration tests excluded), and `mix credo` reported no issues.
- This task is independent of the pilot tenant selection and does not establish deployment readiness. Milestone 1's workload inventory and measurements remain pending, as do the remaining milestone 2 transport, probes, monitoring, request bounds, chart, and companion-repository changes.

The goal is to collect and query Tuist's logs, metrics, and traces through Pulse, expose diagnosis tools through Atlas, and progressively replace Grafana Cloud's storage and alerting services. Pulse remains headless. Keeping Grafana for visualization or replacing that experience in Atlas is a separate product decision.

Start with a staging deployment that receives a copy of selected logs and metrics. Production replacement requires traces, query compatibility, alerting, and predictable storage cost and recovery behavior. Each milestone below has an explicit exit gate; shipping endpoints alone does not satisfy those gates.

[Architecture](../docs/architecture.md) remains the source of truth. This plan proposes work and does not change the implemented storage contract. Update the architecture alongside each implementation that changes formats, coordination, signal support, or tool capabilities.

## Constraints

- Object storage holds every acknowledged record until its configured retention expires. Acknowledge ingestion only after segments, required indexes, and manifest publication are durable.
- Keep local buffers and caches disposable. Do not introduce a shared database, local durability log, leader election, or consensus service.
- Reuse `Pulse.Rendezvous` for eligible ingest, maintenance, and rule-evaluation owners. Ownership reduces duplicate work; conditional object writes enforce correctness.
- Keep infrastructure remediation in a separate server. This plan covers diagnosis and writes contained within Pulse, such as alert acknowledgements and silences.
- Prefer compatibility needed by Tuist's actual collectors, dashboards, and alerts over full query-language coverage.
- Bound memory, work, concurrency, and queues for every signal. Return explicit errors rather than incomplete results disguised as success.

## Baseline and integration points

| Area | Implemented baseline | Gap |
| --- | --- | --- |
| Logs | Loki push in both supported wire formats; OpenTelemetry text-format logs; log query endpoints and tools | Binary OpenTelemetry receiver, compaction, retention, production query limits |
| Metrics | Prometheus remote-write version 1; float samples and stale/non-finite values; dashboard-oriented arithmetic, matching, histogram and function subset | Deployed workload conformance, discovery routes, label indexes, OpenTelemetry receiver; native histograms/exemplars if required |
| Traces | Design documented | Receiver, record model, codec, storage, lookup, search, tools |
| Storage | One Parquet object per append; batched manifest registrations; optional metrics compaction | Buffered segments, bounded manifest metadata, retention, orphan cleanup, segment cache |
| Atlas | Upstream tool proxy with bearer tokens, custom headers, and permission groups | Stateless upstream support, Pulse permission mapping, tool annotations, protocol alignment |
| Operations | Container release, production configuration, liveness/readiness probes, canonical and detailed independent Prometheus self-monitoring | Tuist chart, recovery procedures, capacity measurements |
| Alerting | Design documented | Evaluation, durable transitions, notification delivery, silences, acknowledgements |

Primary code locations in this repository are [the router](../lib/pulse_web/router.ex), [storage adapter](../lib/pulse/storage/s3.ex), [manifest owner](../lib/pulse/storage/s3/manifest_owner.ex), [metrics evaluator](../lib/pulse/promql/evaluator.ex), [log evaluator](../lib/pulse/logql/evaluator.ex), and [tool registry](../lib/pulse/mcp/tools.ex).

Companion changes belong in these repositories:

- `tuist/tuist`: `infra/helm/k8s-monitoring/`, `cache/platform/alloy.nix`, and `infra/grafana-dashboards/` define the collector destinations and query inventory. Include every environment and collectors outside Kubernetes.
- `tuist/atlas`: `lib/atlas/mcp/proxy.ex`, `lib/atlas/mcp/proxy/server.ex`, and `config/runtime.exs` define upstream transport, credentials, permissions, and configuration.
- `tuist/hive`: `lib/hive/forage/grafana.ex` and `grafana_alert.ex` consume Grafana firing and resolved webhook payloads. Inventory any deployed consumers and preserve their contract or migrate them before changing notification sources.

These paths describe the inspected checkouts. Recheck their configuration before implementing companion changes.

## Milestone 1 Establish the workload and replacement contract

Produce a versioned workload fixture and compatibility inventory before promising capacity or savings.

- Inventory all sources, collectors, destinations, tenants, authentication modes, scrape intervals, batching settings, and retry queues. Record trace sampling and current retention for each signal.
- Extract dashboard queries, variable discovery requests, alert expressions, recording rules, contact points, notification receivers, and incident workflows. Include Atlas's alert tools and Hive's alert-triggered agents. Classify each as supported, requiring implementation, or deliberately retained elsewhere.
- Capture sanitized payload fixtures from the actual Alloy and application exporters. Include classic histogram buckets, stale markers, structured logs, and spans with events and links.
- Measure at least seven representative days: accepted records and bytes, batch counts and sizes, active and newly created series, query ranges, concurrency, and trace sampling. Existing destinations remain the reference during this period.
- Record current Grafana Cloud spend and what it buys beyond storage, including alerting and incident management. Separate compute and maintenance costs when comparing Pulse.
- Define the production tenant model and measure dashboard panel fan-out, agent concurrency, and scheduled evaluation concurrency. Start by evaluating environment-scoped internal tenants; choose boundaries for authorization and operational isolation rather than splitting tenants solely to bypass capacity limits.

**Exit gate:** the inventory covers every production telemetry path and critical investigation or alert. Publish measured peak and sustained loads, required query latency, ingest freshness, retention, and monthly cost ceiling. Until measured, all numeric examples are assumptions.

## Milestone 2 Enable Atlas access and a staging deployment

Expose Pulse's existing read tools behind Atlas and deploy it privately with a dedicated staging bucket and tenant.

**Entry condition:** milestone 1 has selected the pilot's tenant boundaries and named tenants. Configure their tokens and collector headers explicitly before deploying the chart.

### Pulse changes

- [x] Declare read-only annotations for the four existing query tools and validate arguments consistently.
- [x] Align the Model Context Protocol lifecycle and transport with a supported version. Pulse implements only the stateless `2026-07-28` revision: per-request version metadata, mirrored-header validation, `server/discover`, 202 notifications, origin and media-type gating, and 405 for the removed GET stream.
- [x] Add liveness and readiness endpoints. Liveness should reflect process health; readiness should fail when the node cannot serve its configured role. Avoid a storage request on every probe by using a bounded periodic check.
- Add configuration documentation and the Tuist deployment chart: resources, secrets, networking, shutdown grace, storage permissions, and compaction enablement. Start with one node to establish the baseline; add multiple nodes for failure validation later.
- [x] Bound compressed and decompressed request sizes, record counts, attribute sizes, and decompression work before admitting pilot traffic. Gzip inflates incrementally under a cumulative cap; Snappy checks expanded length before allocation. Record and attribute preflight rejects entire oversized batches before storage writes. Tenant validation and authentication precede semantic preflight and protobuf decoding; JSON parsing/gzip inflation still happens pre-authentication under byte caps. See [ingest limits](../docs/ingest-limits.md) for defaults, runtime configuration, and counting rules.

### Atlas and Tuist changes

- Migrate Atlas's upstream client to the stateless `2026-07-28` protocol. Its proxy currently hardcodes `2025-03-26`, performs an `initialize` handshake per call, and fails without an `Mcp-Session-Id`. Pulse now rejects that flow with a 400 naming the supported version. Atlas must send `_meta` protocol fields and the `MCP-Protocol-Version`, `Mcp-Method`, and `Mcp-Name` headers on every request, and must stop requiring a session.
- Map `pulse` to Atlas's existing production-systems permission group, rather than the default group.
- Register Pulse with a tenant-scoped bearer secret and an explicit query-tool allowlist. Preserve existing upstreams when configuring `MCP_PROXY_SERVERS`, which replaces the configured server list.
- Keep shared access limited to internal Tuist telemetry. Before exposing customer-specific telemetry, implement subject-aware authorization and audit attribution through the trusted proxy boundary.
- Add a second collector destination for selected logs and metrics. Change authentication from Grafana Cloud credentials to Pulse's bearer token and tenant header. Keep independent retries so Pulse failures do not block the existing destination.
- Require explicit tenant headers in the production deployment, avoiding accidental routing to `default`. Exercise tenant-token rotation with overlapping credentials or a documented coordinated rollout, and keep old credentials valid through the collector rollout window.
- Verify the actual collectors' behavior on status 400, 413, 429, and server errors, connection resets, and lost acknowledgements. Status 429 retries are sender-dependent. Document retry horizons, persistent queue support, queue-full drops, and partial-success accounting. Measure the extra collector memory, disk, and network required for dual delivery.
- Keep the initial pilot low-volume and time-bounded. After a representative 24-hour run, report segment count per hour and signal, manifest size and bytes rewritten, publication latency, and query success. Stop ingestion or reduce scope before hitting measured bounds. At one uncombined segment per second, a signal produces 3,600 objects per hour, exceeding the metrics evaluator's default 1,024-candidate ceiling before other budgets. Buffered ingest and bounded manifest growth in milestone 4 are prerequisites for an uncapped multi-day soak.
- Publish supported pilot query windows per signal in the operator runbook and Atlas tool guidance, based on candidate counts and all scan budgets. Test those windows through Atlas and return an explicit capacity error outside them. At one candidate per second, the 1,024-object ceiling allows less than eighteen minutes even before sample, byte, or work limits; a 24-hour ingestion run does not imply a 24-hour query is supported.

**Exit gate:** an authorized Atlas session can discover and call all four Pulse tools; an unauthorized session cannot. Wrong-tenant access fails. Restarting or disabling Pulse leaves the existing collection path healthy. Validate discovery, initialization, permission filtering, query errors, and timeout behavior across both repositories. The bounded pilot passes the stale-sample and collector-failure checks and its 24-hour storage-growth report; no longer soak begins until its projected metadata and scan budgets are safe.

## Milestone 3 Bound query work and add label indexes

Keep this ahead of OpenTelemetry metrics ingestion, matching the architecture's current follow-up priority.

- Apply supervised deadlines, heap limits, scan-byte and row budgets, result limits, and per-tenant admission to log queries, label discovery, raw sample tools, and future trace queries. Retain the existing metrics evaluator's protections.
- Replace hardcoded query-slot assumptions with configurable global, tenant, and work-class admission. Today the metrics evaluator admits four tasks per node and two per tenant. Reserve capacity for alert evaluation, bound queues, and prevent dashboard or agent bursts from starving scheduled work. Include native calls that outlive a request deadline in occupied-capacity accounting.
- Add metrics label-to-series postings with a versioned index format and manifest references. Canonical labels remain the identity; the stable hash is only an accelerator.
- Define publication rules for required indexes. For older or unindexed segments, retain a correct bounded scan path. Corrupt required indexes must produce an explicit error or a proven complete fallback.
- Measure exact-name and selective-label queries against high-cardinality fixtures. Account for the added index writes and bytes in the cost model.

**Exit gate:** indexed and unindexed queries return equivalent results; hash collisions and missing-label semantics cannot lose series. Selective queries demonstrably reduce downloaded bytes. Over-budget queries fail explicitly, and one tenant cannot exhaust all query capacity. Replay the measured dashboard fan-out alongside agent queries and scheduled evaluations; each class meets its latency target without starvation.

## Milestone 4 Make storage cost and lifecycle predictable

Split this milestone into separately reviewable changes. Query guards from milestone 3 are a prerequisite for broader load testing.

### Buffer and publish segments

- Add pull-based, bounded ingestion with supervised buffers per tenant and signal. Flush on age, bytes, or record count, and bound total buffer memory and waiting requests per node.
- Begin experiments with the architecture's approximately one-second cadence and ten-mebibyte size threshold. Select actual defaults from measured cost and freshness; these are starting points, not capacity guarantees.
- Forward ingestion to eligible owners with bounded timeouts and no forwarding loops. During membership changes, preserve correctness through conditional publication.
- Preserve request identity across combined batches. Define a retry horizon and durable deduplication representation before changing current idempotency behavior. Stable request identity must not depend on which node or flush accepted it.
- Keep requests unacknowledged until all objects they require are published. On node loss, collectors retry unacknowledged data. Document possible duplicates when senders provide no stable identity.
- Choose and test duplicate semantics for each signal when collectors omit `Idempotency-Key`, as standard exporters may do. Evaluate canonical batch identity and exact-record deduplication against legitimate repeated events and differently rebatched retries. Require retry-safe log counts and metric aggregations; a warning about duplicates alone is not sufficient for parity. Define trace span identity and update/conflict handling as part of milestone 6.

### Cache and compact

- Add a bounded local cache of immutable segments, keyed by store identity and object key, with atomic writes, bounded concurrent fills, and eviction. Cache loss must affect only latency and cost.
- Add log compaction using the existing conditional replacement and durable retirement model. Extend it to traces after their storage schema ships.
- Preserve timestamp precision, labels, attributes, and duplicate semantics during compaction. Measure temporary storage amplification, merge reads, and cleanup operations.
- Evaluate range reads and columnar execution with DataFusion after measuring the cache and index gains. Avoid assuming that decoder predicate pushdown reduces network bytes when the whole object was downloaded first.

### Retain and recover

- Define configurable retention per tenant and signal, including the treatment of late records and segments spanning the cutoff. Decide whether boundary segments are rewritten or retained until wholly expired.
- Expire manifest references conditionally before deleting objects after reader grace. Reuse restart-safe retirement cleanup; do not use bucket expiration to delete live objects independently.
- Design bounded manifest partitions and tombstone expiry with the retry horizon. Specify migration, concurrent append and maintenance behavior, and how readers find a complete snapshot before implementation. Avoid replacing one large manifest with an unbounded rewritten root.
- Reclaim abandoned uploads only after a grace period and proof that no published or in-flight manifest can reference them.
- Protect indispensable manifests with recoverable version history or backups. Bound retained backup versions and test restoration; frequent full-manifest versions can themselves become expensive.
- Specify freshness behavior on manifest refresh failures. The current owner serves a cached manifest after refresh errors without a maximum stale age. Bound tolerated staleness for interactive queries and fail closed for alert evaluation when freshness cannot be established. Expose freshness and degraded-state information without returning an apparently current incomplete result.

**Exit gate:** load at the measured production peak plus agreed headroom fits the cost and resource ceilings. Buffered ingestion survives retries and ownership changes without losing acknowledged data. Cache loss preserves results. Retention, compaction, and concurrent writes survive restarts; expired objects disappear without breaking readers; metadata remains bounded across multiple retention windows.

## Milestone 5 Complete the required metrics behavior

Implement the query inventory in dependency order, rather than claiming full Prometheus compatibility.

- [x] Add scalar and vector arithmetic, comparisons, set operators, and vector matching required by the checked-in Tuist panel expressions. Deployed alerts and external dashboards still require inventory and replay.
- [x] Add classic `histogram_quantile` and the required panel functions: `clamp_min`, `label_replace`, `vector`, `time`, `topk`, `sort_desc`, and `round`. The inventoried `quantile_over_time` expressions are LogQL and use the existing log evaluator; production result parity remains part of the exit gate. Native histograms and exemplars are separate capabilities, enabled only if the inventory requires them.
- [x] Support stale markers through decode, storage, compaction, and evaluation. Preserve IEEE non-finite values and define sorted out-of-order evaluation and deterministic query-time conflict resolution. Ingest-time duplicate/rebatched-retry semantics remain milestone 4 work.
- Add series, metric-name, and label discovery routes needed by Grafana variables and integrations, including Loki series discovery where required. Record these requests alongside expressions in the compatibility inventory.
- Add `/v1/metrics` for OpenTelemetry Protocol in text and Protocol Buffers formats, with compression and partial-success behavior. Map resource and scope attributes consistently; define cumulative and delta temporality and restart behavior before accepting delta sums. Reject unsupported types explicitly rather than silently changing their meaning.
- Complete binary-format OpenTelemetry logs using the same decoding and rejection conventions.

**Exit gate:** replay the required metric fixtures through Pulse and Prometheus and compare selector, rate, histogram, arithmetic, and stale-series results with documented numeric tolerances. Every required dashboard query and variable request works, or has an explicitly accepted replacement. Existing Loki and remote-write clients still ingest without application changes.

## Milestone 6 Collect and query traces

Use OpenTelemetry over the [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) first. Alloy can translate existing application exporters, so Pulse does not need an additional native streaming receiver for the initial Tuist rollout.

- Add a span record model and versioned Parquet schema, preserving trace and span identifiers, parent relationships, timestamps, status, resource and scope attributes, span attributes, events, and links.
- Add `/v1/traces` accepting Protocol Buffers and text payloads, with compression, tenant authorization, partial success, payload limits, and the same durable acknowledgement contract.
- In Tuist's Alloy configuration, add a second trace destination using the chart's supported Hypertext Transfer Protocol exporter configuration, Pulse's `/v1/traces` route, bearer authentication, and tenant header. Keep the existing streaming Tempo destination until the gate passes. Application-to-Alloy transports can remain unchanged; verify rendered collector configuration and actual exporter delivery rather than assuming a destination address change is sufficient.
- Extend both storage adapters, manifests, buffering, retention, and compaction to `:traces`. Decide sort order and schema migration in the architecture before shipping the codec.
- Add trace-identifier lookup across all candidate segments and partitions, including spans arriving late or out of order. Add per-segment trace membership filters and bounded attribute search.
- Expose `get_trace` and `query_traces` through Pulse and Atlas. Add a documented path from log trace identifiers to spans and back to related logs. Choose the initial trace-search language from the investigation inventory; full TraceQL support is not a prerequisite.
- Preserve existing collector sampling initially. Add trace-derived service metrics or Tempo-compatible routes only where the inventory requires them.

**Exit gate:** sampled reference traces retain their span counts, relationships, events, and attributes across ingestion, restart, and compaction. Late spans remain discoverable; partial traces are identified honestly. Trace lookup and search meet measured investigation latency and scan budgets. Atlas can correlate a known failure across logs, metrics, and traces.

## Milestone 7 Replace alerting safely

Start once the required expression semantics and storage lifecycle are stable. Inventory-driven alert evaluation can precede trace search completion.

- Store versioned rules in object storage with conditional updates and supervised, rendezvous-assigned evaluators.
- Implement evaluation cadence, pending duration, firing and resolution transitions, missing-data behavior, and execution-error behavior. Query failure must not silently resolve a firing alert.
- Specify pending `for` duration, optional keep-firing behavior, label and annotation templates, notification grouping, repeat intervals, resolved notifications, and stable fingerprints. Define a durable state model for pending, firing, resolved, and repeated notifications; immutable fire records alone do not describe the full lifecycle.
- Define deterministic evaluation and transition identities before implementing immutable fire records. Test overlapping owners, clock skew, restart, and ambiguous write responses.
- Persist delivery progress and retry notifications after crashes. A unique fire record does not guarantee exactly-once delivery to an external webhook; use provider-supported idempotency or deduplication and document delivery guarantees.
- Add routing, acknowledgements, silences with expiry, and audit records. Keep these writes separate from Atlas's diagnosis-only allowlist.
- Implement required recording rules, or identify their retained external evaluator. Document which incident-management responsibilities stay outside Pulse.
- Preserve or migrate downstream payload contracts, especially Hive's fingerprints, firing/resolved status, labels, annotations, and investigation links. Replace Atlas's required alert and silence tools as well as its query tools. Validate with consumer fixtures before changing contact points.

**Exit gate:** run critical rules alongside the existing evaluator for at least seven representative days. Compare pending, firing, and resolved timelines and notifications. Demonstrate notification recovery, overlapping-owner deduplication, silence expiry, and alert behavior during storage and query failures before moving paging responsibility. A refresh or query failure cannot produce a false resolution. Hive threads firing and resolved deliveries correctly and does not start duplicate work from replayed notifications.

## Milestone 8 Validate and cut over production

Run a production pilot for one bounded workload before moving signals broadly. Keep a fallback destination and independent monitoring throughout migration.

1. Load-test representative payloads and query mixes, including high series churn and sparse collectors. Record resource usage, rejected load, freshness, latency, and actual object-store charges.
2. Exercise node termination before and after acknowledgement, collector retries, object-store throttling, lost publication responses, ownership changes, compactor overlap, cache eviction, and manifest restoration. Verify retry-safe log counts and metric aggregations and the documented span conflict policy, including retries that are rebatched.
3. Run logs, metrics, and traces to both destinations for at least fourteen representative days. Compare completeness, required queries, and investigation outcomes at equivalent sampling and retention settings.
4. Move collection per environment and signal. Move paging only after milestone 7. Verify that agents and humans can perform the replacement workflows before removing their former tools.
5. Retain access to historical data until its old retention window expires. Document that switching destinations does not migrate historical data; any backfill requires a separate bounded migration plan.
6. Roll back routing if completeness, freshness, critical alerts, latency, or the agreed cost ceiling fail. Re-enabling the former destination captures new data; it does not automatically restore the interval written only to Pulse. Keep dual delivery through the agreed rollback window.

**Exit gate:** production owners accept the evidence, recovery procedure, ongoing operating cost, and retained responsibilities. Remove each Grafana Cloud dependency only after its replacement gate passes. Decide separately whether Grafana visualization and incident management remain.

## Cost measurement and decision model

Track operations and bytes by purpose: ingest, manifests, indexes, queries, compaction, retention, retries, and backups. Reconcile the application counters against provider billing. Report cost per million accepted records and per representative investigation as well as the monthly total.

Include manifest bytes rewritten per month, conditional-write conflicts and retries, listing operations, full-object query read amplification, and dual-delivery collector overhead in the measured report. These costs do not scale solely with retained telemetry volume.

For a thirty-day month, an initial estimate is:

```text
monthly write operations = 2,592,000 × (segment writes/second + manifest writes/second)
                          + index, maintenance, retry, and backup operations
steady retained bytes   ≈ compressed bytes/day × retention days
monthly cost            = retained storage + writes + reads + listings
                          + data transfer + compute + backup overhead
```

Measure manifest write rate separately from segment rate. Today each append uploads a segment, while manifest registrations are combined over a default ten-millisecond window. Future buffered ingestion changes both rates. Collector count therefore matters as much as total volume. Compaction cannot refund original upload charges.

As reference prices checked on October 2, 2026, Amazon Simple Storage Service (S3) Standard in Northern Virginia charges $0.023 per gigabyte-month in its first storage tier, $5 per million write operations, and $0.40 per million read operations. Cloudflare R2 Standard lists $0.015, $4.50, and $0.36 respectively, with no internet egress charge. See [Amazon's regional price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonS3/current/us-east-1/index.json), [Amazon's pricing explanation](https://aws.amazon.com/s3/pricing/), and [Cloudflare's pricing](https://developers.cloudflare.com/r2/pricing/). Region, allowances, billing rounding, storage class, and future price changes affect the bill.

Illustrative assumptions: 100 gigabytes of input daily, five-to-one compression, thirty-day retention, and three aggregate incoming batches per second with one manifest write per batch. Steady storage is approximately 600 gigabytes, costing $13.80 monthly on Amazon, and 15.552 million writes cost $77.76. The $91.56 subtotal excludes reads, transfer, indexes, compaction, backups, and compute. It is not an estimate of Tuist's actual usage.

Benchmark Amazon and Cloudflare from Tuist's actual hosting locations before choosing a provider. Check conditional-create and conditional-replace correctness, tail latency, throughput, retry behavior, and recovery support. Repeated full-object downloads from Amazon to Hetzner or Scaleway can dominate storage charges. Avoid colder storage classes until retrieval charges, minimum retention, and small-object billing are modeled.

## Implementation order and decisions

Milestone 1 defines all acceptance targets. Milestone 2 enables a bounded staging pilot with protocol and input-safety entry checks. Milestone 3 protects queries and adds the documented next indexing capability. Milestone 4 makes sustained storage practical and must pass before an uncapped multi-day soak. Milestone 5 completes the required metrics and OpenTelemetry collection paths. Milestone 6 adds traces. Milestone 7 can start after milestones 4 and 5, with trace-dependent alerts waiting for milestone 6. Milestone 8 requires all replacement gates that apply to the workload being moved.

Suggested first reviewable changes are the workload inventory, Pulse transport and tool annotations, Atlas stateless transport and permission mapping, and the staging chart with selected dual delivery. Follow with query admission, label postings, buffered ingest, cache, and storage lifecycle changes in separate reviews. Keep companion repository dependencies explicit in each change.

Resolve these decisions with evidence before the relevant milestone ships:

| Decision | Evidence needed | Due |
| --- | --- | --- |
| Keep Grafana visualization or build Atlas investigations | Required human workflows and cost of replacing them | Before production cutover |
| Storage provider and region | Conditional-write conformance, hosting latency, total measured cost | Before production pilot |
| Retention, late-arrival policy, and retry horizon | Operational and privacy needs, collector retry configuration | Before lifecycle and deduplication changes |
| Manifest partition format | Growth benchmark and concurrent publication/recovery design | Before production scale |
| Metrics types and query scope | Collector, dashboard, and alert inventory | Before compatibility work |
| Trace sampling and search scope | Existing sampling, incident examples, measured volume | Before trace rollout |
| Customer telemetry authorization | Tenant model, trusted actor identity, audit requirements | Before customer data exposure |
| Alert and incident ownership | Required routing, on-call workflows, delivery guarantees | Before moving paging |

## Validation references

An adversarial review by Claude of the original plan at commit `8666478` prompted the early pilot limits, work-class admission, stale-sample checks, explicit duplicate policy, collector trace migration, and downstream alert contracts above. Supporting code was inspected, but application code was not run. Capacity depends on the measured workload; stale-marker failure behavior remains a test requirement rather than a confirmed runtime defect. The one-segment-per-second illustration is per signal, not a claim that the cost example's three aggregate batches all belong to each signal.

Claude's follow-up review found no remaining material planning blocker and recommended explicitly gating deployment on tenant configuration and documenting supported pilot query windows. Both requirements are included in milestone 2. This approves the plan's coverage for starting the inventory and bounded pilot, not production readiness or runtime correctness.

Use the repository's required compilation, formatting, and test checks for implementation changes, plus object-store integration tests against local storage and the selected production provider. Keep protocol and query conformance fixtures independent of the implementation. Documentation-only planning changes do not require starting the application.

Atlas interface changes must also follow its repository verification rules, including local browser verification and before/after screenshots in pull requests where applicable. Pulse's headless endpoints need protocol and load validation.

- [Model Context Protocol lifecycle](https://modelcontextprotocol.io/specification/2025-06-18/basic/lifecycle) and [transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).
- [OpenTelemetry Protocol](https://opentelemetry.io/docs/specs/otlp/) for receivers, formats, and partial success.
- [Prometheus Query Language](https://prometheus.io/docs/prometheus/latest/querying/basics/) and [remote-write specification](https://prometheus.io/docs/specs/prw/remote_write_spec/).
