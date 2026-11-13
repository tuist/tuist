# Pulse documentation

Pulse is a headless observability backend. It accepts logs, metrics, and traces over the
protocols your collectors already speak, stores them as Parquet in an
S3-compatible bucket, and serves queries through the Model Context Protocol and
Prometheus- and Loki-compatible HTTP APIs. It ships no user interface.

The [target architecture](architecture.md#reliability-signals-and-optional-raw-retention)
prioritizes actionable reliability signals and supporting evidence for external
agent workflows, with raw archival retention as an opt-in capability. That is
design direction, not a current processing-only mode: today's ingestion still
stores raw records, indefinitely unless event-time expiry is configured.

> [!WARNING]
> Pulse is early software. Logs, metrics, and OTLP/HTTP traces work end to end. Native alert
> evaluation, Slack delivery, live resource hints and rule history are experimental.
> Event-time retention is experimental and off by default for all signals.
> Full Grafana backend compatibility, full/verified Tempo TraceQL and Tempo
> zero/partial windows and deployed-client parity are not yet implemented.
> Default-off five-scope names and original string/int64/bool/float values accept bounded
> parent-string filters. Filtered names return complete conservative hints, not
> matching-key proofs or exact upstream omission/dedicated-column parity. Default
> names combine five namespaces plus static v2 suggestions under a shared budget
> and fail whole on storage or metadata errors, not partial vocabulary. Unscoped
> values union three original owners after optional same-parent resource/span string
> filters, a complete extension rather than Tempo's ignored-filter fast path.
> Matching complex targets and all selected legacy/corruption fail whole. Discovery12
> matching artifacts/explicit adapter support are required; old callbacks cannot
> silently drop new filters/windows. Seven stored intrinsic strings accept parent
> filters and read data, unlike the separate storage-free static shortcuts.
> event:timeSinceStart adds exact signed int nanoseconds; default event time0 can
> yield negative offsets, no events invent no values. Parent filtering is a complete
> extension versus Tempo's empty filtered path. Explicit event-time/window support
> is required; invalid requested times and unknown metadata fail whole. Paired
> positive discovery time bounds select whole retained segment envelopes, not span
> starts; all source header/provider costs remain, compaction can broaden results;
> unsupported types/nested predicates and unproven query-literal shortcuts reject rather than coerce.
> Root name/service dictionaries now recover complete retained candidate context,
> not a matching child's fields. Missing/ambiguous roots and missing original
> string root service fail409 whole. In-flight/retention-straddling traces can make
> recent/broad autocomplete unusable; no guessed defaults or skipped traces.
> Entire retained root S3 input must fit1024 objects/32MiB compressed/1M rows
> regardless of window, with all-source replay and dedicated root/window support.
> This remains experimental, not transparent production autocomplete parity.
> Canonical trace:duration now measures complete retained bounds without requiring
> roots, not exporter duration; ingestion/retention can grow/shrink it. Unfiltered
> values are int nanoseconds, parent-filtered values Go duration strings (µs), both
> lexical. Whole-tenant capture/replay/group bounds remain; high-cardinality
> nanosecond dictionaries commonly fail422, never sample/truncate. Dedicated
> duration/window adapters required; static empty duration shortcuts unchanged.
> Separate intrinsic discovery returns static protocol names and seven v2 keyword/
> empty vocabularies without storage reads, not stored data or full TraceQL support. Experimental v1/v2 exact-ID trace
> lookup supports bounded JSON/protobuf responses. A separate disabled-by-default
> Tempo-shaped bounded-selector search aggregates complete retained context before
> overlap/order/limit. Exact-service publication proofs and conservative ID summaries
> can reduce data reads, but catalog metadata and cumulative input/group bounds remain;
> this is not representative posting/index/capacity acceptance. Native window-local
> search remains distinct; neither establishes deployed-client parity. Expect breaking changes between
> releases and read the release notes before upgrading.

## Running Pulse

- [Deployment](deployment.md): install the Helm chart or run the container,
  expose it safely, connect collectors, and query data.
- [Trace search expressions](trace-query-expressions.md): bounded negated regex,
  int64/status/span-duration conditions, same-span AND/OR, costs and upgrade fence.
- [Configuration](configuration.md): every environment variable, tenants and
  tokens, object storage requirements, and metrics compaction.
- [Scaling](scaling.md): per-instance memory envelopes, autoscaling signals,
  and what does and does not scale with more instances.
- [Tenants and usage](tenants.md): the admin API, runtime tenant provisioning,
  suspension and deletion, and per-tenant usage metering.
- [Issuer credentials](issuer-credentials.md): trust one external issuer (such
  as Tuist) whose offline-verified tokens and ingest keys carry tenant and
  scopes, its signed status list, quotas, MCP OAuth discovery and client setup.
- [Querying](querying.md): the Model Context Protocol tools, the Prometheus and
  Loki query APIs, the supported query subset, and query limits.
- [Alerting](alerting.md): experimental native threshold/recording evaluation,
  ordered recording groups, Prometheus/Grafana rule-file import, durable
  recording publication, dedicated credentials, rule management and
  modification history, with explicit compatibility limits.
- [Reliability assessments](reliability.md): opt-in cross-signal windows,
  budgeted Decisions judgments, durable MCP signals and capped external handoff.
- [Keyed ingestion](keyed-ingestion.md): conditional uploads, exact-byte retry
  verification, permanent conflicts, provider costs and all-writer upgrades.
- [Historical backfill](backfill.md): offline Loki batch preparation, raw metric
  export requirements, reconciliation and safe storage cutover gates.
- [Retention](retention.md): experimental event-time retention for logs, metrics
  and traces, its irreversible rollout, policy changes, limits, and recovery.
- [OpenTelemetry logs](logs.md): HTTP protobuf/JSON, typed metadata, collector
  bridging, time/correlation semantics and storage upgrade requirements.
- [Protocol coverage](protocol-coverage.md): generic public-protocol scope, current supported forms and explicit gaps.
- [OTLP over gRPC](otlp-grpc.md): the opt-in gRPC receiver for logs, metrics and
  traces, its tenancy, limits and status codes.
- [OTLP wire compatibility](otlp-wire.md): bounded protobuf merging/oneofs, exact integers, receiver-scoped JSON fields and ingress upgrade requirements.
- [OpenTelemetry metrics](metrics.md): gauge/cumulative-sum, explicit histogram and summary ingestion,
  typed metadata and exemplars, series identity, bounded native footer postings,
  batching, upgrades and limitations.
- [Metric footer-first pruning](metric-footer-pruning.md): opt-in snapshot suffix
  reads that avoid full-object GETs only for proven-empty ordinary metric sources;
  provider requirements, added request costs and unchanged logical admission.
- [Metric discovery](metric-discovery.md): MCP and Prometheus label/value/series
  metadata, selector/time semantics, bounded scans and compatibility limits.
- [Collector bridge compatibility](trace-collector-bridge.md): locally exercised
  gRPC-to-HTTP profile, upstream schema/link metadata losses, tenant boundaries
  and delivery/retry caveats.
- [Erlang/Elixir trace exporters](trace-elixir-clients.md): pinned local SDK and
  instrumentation profiles, upstream type/counter losses and transport-specific
  delivery results.
- [Rust trace exporters](trace-rust-clients.md): pinned SDK/tracing component,
  full HTTP endpoints, environment-header precedence, gRPC bridge and observed
  whole-request failures.
- [Trace OTel compatibility and gaps](trace-otel-compatibility.md): typed and
  non-finite fidelity, upgrade boundaries, SDK/Collector validation and remaining
  Tempo-replacement requirements.
- [OpenTelemetry traces](traces.md): SDK/collector configuration, trace ingestion,
  stored metadata, MCP lookup/search, and compatibility limits.
- [Error tracking](error-tracking.md): experimental Sentry SDK ingestion,
  object-backed error events, issue grouping and read-only agent queries.
- [Error monitoring](error-monitoring.md): separately enabled S3-derived issue
  summaries and replayable agent changes, with explicit history and gap semantics.
- [Ingest limits](ingest-limits.md): per-request budgets for records,
  attributes, and payload sizes, and how to tune them.
- [Self-monitoring](self-monitoring.md): the `/metrics` endpoint, what each
  metric means, and how to scrape it without exposing it.
- [Storage costs](storage-costs.md): request and retained-byte cost drivers,
  Tigris pricing examples, and avoiding small-object amplification.

## Understanding Pulse

- [Architecture](architecture.md): the storage model, coordination through
  object storage, reliability-first direction and optional raw archive, the
  query path, and the Model Context Protocol interface.
  Read it before contributing a design change.

## Getting help

Report bugs and ask questions in
[GitHub issues](https://github.com/tuist/tuist/issues).
