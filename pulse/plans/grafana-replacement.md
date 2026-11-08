# Tuist Grafana backend replacement

## Acceptance scope

This is one application's compatibility acceptance track, not Pulse's product
boundary. Full public-protocol feature breadth is the generic goal; see
[the protocol workstream](protocol-breadth.md) and [current coverage](../docs/protocol-coverage.md).

Current metric artifact tuple is `{2,2,1,1,1}` for remote-write source starts;
the explicit-distribution tuple below is historical. Source starts require the
[fleet-wide maintenance upgrade](../docs/metrics.md#remote-write-20-start-timestamps),
not a rolling deployment under traffic.

Replace the observability ingest, storage, query, alert evaluation and notification dependencies Tuist actually uses. Pulse remains headless: it does not implement Grafana's UI or become a general-purpose SQL datasource. IRM and its incident/status integration move to Atlas and are outside Pulse's scope. Dashboard clients and any actually used profiling/synthetic products remain separate consumer or scope decisions, not an implied Pulse UI. Installed datasource entries alone are not evidence that a product is in use.

No production reconfiguration, token retrieval, or deployment mutation is authorized by this workstream. Local implementation, read-only contract inventory and isolated validation are authorized. A cutover requires human-authorized shadow deployment and rollback evidence.

## Latest checkpoint: native histograms, exemplars and cutover tooling (2026-10-20)

- **Native histograms** over Remote Write 1.0 and 2.0 and through PromQL
  (rates, aggregation, arithmetic, `histogram_*` functions), with semantics
  ported from Prometheus 3.5.0. **Exemplars** from Remote Write and OTLP,
  queryable through `/api/v1/query_exemplars`. Checked against Prometheus
  3.5.0 scraping its own native histograms and an OpenMetrics exemplar target,
  remote-writing the same data to Pulse: 20 histogram queries over 2m and 5m
  windows matched within 1e-9 (quantiles and stddev to the last digit), and
  exemplar results were identical. Prometheus sends exemplars in series
  entries of their own; Pulse joins same-label entries per request and keeps
  exemplars whose sample came in another request on value-less rows.
- **Live tail** follows shared object storage across unclustered instances via
  a per-tenant manifest poller (`PULSE_LOKI_TAIL_POLL_INTERVAL_MS`). It is
  **best-effort, not a complete changefeed**: compaction's event-time settle age
  is not evidence that followers observed late publications or failed polls.
  Excess unseen backlog closes the stream explicitly. See
  [the landing limitations](landing-review.md).
- **Self-monitoring alerts** ship in the chart (`files/alerts.json`,
  `prometheusRule.enabled`), replacing the Grafana Cloud usage and spend rules.
- **`mix pulse.parity`** compares dashboard, alert or plain queries between a
  reference backend and Pulse; validated against Prometheus on shared data.
- **Prefetch benchmark** (MinIO behind a 25 ms proxy, 1,000 segments): metric
  queries 25 s at 1, 5.8 s at 4, 2.8 s at 8, no more requests or memory. The
  product default is now 4; `PULSE_QUERY_TIMEOUT_MS` makes the 10 s query
  timeout configurable.
- **k8s-monitoring** (4.0.3, latest 4.5.3) cannot set `honor_metadata` on the
  scrapes it generates, so Tuist keeps Remote Write 1.0.
- Test robustness: wall-clock waits in tests that assumed an idle machine were
  widened or made injectable.

Remaining for cutover: the operational gates in the runbook (they need
production access), OTLP-sourced metric metadata and TraceQL `compare()`.

## Prior checkpoint: alert replay, Drilldown APIs and a manifest heap fix

**Alerting.** Every inventoried Grafana rule whose queries target the replaced
datasources (106 of 115; the other nine read ClickHouse SQL or Grafana Cloud
billing metrics) was replayed through stock Grafana's query backend with its
full query and server-side expression chain (`math`, `reduce`, `threshold`)
against Pulse: zero errors. Grafana-managed alerting over Pulse datasources is
therefore a viable migration path; routing, notification parity and shadow
evaluation against production remain cutover gates.

**Grafana exploration APIs**, each verified through Grafana's datasource
backend against the live harness:

- Loki live tail (`/loki/api/v1/tail`, WebSocket): history then live entries.
  Tailers join a per-tenant `:pg` group, acknowledged log appends fan out to
  them, and each tailer filters with the storage reference semantics plus the
  LogQL pipeline. Overload drops whole batches as `dropped_entries`.
  `PULSE_LOKI_TAIL_MAX_PER_TENANT` caps tails per tenant.
- Loki `detected_labels`, `detected_fields` and `detected_field/<name>/values`
  (Grafana's query builder and Logs Drilldown), following Loki's sampling,
  JSON/logfmt detection and Go type rules.
- Loki `patterns` and the `|>` / `!>` pattern line filters. Patterns are mined
  at query time by an independent native Drain implementation (Loki's pattern
  code is AGPL and was not ported). Every returned pattern is a valid `|>`
  filter for exactly the lines it counts. 1M lines mine in about 0.6s.
- TraceQL metrics (`/api/metrics/query_range`, `/api/metrics/query`) for
  Traces Drilldown: `rate`, `count/min/max/sum/avg_over_time`,
  `quantile_over_time`, `histogram_over_time`, `by (...)` and root-span
  selection, reduced natively per segment with Tempo's interval, labeling and
  log2 quantile semantics. Gated with Tempo search.

**Bug found by the harness:** once a tenant's trace manifest grew past ~100 KB,
every trace ingest request was silently killed. Decoded manifest strings were
sub-binaries of the manifest body, and the OTLP ingest heap cap counts shared
binaries, so ~600 references each counted the whole body (70 MB). Alloy then
retried the same batch forever (`DeadlineExceeded`). Manifests (flat and
paged) now detach decoded strings; the same request accounts ~97 KB.

Validation: full suite 1396 passed (1 skipped, 37 excluded) at `--max-cases 4`;
at default concurrency it timed out under unrelated machine load and every
failure passed on rerun. Strict Credo, codec fmt/Clippy and 112 codec Rust
tests pass.

The open decisions were settled with a Codex review and the cutover gates
written up as [tuist-cutover-runbook.md](tuist-cutover-runbook.md): Grafana-managed
alerting stays; Tempo search/metrics on for Tuist; a separate bounded LogQL
sample budget (`PULSE_QUERY_MAX_LOG_SAMPLES`); prefetch 4 only after a
benchmark; live tail recorded as a horizontal-scaling gap. Filled since:
retained remote-write metric metadata for `/api/v1/metadata` (per-tenant
CAS-merged object, published before samples), TraceQL `topk`/`bottomk`.
Validation: full suite 1405 passed (1 skipped, 37 excluded) at `--max-cases 4`;
metadata verified end to end with Prometheus 3.5.0 remote write through
Grafana's Prometheus datasource (242 families); strict Credo, codec
fmt/Clippy and 114 codec Rust tests pass.

Object-store NIFs no longer hold dirty I/O schedulers (2026-10-20): requests
run on the native tokio runtime and reply to the caller's mailbox. Blocking
calls had capped in-flight S3 requests at 10 per node and deadlocked the
default-concurrency test suite against in-VM fake stores; the suite now passes
at default concurrency (about 70 s). Wall-clock bounds that assumed an idle
machine were made injectable or widened in tests.

Remaining at this checkpoint: alert routing/notification migration and shadow
evaluation, exemplar queries, OTLP-sourced metric metadata, TraceQL `compare()`, and the
operational gates in the runbook.

## Prior checkpoint: live Grafana validation and Tuist-blocking gaps closed

A local live harness ran the Tuist-shaped pipeline end to end: Alloy 1.19.2
remote write (Basic `tuist:secret`) to `/api/prom/push`, Alloy file tailing
logfmt server lines into Loki push, OTLP traces into Alloy forwarded over
**gRPC** to Pulse, Pulse on MinIO, and stock Grafana OSS 12.3.0 with provisioned
Prometheus, Loki and Tempo datasources pointed at Pulse. All three datasource
health checks pass; panel-shaped queries (rate, `histogram_quantile` with
`$__rate_interval`, tables, `label_replace`, logs, the page-load apdex
`quantile_over_time … | logfmt | regexp | unwrap`, regex rates, numeric label
filters, TraceQL traces/spans tables and trace view) return frames; label,
series, tag and index endpoints work through Grafana. **Every query in the
Tuist dashboards (370 PromQL, 16 LogQL, 1 TraceQL, including the two v2-schema
dashboards) executes through Grafana against Pulse with zero errors.** Harness
scripts stay in session scratch space; no Tuist file, deployment or credential
was touched.

The harness found and this checkpoint fixed:

- **Alloy's Snappy-protobuf Loki pushes were all rejected on S3** (`encode_failed`):
  the native push decoder built records without the `otlp` key. Fixed in Rust,
  regression-tested at the encoder boundary.
- **LogQL metric samples used string timestamps and `"8.0"` values**, which
  Grafana's Loki decoder rejects; now Loki's `[seconds, "8"]` format.
- **Grafana's Loki health check (`vector(1)+vector(1)`) failed**; `vector()`
  literals are now supported.
- **TraceQL search rejected queries without `with (most_recent=true)`**, which
  Grafana never adds; the hint is now optional (results are always most-recent).
- **Log compaction did not exist**, so every Alloy push stayed one object; native
  Arrow log compaction now runs opt-in, and passes keep merging while they make
  progress so per-second shippers cannot outrun one merge a minute.
- **LogQL metric and limited log queries died above ~100k lines** (query heap):
  evaluation now streams 4096-row chunks, reduces lines to packed per-series
  samples, runs common pipelines natively (`log_metric.rs`), applies Loki's
  global top-k limit semantics (the old per-stream limit could omit the newest
  lines) and stops backward scans early. 2M lines/hour locally: limited log
  query ~0.02s, `count_over_time` ~0.4–0.7s, apdex quantile ~1.2–2.1s.
- **Loki label discovery failed past 5k records**; native stream discovery is
  complete or fails explicitly. Label regexes are now fully anchored as in Loki.

Also added: an opt-in Rust (tonic) **OTLP/gRPC receiver** for all signals sharing
the HTTP ingest path; Basic auth (`<tenant>:<token>`) tenancy; Grafana Cloud /
Mimir / Loki ingest path aliases; Prometheus/Loki/Tempo build info, Tempo echo,
`format_query`, Loki `index/stats` and `index/volume{,_range}`; OTLP
**exponential histograms** (classic-bucket projection) and **delta**
sums/histograms (stored as reported); configurable query budgets and opt-in
segment prefetch.

Validation: full suite 1365 passed (1 skipped, 37 excluded) with the machine
idle; a run under harness load had four unchanged AppendBuffer/StorageMonitor
timing failures that pass in isolation; randomized
parity suites (native discovery vs reference, streamed and native LogQL vs the
frozen materializing evaluator, chunked vs one-shot decode, native log
compaction vs single encode); strict Credo, both crates' strict Clippy and the
Helm lint/render pass.

Remaining for cutover: alert-rule migration (Grafana-managed alerting over these
datasources is now viable, or native Pulse rules), retained remote-write metric
metadata and exemplars, Loki live tail / detected fields / patterns for Logs
Drilldown, TraceQL metrics for Traces Drilldown, and the operational gates below
(shadow delivery, provider capacity, fault and restore rehearsal).

## Prior generic protocol checkpoint: explicit distributions

The OTLP receiver now retains and projects cumulative explicit histograms and
summaries independently of this application's observed instrumentation. Public
OTLP v1.9.0/protoc/Google fixtures cover seven source points and 24 float rows;
2,055 actual Go label cases pin canonical identities. Source counts remain exact
uint64 strings; full source envelopes, optional fields, ignored staleness values
and embedded histogram exemplars survive native storage. Source/expanded limits,
request-local identity conflicts and unchanged 16 MiB metadata bounds fail whole.
No delta accumulator, native histogram, exponential histogram or full naming
translation is claimed. Metric artifact tuple is now `{1,2,1,1,1}`; traces remain
`{2,1,3,4,12}`, object-store `{1,1,1}`. Every ingress pair must be upgraded before
relying on new types. This does not establish application/deployment/capacity or
cutover acceptance. See [metrics](../docs/metrics.md) and [protocol breadth](protocol-breadth.md).

## Latest local Rust component checkpoint

The paused Rust build/exporter slice is now exercised with actual API/SDK 0.31,
exporter 0.31.1 and tracing-adapter 0.32.1. All 143 dependency identities, including
registry/checksum, match the read-only Kura lock inventory; this is not its full
application/feature graph or bootstrap. A real loopback HTTP/W3C hop has remote
server/local adapter parenting. Programmatic-header HTTP, env-only HTTP and
gRPC→Collector0.137→gzip HTTP publish to isolated S3-stub/Parquet/CAS tenants,
survive manifest-supervision restart and match exact MCP assembly/HTTP-MCP
retained-context queries. Booleans, link tracestate and nonvacuous drop counts of 1
survive this profile. Actual 401/whole 413 and injected pre-publication 429/503
produce errors/store zero once per transport; malformed env headers and precedence
are explicitly exercised. Incoming gRPC tenant metadata never authorizes writes.

The controlled flush profile (queue/batch 64, schedule 24h vs child await 30s) and
no-proxy/no-redirect/3s blocking HTTP client are intentional deviations, not
application default batching/client/TLS acceptance. Frozen source/lock/tree and
three actual transport captures plus 13 attempts/outcomes replay offline through
native compaction/assembly/four Tempo formats. The final 15-file index 291f6ec3...
replaces explicitly preserved pre-batching/pre-constant corpora; assertions were
not weakened.
`rust_sdk` remains opt-in/excluded from ordinary/S3 CI, with no external tools
needed for replay. See [Tempo checkpoint](tempo-replacement.md#latest-otel-checkpoint-rust-sdktracing-component),
[operator scope](../docs/trace-rust-clients.md) and private `/tmp/pulse-rust-sdk/`
execution provenance. No Pulse runtime/native ABI/budget change; traces remain
`{2,1,3,4,12}`. Full Kura/application/Alloy, additional metric types, query/alert
semantics, source residency and provider/node/capacity/recovery/restore/cutover
requirements remain open. No Tuist build/edit, commit or deployment.

Final bounded precommit passes **1246 tests, 1 skipped, 37 excluded** (70.4s);
replay3 passes 14 offline SDK tests. Rust live6 passes 13 producer profiles plus
four embedded-input checks; Go regression1 passes one test and Elixir regression1
two. Integration-exclusion1 passes one/excludes four with tools unset; explicit
missing-tools fails rather than skips. Locked/offline producer build5, strict
all-target Clippy3, fresh native codec/store tests (88/5) and both native strict
Clippy checks, compile/Credo/format/diff pass. All RS source findings are
closed separately from assistant-owned execution. No capacity claim; historical
high-parallelism failures remain unresolved.

## Latest local query-gap checkpoint

The three observed TraceQL workflow gaps are now implemented for retained-context
HTTP/MCP search: negated original-string regex, status/int64 OR and own-span
duration comparisons, with bounded same-parent AND/OR/groups. All4 sampled saved
TraceQL targets parse with representative substitutions. Actual public Tempo2.9
Parquet/engine24-case plus12-literal oracles agree with native/independent Elixir
replay, and public protobuf consumers accept all24 native responses. Authenticated
local OTLP→S3-stub→HTTP/MCP and both actual Elixir profiles exercise the operators.

Expressions deliberately admit full retained scope without service/ID pruning;
existing input/context/output bounds and an additional20M prefilter work ceiling
fail whole. Window-local search/discovery retain narrower grammar. Matching
search capability4 / tuple `{2,1,3,4,12}` is required across serving instances,
without a new stored format. See the [Tempo checkpoint](tempo-replacement.md#latest-query-checkpoint-observed-same-span-expression-gaps-closed)
and [operator semantics](../docs/trace-query-expressions.md).

Whole-tree bounded precommit passes1241 tests/1 skipped/36 excluded in67.3s;
codec Rust88 and strict all-target Clippy pass; focused expression/workflow14 and
existing/planner-inclusive37 pass. Final actual-client live2 passes2 profiles
in14.1s; required public consumer2 accepts24/24 native responses; strict compile,
Credo3/format/diff checks pass. Source-only SX review is closed separately
from assistant-owned execution. Provenance stays `/tmp/pulse-trace-expressions/`.
This closes the concrete query-operator gaps, not full replacement: full Rust/Kura
application acceptance, additional metric types, deployed Alloy/application/client
behavior, source residency, alert parity and provider/node/capacity/restore/cutover
requirements remain. No Tuist edit, commit, deployment or production query.

## Latest local client/workflow checkpoint

This preceding checkpoint's query gaps are superseded above; its client and
operational limitations remain applicable.

Actual Erlang API1.5/SDK1.7/exporter1.10 profiles now cover grpcbox0.18/0.17.1,
Finch git0.3/Hex0.2, real Phoenix/Bandit/Finch loopback instrumentation and task
propagation, direct gzip HTTP and gRPC bridging, S3-stub publication/restart/MCP
and filtered trace metadata search. Ecto uses synthetic telemetry, not database
execution; application-specific server forks/bootstrap and custom job lifecycle
are not accepted. Original SDK snapshots expose boolean→string and event/link
counter losses before export. HTTP401/413/429 and OTP-specific503 retry outcomes
are asserted independently of asynchronous flush. See the
[Tempo checkpoint](tempo-replacement.md#latest-otel-checkpoint-existing-erlangelixir-clients-and-workload-gaps).

Atlas read-only metadata shows57 dashboard entries, not only the9 provisioned
files. One sampled v2 dashboard contributes262 PromQL,4 LogQL,4 TraceQL and2
Grafana-side SQL expression targets. PromQL/LogQL parse after representative
substitution; this is not numeric/client/residency proof. Three TraceQL shapes
were unsupported at that checkpoint (negated regex, intrinsic/numeric OR and
duration comparison); the new query checkpoint above closes them.
The positive original-string AND shape works against locally ingested SDK data.
Saved v2 `group` metadata incorrectly labels logs/traces Prometheus, so inventories
must inspect actual datasource/model fields. Raw deployment queries stay private
in `/tmp/pulse-elixir-sdk/`; only generic synthetic shapes enter public fixtures.
Configured trace correlations/service maps/profiles/streaming are requirements
to investigate, not evidence they are used or implemented. Grafana-side SQL/frame
operations do not imply a new general SQL backend in Pulse.

Final evidence:live16 passes2 profiles/12 SDK subprocesses in16.8s; replay2
passes7 offline/workflow tests; precommit1 passes **1229 tests,1 skipped,
36 excluded** in89.3s with `ERL_FLAGS='+S 4:4'`/max_cases4. Strict compile,Credo2,
format/diff checks, Go bridge regression and combined CI-filter sentinel pass.
Source-only reviewer closes EL-M1/L1–L5; prepared external `_build` remains a
documented trusted input, not compiled-artifact attestation. Unreleased captures
were explicitly regenerated after the completion barrier and isolated BEAM-env
fixes, with the first corpus preserved in `/tmp/pulse-elixir-sdk/first-freeze`.
Full provenance is in the Tempo checkpoint and `/tmp/pulse-elixir-sdk/`. Variable
local live timings and older high-parallelism failures are not capacity acceptance.
At that historical checkpoint Rust exporter work was paused/unvalidated; the
later component checkpoint above supersedes that pause. No new runtime/native ABI or
production limit, Tuist edit, deployment, provider/node/cutover acceptance or commit.

## Prior local OTel bridge checkpoint

Actual Go SDK 1.43/core Collector 0.137 now exercise W3C propagation across an
HTTP service hop, gRPC→gzip HTTP, typed metadata/flags/schemas, two static tenants
with shared IDs, owned S3-stub publication, manifest restart and MCP reads.
Frozen SDK API/request-message and actual Collector HTTP captures replay in three
ordinary native-only fidelity tests including compaction/assembly/export, plus
an owned-Agent regression proving evidence-limit failure preserves state. No new Pulse
runtime dependency/listener/ABI; trace tuple remains `{2,1,3,3,12}`.

The tested SDK omits link tracestate before export; Collector mixed-resource
batch splitting loses schema URLs before Pulse. Captured counterexamples are
explicit, not normalized away. Passing profile disables Collector processors
and queues; examples no longer unconditionally recommend trace batch processors.
429/503 injected before commit retry unchanged payloads, actual401/413 do not;
a malformed public-protobuf partial case stores one span without replay, but
upstream gRPC OK does not expose backend rejection count. SDK background export
failures can escape a later flush result. Queue/crash/provider/ambiguous-commit
and actual Rust/Elixir/Alloy/TLS deployment profiles remain unaccepted; subsequent
local component checks above do not accept those deployments.

Validation: final explicit `collector_bridge` live13 passes; precommit4 with
`ERL_FLAGS='+S 4:4'`/max_cases4 passes **1222 tests, 1 skipped, 34 excluded** in98.3s;
strict compile, Credo6, format/diff checks and all four replay tests pass. Dedicated tag stays excluded from normal/S3 integration CI;
a temporary integration sentinel proves CI filter exit0 without binaries. Source
review closed BR-M1/L1/L3/L4/L5; L2/L6 (port handoff/direct Unix pid cleanup) are
documented fail-closed limits. CB-L1/L2/L3 and wording nits also close after the
preserved-state limit test, build-info SHA pin and source/retry citations. Credo4
nesting failure is fixed by a pure private helper; Credo5/6 pass. Source closure
is not execution/capacity proof. Provenance/results:
`/tmp/pulse-collector-bridge/`, fixture README and
[Tempo checkpoint](tempo-replacement.md#prior-otel-checkpoint-actual-sdkcollector-loopback-bridge).
[Operator contract](../docs/trace-collector-bridge.md) distinguishes actual local
evidence from deployment/Alloy/receiver-auth/capacity/cutover acceptance. Prior
high-parallelism failures remain unresolved. No commit, deployment, real provider
or node restart, production mutation or replacement approval.

## Inventory evidence

Read-only snapshot from the Tuist repository and Grafana MCP:

- Managed `infra/helm/k8s-monitoring/values.yaml` forwards Prometheus remote write, Loki pushes and OTLP/gRPC traces through Alloy. Kubernetes/node/pod metrics, events, logs and managed workload traces are enabled. Trace exporters can bridge through Alloy to Pulse OTLP/HTTP; existing delivery remains authoritative until shadow comparison succeeds.
- Nine provisioned dashboard files contain 303 distinct panel query contracts: 301 PromQL, one Loki selector, and one TraceQL selector. All 301 PromQL expressions parse after resolving dashboard variables, but parser acceptance is not numerical/client compatibility proof.
- The TraceQL contract combines exact resource namespace/name with a regular-expression environment predicate and `with (most_recent=true)`. Native `search_traces` now accepts its expanded string-selector syntax and groups before trace limits, but its explicit window-local aggregates/order do not yet establish Tempo/Grafana trace-wide metadata, roots, most-recent semantics or datasource/API compatibility. Existing exact `query_traces` filtering alone does not satisfy it.
- The Loki contract selects environment, pod and container labels. It must work on native stored logs, not merely proxy to an existing Loki destination.
- Grafana reports 21 installed datasources, including the three observability stores, Alertmanager, Pyroscope, synthetic monitoring, k6, SQL/ClickHouse and Sentry plugins. Determine actual usage before claiming all are replaceable.
- `status/src/grafana-irm.ts` reads Grafana incident APIs for public status. That dependency moves to Atlas with IRM; Pulse supplies observability and alerting rather than incident management.
- The earlier 118-entry metadata-only listing is superseded by 115 complete definitions under `plans/alerting/`, including four recording rules and 104 distinct Prometheus expressions. Full definitions do not establish source residency, graph/lifecycle/routing parity or acceptance. Never export webhook secrets into fixtures.

`scripts/grafana_inventory.exs` provides reproducible, credential-free extraction of panel expressions from a dashboard directory. Inventory source files remain unchanged.

## Implementation and validation gates

1. **Storage lifecycle across signals:** bounded per-partition active catalogs, durable partition discovery, safe legacy reads/migration, compaction, explicit retention, bounded hot retirement metadata, recovery and restart tests. PR #32 supplies paged retention authority for configured windows; retain-forever flat catalogs remain unbounded.
2. **Metrics:** independent Prometheus conformance for every used expression and label-discovery endpoint; classic/native histogram and exemplar requirements identified; stale/non-finite parity; large cardinality/workload capacity, posting indexes, and alert/recording-rule input completeness.
3. **Logs:** native Loki-compatible queries/labels and the actual LogQL grammar, structured metadata/trace IDs, ordering and pagination, durable retention/compaction and production-volume capacity.
4. **Traces:** the gates in `tempo-replacement.md`, including typed attributes, complete lookup/indexes, bounded native TraceQL/regex, discovery/Tempo envelopes and Collector partial-success/retry conformance.
5. **Alerting:** full used Grafana query/condition chains, missing-series/no-data/error/keep-firing behavior, recording rules, routing/grouping/silences/mute intervals and durable delivery/retry semantics. Native thresholds alone are insufficient; imported definitions cannot simply be enabled.
6. **Adjacent dependencies:** Atlas owns IRM/incident/status migration. Inventory profiling/synthetics and dashboard consumers separately. No implied UI replacement or hidden SQL proxy feature.
7. **Operational cutover:** actual shadow delivery, workload-shaped sustained runs, process/node loss, ambiguous publication, object-store outage, multiple lifecycle cycles, data/alert comparison and rehearsed recovery. External tests and human authorization are required before a readiness claim.

## Current checkpoint

**OTel trace non-finite fidelity is implemented:** both HTTP transports retain
NaN/+∞/−∞ class and doubleValue identity at all five owners/nesting through
Parquet, native compaction, native/reference assembly, JSON/protobuf export and
Tempo dictionaries. NaN normalizes to quiet class (no sign/payload/signaling bits);
finite/signed-zero contracts stay unchanged. Raw exact/regex queries remain
projection predicates, now explicitly documenting non-finite strings/base64 bytes;
original-string selectors remain typed. Service promotion uses only original
stringValue, so byte-service normalized fingerprints change. Old/new copies of
the same byte-service span conflict permanently at lookup; drain keyed retries,
avoid mixed writers/resends, never evade conflicts by overwriting/deleting history
or rotating keys. Old records are not rewritten. Current trace native tuple is
`{2,1,3,3,12}`, requiring every reader/writer/compactor/serving app/native pair to
upgrade before writers resume. Metric/object requirements below are unchanged.

Actual public Tempo v2.9 Parquet/TraceQL produces 14 dictionaries over six spans;
its generated decoders reconsume 14 native dictionary protobufs and both v1/v2
lookup protobufs (16 required outputs), verifying owner/nested classes and signed
zero. Frozen input/oracle/producer SHA checks and optional native fixture emitter
ship; ordinary tests have no Go/Python/network dependency. Owned HTTP gzip JSON
and protobuf → same keyed S3 object → supervisor restart → MCP and Tempo lookup
and discovery also pass. Native/reference regressions preserve typed string/double
conflicts and disclose the synthetic old-byte-service duplicate boundary.

Validation: final `ERL_FLAGS='+S 4:4' mix precommit` passes **1218 tests**, one
skipped/33 excluded, max_cases8 (81.9s); strict compile/Credo/Mix/Cargo formats and
diff check pass. Codec85 Rust tests and all-target strict Clippy pass. Independent
source-only review closed NF-M1–M3/NF-L1–L2; execution evidence is ours. The first
max_cases36 full attempt had 81 broad manifest/HTTP/query timeouts; not root-caused
and not a pass. A second max_cases8 run had one loopback PUT transport failure;
that test passed unchanged in isolation, then the complete third run passed.
Prior footer baseline used max_cases4. No production limits/deadlines/test
assertions were weakened to get this result; high-concurrency/provider/native
capacity remains unaccepted, not dismissed by the lower-concurrency pass.

[OTel/Tempo gap matrix](../docs/trace-otel-compatibility.md) prioritizes real SDK →
Collector/Alloy → Pulse propagation/batching/retry/tenant acceptance before direct
gRPC unless the bridge is insufficient. Resource entity refs/duplicate singular
wire forms, 5000-span/16MiB lookup/shared client-server IDs, deployed clients and
cold/provider/separate-node/recovery capacity remain explicit gaps. No live
pipeline, load/fault/restore, deployment, shadow or cutover authorization. Nothing
committed/deployed; full Grafana/Tempo replacement remains unaccepted.

**Opt-in metric footer-first exclusion is implemented:**
`PULSE_METRICS_FOOTER_PRUNING_ENABLED` / `metricsFooterPruning.enabled` default off.
A bounded 64 KiB suffix and at most one expanded 1 MiB footer can prove no surviving
group using shared time/postings; otherwise fetch one full matching snapshot.
Strong ETag/exact Range/If-Match/EOF/deadline failures reject whole. No new format,
authority or keyed encoder bytes. Each source costs max(full logical size,
transferred bytes), actual footer rows are charged before expansion/exclusion,
and 404 retries retain reserved costs. Independent 128 MiB/1M-row per-source caps
are explicit. Provider prerequisites, extra GETs, unread-body integrity and native
memory/capacity limits are in [operator docs](../docs/metric-footer-pruning.md).
At that footer-pruning checkpoint, metric codec tuple was `{1,1,1,1,1}`, object-store `{1,1,1}`; local fences do not fence
old pooled apps. Discovery and maintenance still use existing whole-object paths.
A nonmatching host/environment combination with both values present in manifest
summaries uses a single 64 KiB GET; actual HTTP/MCP, independent same-BEAM contexts,
restart/compaction/retention and undercounted-footer HTTP422 tests run with flag on.
Large/oversized/corrupt footers, snapshot changes, weak tags, missing-after-probe,
deadlines, limits and disabled path have owned local HTTP/native tests.
Local full precommit: 1212 passed, 1 skipped/33 excluded; final focused 23 passed.
Rust 85 codec/5 object-store tests and both all-target strict Clippy pass. This is
not selected-column/row-group range reads, external indexes, separate-node or
representative/deployed-provider capacity acceptance. Nothing deployed/committed.

**Bounded metric discovery is implemented:** MCP `discover_metrics` and
GET/form-POST Prometheus label names, label values and series share authorization
and discovery admission. OR selectors share one source scan; exact sample times,
empty-label-as-absent projection and pairwise series ordering are explicit.
Native timestamp/canonical-label projection preserves dictionaries and reuses
keys per 1024-row batch instead of expanding samples or probing repeated labels.
Actual footer rows, retries and retention floors are charged; 5000-entry/1MiB
key/output and independent source/work/probe limits fail whole, never truncate.
A pre-parser 32KiB form/query gate retains raw duplicate scalars and consumed
connections. Metrics serving codec tuple is now `{1,1,1,1}`; no file-format change.
See [operator contract](../docs/metric-discovery.md) for TSDB metadata differences,
reference bounds and all-serving-pair upgrade requirements. This closes missing
HTTP metadata routes, not Grafana browser/datasource acceptance or S3 indexed
planning/range reads. Local 1204 Mix tests pass (1 skipped/33 excluded), 84 codec
Rust tests and strict checks pass; owned local HTTP tests cover gzip JSON/protobuf,
independent same-BEAM contexts, HTTP/MCP, restart, compaction, enforced retention
and undercounted-footer rejection. No deployed provider/client/capacity evidence
or production changes; source-only review has no open findings in this slice.

Metrics now have a bounded native label→canonical-series→row-group footer
postings slice, not external sidecars or provider/indexed-capacity acceptance.
Unkeyed writes and fresh compaction keys can carry complete partitions under
512-series / 100k-row / 16-name / 64 KiB footer limits; absent or rejected indexes
scan. Exact equalities intersect before Arrow decode; other matchers still run.
Whole-object GET bytes, source budgets and per-instance admission are unchanged.
Keyed appends retain the pre-index v2 byte layout to avoid deterministic-key PUTs
changing object size beneath published manifests. A frozen first-party
source-equivalent v2 golden guards later byte drift, not historical/deployed
writer compatibility. Local native metric tuple is now `{1,1,1}`; trace tuple
remains `{1,1,2,3,11}`. See [operator scope](../docs/metrics.md#bounded-native-query-acceleration).
Local checkpoint: 1174 passing Mix tests, 1 skipped / 33 excluded, 78 codec Rust
tests; strict compile, Credo, Clippy, formats and synthetic Helm lint/render pass.
The native layout test selects 16,384 rather than 24,576 Arrow rows and proves an
empty conjunction before decode. Synthetic HTTP gzip→S3→independent same-BEAM
instance contexts→restart→MCP/PromQL→compaction tests preserve complete results;
these are not separate-node, deployed provider/client or capacity evidence.

**Immutable keyed publication checkpoint:** all signal appends now use conditional
creation, with native streaming exact-byte verification after any failed create.
At most two create/verify rounds recover a 412 followed by missing GET, and
verification has a 15s cap shortened by an explicit internal append deadline.
Only create success or exact matching bytes can register the candidate's size and
summaries through the existing manifest CAS. Byte conflicts are permanent HTTP409
(OTLP code6), counted without tenant/key labels. Recording conflicts retain FIFO
intents and expose their precise diagnostic. Retired/floor publication fences
remain authoritative; no semantic equality inferred from keys, metadata or hashes.
All writers must upgrade/drain because old unconditional writers remain dangerous.
See [keyed ingestion](../docs/keyed-ingestion.md) for costs, orphan limitations and
operator recovery. Semantic cross-encoder recovery, actual mixed-provider/node
capacity and rollout/restore acceptance remain open. Never rotate deterministic
keys just to evade conflicts or infer production migration authorization.
Latest local validation: `mix precommit --max-cases 4` passes 1188 tests with
1 skipped / 33 excluded; 78 codec and 3 object-store Rust tests pass. Strict
compile, Credo, both crates' all-target Clippy, formats/diff checks and synthetic
Helm lint/render pass. Source-only review has no open findings in the reviewed
slice, not independent test/provider/client provenance. The exact-byte tests use
owned local HTTP object stores and independent contexts in one BEAM; no deployed
provider, separate-node, load/fault exercise or production action is implied.

Rust-native trace query/encode/read/compaction and exact-ID `get_trace` assembly are implemented. Traces now reuse PR #32's bounded paged retention authority, shared cleanup/discovery, committed floors and delete admission. `PULSE_TRACES_RETENTION_DAYS` defaults to zero. The unreleased receipt-based v3, seconds TTL and frozen admission cutoff are removed: latest-floor publication fences remain authoritative. Unkeyed OTLP rejects semantic expired/future spans with partial success; keyed payloads are never rewritten.

OTLP/HTTP logs now accept protobuf/JSON/gzip with typed body/attribute/resource/scope envelopes, schema URLs, event names, flags/dropped counts, original context and source times. Event time falls back to observed time; receive-time assignment is unkeyed only. Invalid keyed batches and missing keyed times fail in full; oversized normalized metadata never publishes. Versioned native bindings/startup guards, legacy/corrupt Parquet fixtures and real HTTP/native-S3/MCP cases cover storage fidelity and deterministic retries. Large consumed-body connection failures are fixed for logs/traces/Loki/remote_write. Upgrade all readers/writers and drain legacy keyed retries before rich writes; old observed-only null-time objects are not automatically reindexed. Compiler/provider fixtures are not live exporter acceptance. See [`../docs/logs.md`](../docs/logs.md).

At the initial scalar-receiver checkpoint (superseded for histograms/summaries by the generic protocol increment above), the OTLP metrics persistence foundation added nullable typed metadata, metadata-aware deterministic identity and duplicate sharing, legacy six-column reads and versioned codec/startup checks. A metadata-only 16 MiB column budget does not constrain existing scalar/label compactions; raw metric result text has a separate 16 MiB cap. Metadata-budget compaction failures shrink whole source sets before upload. `POST /v1/metrics` now accepts JSON/protobuf/gzip scalar gauges and cumulative sums with complete resource/scope/descriptor/point metadata and embedded exemplars. Delta/unspecified sums and histogram/summary points are explicitly rejected; keyed invalid batches never publish subsets. A pinned independent protoc/Google corpus and native S3 tests cover concurrent cross-format retries through independent instance contexts, restart recovery, compaction and raw MCP fidelity. These contexts are in one BEAM, not cross-node/provider/live SDK acceptance. Operators must establish unique stream labels and bound repeated-metadata batches. Direct gRPC and full Prometheus OTLP name translation remain unsupported. See [`../docs/metrics.md`](../docs/metrics.md). All readers/writers/compactors must be upgraded before metadata-bearing writes, since old compactors erase the new column.

Managed trace leaf references carry conservative ID/service summaries, so irrelevant leaves can be skipped before metadata reads. Legacy/unknown summaries scan, and dense catalogs can still exhaust explicit budgets. Assembly reports the committed floor and covers stored spans at or above it, not exporter completeness. Trace posting indexes, query/API breadth, alerting parity and live workload acceptance remain unresolved.

Native `promql_recording` rules now publish CAS-fenced immutable results through a durable bounded outbox into keyed S3 metrics, with stale-series/configuration retirement, catch-up and publication diagnostics. A controlled native S3 fixture executes all four original Kura producer expressions in explicit dependency order. Automatic recording-group ordering, input residency and same-tick freshness remain unimplemented; Grafana imports stay disabled. See [`tuist-recording-publication.md`](tuist-recording-publication.md).

Read-only disabled Grafana graph previews now support explicitly mapped same-tenant native Prometheus instant and metric-producing LogQL instant/range queries, a bounded math/threshold/strict-last kernel, shared cross-language source-query budgets and conservative response-size limits. All 115 inventoried expression graphs compile; 968 independent synthetic parser/IEEE/union-shim cases target public Grafana v12.3.0, not Cloud 13.3 or the entire server. Source residency, native/Grafana frame conversion, complete Loki pipeline parity, SQL/external adapters, lifecycle/template/delivery policy, recording closure and migration remain separate blockers. No wrapper can be enabled through this increment.

The LogQL foundation additionally repairs grouped/interpolated quantiles, unwrap label identity, typed binary/set matching, empty-window/absence behavior, nonfinite folds/ranking and shared sample/work/point budgets. All 16 inventoried Loki expressions now parse and validate; 63 independent public Loki v3.6.6 extracted-quantile cases and native synthetic regressions cover that scope, not full deployed query parity. HTTP query time handling now honors instant time and validates seconds/nanoseconds/RFC3339 bounds, preserving submicrosecond fractions. Unsupported post-unwrap/counter semantics fail closed; native Loki preview bindings are explicit and imports remain disabled. Range previews preserve the declared interval and sparse native points, not Grafana gap-filling semantics. Reducer ULP/tie, complete pipeline/error-label, scalar/client-envelope, residency and long-window capacity gates remain.

Native log alerting now uses closed `logql_threshold` rules over stored log metrics, the existing CAS lifecycle/history/outbox, explicit keep-last/OK empty-result policy, required signal-manifest freshness and bounded-reason skip diagnostics. This is a deliberately authored native rule contract, not Grafana import execution. Missing authority never becomes no-data through LIST reconstruction. Native instance overflow publishes error health without truncation. Deliberately authored `expression_threshold` rules can combine 1–16 native instant Prometheus/LogQL sources under one worker and bounded kernel, rejecting label-drop notices rather than firing partial/unlabeled results. Explicit optional source `empty_value: 0` handles successful fully empty vectors only, never missing authority/errors/partial label sets. Fixed kernel violations publish error health rather than indefinite skips. This does not enable/import Grafana graphs or external datasource bindings. All evaluators must upgrade before using the new kind/policy; source parity, imported lifecycle and notification policy remain gates.

Validation checkpoint: 1024 passing Mix tests (`mix precommit --max-cases 4`) (1 skipped, 33 excluded), 61 passing codec Rust tests, clean strict Credo/formatting, Rust Clippy and Helm lint/opt-in rendering. These are intermediate increments, not acceptance of all gates. Scope is settled: Pulse remains headless and supplies storage, querying and alerting; IRM moves to Atlas. The query compatibility increment now supports the missing used PromQL functions and explicit-resolution subqueries. All 104 distinct inventoried Prometheus source expressions parse and execute on empty inputs; 780 independent numerical cases and four exact large-epoch checks pass against promtool 3.5.0. This does not enable Grafana graphs or establish telemetry residency. See [`tuist-query-conformance.md`](tuist-query-conformance.md). No production mutation or cutover has been performed. See [`tuist-adversarial-review.md`](tuist-adversarial-review.md) for the latest repairs, review verdict and remaining backend acceptance requirements.
