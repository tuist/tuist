# Actual Erlang/Elixir SDK trace fixtures

These are synthetic, first-party producer workloads run against public pinned
libraries, not a new Pulse SDK. No application repository, customer payload,
production credential or Grafana saved query is included.

## Provenance and scope

Both profiles use API 1.5.0, SDK 1.7.0, exporter 1.10.0, Phoenix instrumentation
2.0.1, Bandit instrumentation 0.3.0, process propagator 0.3.0 and Ecto
instrumentation commit `c37d1226ec83d81458a372d5f9bc6188db564d74`.

| Profile | grpcbox | Finch instrumentation | Phoenix | Req | Bandit |
| --- | --- | --- | --- | --- | --- |
| modern | 0.18.0 | commit `acd292b1515f022429fc9759bee7cff6ff6f9de4` (0.3.0) | 1.8.15 | 0.6.2 | 1.11.1 |
| legacy | 0.17.1 | Hex 0.2.0 | 1.7.21 | 0.5.17 | 1.11.1 |

The two explicit isolated dependency graphs have their own complete locks with
Hex checksums and git SHAs. They match the listed client/instrumentation versions,
**not an entire application's dependency graph or bootstrap**. In particular,
the legacy fixture deliberately uses public upstream Bandit 1.11.1, not an
application-specific server fork. An initial attempt to fetch that fork's pinned
commit failed checkout; it is not accepted as tested. These fixtures do not vendor
upstream implementations. Dependency downloads/builds occur only during explicit
external preparation, never ordinary replay or Pulse startup.

`run.exs.txt` manually starts an isolated global provider and batch processor,
with resource explicitly supplied to both, an explicit deterministic trace-ID
generator, queue 64, scheduled delay 60 seconds and an explicit force-flush.
The recorded toolchain is Elixir 1.20.4 / OTP 29. Span IDs use `unique_integer`,
source times use the actual wall clock, and fresh captures are **not byte-for-byte
reproductions** of these files. Captured ports are owned
loopback ports, not deployed addresses. Resource detection is disabled. This is
not a default SDK timer, deployment configuration or sampling acceptance test.
The bootstrap explicitly uses the pinned SDK's internal supervisors, not its
standard application startup or any consumer application's bootstrap. A stateless
completion observer after the batch processor waits for all five synchronous
`on_end` insertions before stopping the HTTP server or triggering flush; there is
no sleep or assumed response/telemetry ordering.

The producer sends a real Req/Finch request to its owned Bandit/Phoenix router,
with actual W3C headers. Actual Bandit/Phoenix/Finch instrumentation creates
spans/route attributes; an actual process-propagator task retains its parent.
Ecto's library handler is exercised with **synthetic telemetry**, a fake repo
adapter identity and parameterized SQL text. No PostgreSQL/Ecto query or Oban
application executes. Exactly five spans include resource and scope schemas,
remote parent flags/tracestate, int64 >2^53, signed zero/arrays, events and links.
BEAM cannot emit non-finite float values; none is claimed here.

For each profile and HTTP/gRPC protocol:

- `*-oracle.json`: first-party SDK `span` record snapshot, typed attributes,
  original drop counters, recorded runtime/library versions and separate flush
  and exporter-callback results. This is not an independent upstream oracle.
- `*-sdk.protobuf`: the exporter's own `otel_otlp_traces:to_proto/2` plus
  generated protobuf encoding of the handed-off export table. This is an
  internal conversion entry point, not a documented public SDK API. This is **request-message re-encoding, not literal
  HTTP/2/gRPC frame interception**; the decorator forwards the real exporter and
  its actual result.
- `*-delivered.protobuf`: decompressed **actual HTTP body** captured immediately
  before forwarding to Pulse, either directly or after core Collector 0.137.0.
  The gRPC profile has no Collector processors/queue/retry.

The SDK attributes and metadata are not rewritten to hide losses.
Exporter 1.10.0 turns bools, including array elements, into original OTLP strings;
event/link attribute-drop counters 1 become 0; the SDK link record has no original
flags/remote field and exports flags 256. Original source snapshots retain those
facts. Assertions account for only those precise exporter differences, then
require strict SDK-message/delivered/stored equality. Link tracestate and schemas
survive this profile. Signed-zero bits are checked explicitly, including in live
stored rows and typed array values.

Upstream source citations are the public Hex `opentelemetry_exporter` **1.10.0**
artifact (both locked Hex checksums are in each `*.mix.lock.txt`), matching the
upstream `opentelemetry-erlang` tag **`opentelemetry_exporter/v1.10.0`**,
peeled commit `9f0511e705f18e4b3cc1767b42367ba49e02455a`. Both encoder files
were fetched read-only at that commit and SHA-compared with the built Hex sources:
common `3b1032637ad499cda42efa113b6134cf0cfbb10fa4bddb97489b36c6d1eb40c6`,
traces `685f2e222c3e5b058cc63cb5242baed353fd05c6cda8a36b521ca231890bed3d`.

- `apps/opentelemetry_exporter/src/otel_otlp_common.erl`, `to_any_value/1`:
  `is_atom` precedes `is_boolean`, also reached for array elements.
- `apps/opentelemetry_exporter/src/otel_otlp_traces.erl`, `to_events/1`:
  event dropped-attribute counter is absent.
- The same file, `to_links/1`: dropped attributes are explicitly 0;
  `build_span_flags(undefined, 0)` emits 256. The SDK 1.7 `#link{}` record in
  `apps/opentelemetry/include/otel_span.hrl` has no flags/remote field.

The Hex artifact/checksums are authoritative for this run; no claim of a
separate runtime or deployed-source verification is implied.

The local harness additionally covers native Parquet/CAS through an owned S3
HTTP stub, manifest-supervision restart, authenticated MCP and filtered metadata
search, cross-tenant denial and actual 401/whole-batch 413. Injected
pre-publication 429 returns export error without retry; 503+Retry-After is retried
by this OTP `httpc` profile with identical compressed bytes before success.
`force_flush` is `:ok` even when the actual callback is `:error`. These delivery
observations belong to the live test, not the frozen positive captures. No real
provider, node restart, ambiguous postcommit loss, durable queue, exactly-once,
TLS, Alloy, application bootstrap, capacity or cutover acceptance is established.

## Offline replay

```sh
ERL_FLAGS='+S 4:4' mix test test/pulse/otlp/elixir_sdk_test.exs \
  test/pulse/traces/workload_contract_test.exs --max-cases 4
```

This never downloads, builds, probes or runs an external SDK/Collector. It uses
only these frozen files plus Pulse's normal native toolchain. Replay validates
all pinned sources/locks/captures, SDK-record differences, native Parquet and
compaction, native/reference whole-trace assembly and four Tempo export formats.
The checksum index is itself pinned in the test:
`4cc29459e456387b3151e3fbde3840b0198b3506ccadcfb1230f69fa3c8a572e`.
Do not silently refresh captures or hashes.

## Optional local reproduction

Prepare two owned directories outside Pulse. This step explicitly downloads and
builds only the public client libraries. Prepared `_build` directories are trusted
inputs: source/lock identity and version checks do not cryptographically attest
compiled BEAM files or git working trees. Prepare fresh directories rather than
reusing an untrusted or stale build:

```sh
fixtures="$PWD/test/fixtures/traces/elixir_sdk"
modern="$(mktemp -d)"
legacy="$(mktemp -d)"
for profile in modern legacy; do
  if [ "$profile" = modern ]; then target="$modern"; else target="$legacy"; fi
  for name in run capture_exporter snapshot fixture_plug router ids repo completion_processor; do
    cp "$fixtures/$name.exs.txt" "$target/$name.exs"
  done
  cp "$fixtures/$profile.mix.exs.txt" "$target/mix.exs"
  cp "$fixtures/$profile.mix.lock.txt" "$target/mix.lock"
  (cd "$target" && ERL_FLAGS='+S 4:4' mix deps.get && ERL_FLAGS='+S 4:4' mix deps.compile)
done
```

Use the pinned core Collector 0.137.0 binary prepared as described in the
[Go bridge fixture](../collector_bridge/README.md). Then explicitly opt in:

```sh
PULSE_TEST_ELIXIR="$(command -v elixir)" \
PULSE_TEST_ELIXIR_SDK_DIR="$modern" \
PULSE_TEST_ELIXIR_SDK_LEGACY_DIR="$legacy" \
PULSE_TEST_OTELCOL=/absolute/path/to/otelcol \
ERL_FLAGS='+S 4:4' mix test \
  test/pulse_web/controllers/elixir_sdk_live_test.exs \
  --include elixir_sdk --max-cases 4
```

Missing tools/paths fail, not skip. `:elixir_sdk` stays excluded from default tests
and the S3 integration job even with `PULSE_INTEGRATION=1`. Each test owns all
SDK OS processes, loopback listeners, state and synthetic credentials. The
external-command helper clears known OTel/gRPC/proxy variables only in the child.
For the Elixir process it also clears `ERL_*`, `ELIXIR_*` and `MIX_*`, preventing
inherited code paths or flags from overriding the explicit two-scheduler profile;
it is **not an OS sandbox**. Cleanup signals the owned direct Unix pid, not a
process tree; use direct executable/exec-launcher paths, not daemonizing wrappers.
Port reservation/handoff remains a race that must fail readiness, never attach to
an existing service. Generated captures under `tmp/` are evidence, not permission
to overwrite these fixtures. No traffic goes to a hosted telemetry provider.
