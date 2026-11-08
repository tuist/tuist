# Trace compatibility fixtures

## Actual SDK/Collector bridge

[`collector_bridge/`](collector_bridge/README.md) contains a first-party harness
workload driven through the actual Go SDK 1.43/core Collector 0.137, with frozen
SDK request-message/ReadOnlySpan snapshots and Collector HTTP requests. Ordinary
Elixir/Rust replay requires no Go, Collector, network or executable probes. An
explicitly tagged optional loopback harness checks propagation, static tenants,
S3-stub publication/restart/MCP, retries/permanent errors and partial delivery.
It captures pre-Pulse SDK link-tracestate omission and Collector batch-split
schema loss rather than claiming a transparent generic bridge. These SDK
snapshots are not an independent upstream oracle; see the nested provenance,
checksums, limitations and reproduction instructions.

## Actual Erlang/Elixir clients

[`elixir_sdk/`](elixir_sdk/README.md) freezes two isolated real SDK/API/exporter
profiles with grpcbox and Finch instrumentation version differences. Real
loopback HTTP covers Phoenix/Bandit/Finch and process propagation; Ecto uses
synthetic telemetry, not a database. Original SDK snapshots expose boolean and
event/link-counter losses before export. Four HTTP/gRPC captures replay offline
through native storage, compaction, assembly and Tempo export; optional live
checks cover publication/restart/MCP, tenant denial and delivery classifications.
Generic `query-workflows.json` records supported positive-string selector forms,
bounded negation/status-int64 OR/span-duration expressions and remaining
fail-closed grammar gaps, plus
log query shapes. No saved deployment queries or customer telemetry are included.

## Actual Rust SDK/tracing component

[`rust_sdk/`](rust_sdk/README.md) freezes actual API/SDK0.31.0/exporter0.31.1/
tracing-adapter0.32.1 output, a complete aligned lock/feature tree and source
provenance. A real HTTP/W3C hop has remote server/local adapter parenting.
Programmatic-header HTTP, env-header HTTP and gRPC bridging retain booleans,
link tracestate and explicit drop counters. Three actual received payloads replay
through native compaction/assembly/four Tempo exports;13 captured attempts and
producer outcomes disclose whole rejections without implying durable queues or
postcommit recovery. The optional `rust_sdk` live tag stays excluded from ordinary
and S3 integration CI. This is not Kura's whole build/bootstrap/deployed profile.

## Same-span boolean search expressions

[`search_expressions/`](search_expressions/README.md) pins actual public Tempo
2.9 Parquet/TraceQL results for 24 synthetic queries plus 12 duration literal
conditions. Native and independent Elixir replay covers missing/mismatched
negative predicates, exact int64/status OR, equal-precedence grouping,
span-versus-trace duration and full retained context. Local HTTP→S3-stub→HTTP/MCP
checks tenant/budget fences; optional public consumers decode 24 native protobuf
responses. No private dashboard definitions or runtime Go dependency.

## Non-finite trace AnyValues through public Tempo

`tempo-nonfinite-input.protobuf` and `tempo-nonfinite-oracle.json` come from
`produce_tempo_nonfinite.go.txt` running inside **public Tempo v2.9.0's actual
vparquet4 test package**. Six spans cover NaN, positive/negative infinity,
negative zero, 1.0 and a second NaN payload. Each of the five owners has scalar
and nested double values plus literal string contrasts. Actual Parquet/TraceQL
FetchTagValues produces 14 scoped/unscoped, filtered/unfiltered dictionaries.
Its float spellings are `NaN.0`, `+Inf.0`, `-Inf.0`, not OTLP's input spellings.

SHA-256 (also asserted by native-toolchain replay tests):

- Input: `12fa7c9de224f33683faa940b5e565fa0e8ca05c013d7391c272463f6187dd60`.
- Oracle: `dfe25b842ddfa500c55d61869e0a2b4c5960ffb0cd6b52684627617beb2c6b17`.
- Producer: `0abf767eb25ea6fbe15f69a93a3b783b902f6a2fb6580ae319a6596db29beb68`.

Optional upstream reproduction, with the public v2.9.0 source extracted at
`/tmp/pulse-tempo-search/reference` (same public archive provenance as the later
fixtures): copy the producer to
`tempodb/encoding/vparquet4/pulse_nonfinite_test.go`, then run from that tree:

```sh
GOMAXPROCS=2 go test -mod=vendor -p 2 ./tempodb/encoding/vparquet4 \
  -run '^TestPulseNonfinite$' -count=1 -timeout=180s -v
```

Artifacts go to `/tmp/pulse-trace-nonfinite/{input.protobuf,oracle.json}`.
Existing `result-00.protobuf` through `result-13.protobuf`, `export-v1.protobuf`
and `export-v2.protobuf` are independently consumed when present. From Pulse,
produce all 16 native responses without touching checked-in fixtures:

```sh
MIX_ENV=test mix run scripts/trace_nonfinite_conformance.exs /tmp/pulse-trace-nonfinite
```

Then rerun the upstream command with `PULSE_REQUIRE_CONSUMER=1`; it fails unless
all **16** are consumed. Public generated v1/v2 lookup decoders verify every
owner/nested value and signed-zero bits. Equal resource/scope groups can merge
when distinct NaN payloads normalize to one class, so the consumer verifies all
six span IDs rather than requiring one resource group per input batch. NaN
sign/payload/signaling fidelity is not claimed. This producer-plus-consumer run
passed; an initial producer-only run with consumed=0 is not consumer evidence.

Ordinary `mix test` needs only the checked-in files and native toolchain. Replay
covers JSON/protobuf, Parquet/compaction, native/reference assembly/export,
typed conflicts, full dictionaries under order/duplicate changes, and a separate
HTTP gzip → keyed S3 retry → restart → MCP/Tempo integration. The old byte-service
projection conflict test is synthetic, not a captured released-writer artifact.
No SDK/Collector pipeline, deployed client, real provider or capacity acceptance
is established by these fixtures. No upstream implementation is vendored.

## Tempo v1 JSON

`tempo-v1-trace.json` was produced outside Pulse with **public Tempo v2.9.0's
actual generated common/resource/trace types and gogo/protobuf jsonpb v1.3.2**.
A temporary Go wrapper defines only `tempopb.Trace`'s field-1 ResourceSpans list,
decodes the independent official-protoc `protoc-trace-values.protobuf`, marshals
with `jsonpb.Marshaler{}`, and applies the exact first-key `resourceSpans` →
`batches` rename from public `tempopb.MarshalToJSONV1`. No Pulse encoder or
expected-value implementation participates in fixture generation.

- Fixture SHA-256: `6687bcc22b359555d32f52f25790bcaa0cf220d8c724464adcfac882bcc3c5f3`.
- Input wire SHA-256: `345cbbcb764b0e9959735462671d4ed65265b726ed7d75bb98461d637db95234`;
  official OpenTelemetry v1.9.0/libprotoc34.1 provenance is in [OTLP](../otlp/README.md).
- Temporary wrapper SHA-256: `26de7f03462b3d6f4fca452003abd4d818dd67f1349a5c6e980b80257f98dd17`.
- Public `pkg/tempopb/trace_utils.go`: `7f904d6139d77d0b052c9dde54d7e8c64d36ff10dce53a993bfddd0c5894e31a`.
- Public `pkg/tempopb/common/v1/common.pb.go`: `d40f237c837e8ce581314c27bce9ea6041efb2bc0735f70b09b39d74aa0fa605`.
- Public `pkg/tempopb/resource/v1/resource.pb.go`: `04732b6ac7bf55ae0cd9b119d63da80315347b444e9ec886b971d85ca40155f2`.
- Public `pkg/tempopb/trace/v1/trace.pb.go`: `84fe95078bc2ee56d2358ff8ae6ae6ed63100c780c5e30a58ea8841eca963996`.

Sources are from `https://raw.githubusercontent.com/grafana/tempo/v2.9.0/`;
upstream generated code is not vendored into Pulse. Ordinary tests replay the
checked-in JSON/wire with Elixir/Rust only, without Go, protoc, Python, network
or provider dependencies. The signed-zero JSON lexeme is decoded through the
OTLP-specific number adapter, not by changing general JSON semantics. Tests
also assert native/reference protobuf output is byte-exact with the independent
protoc wire and JSON maps match this jsonpb fixture. This proves the serialization
slice, not a full Tempo server/Grafana/deployed-client/capacity acceptance.

### Tempo v2 wrapper

The same independent gogo producer additionally wraps the Trace as field 1 of
`TraceByIDResponse`, using public `tempo.proto`'s exact schema. Optional metrics
and zero/default `COMPLETE` status are omitted. This is the preferred request
shape in public Grafana v12.3.0 `pkg/tsdb/tempo/trace.go` (source SHA-256
`d1ab0795a85327b8fe7263c3b9d703306c49d993418fb55164268d2341871992`),
which uses exact protobuf Accept and falls back to v1 only on HTTP 404.

- `tempo-v2-trace.json`: `7548dc1533417f7ededeca5972e23f4f05ef2ce29f614cf21b6ea1ec7cefcbdc`.
- `tempo-v2-trace.protobuf`: `62fb1ea327bbb347e3180e93d10788d06ffdf57c70453dff185dcc013bb23b87`.
- Extended temporary producer: `4f757a5be715bf1006ac59ec1dd04b7deb471e40296aa480957681196582e8f3`.

This is a serialization/request-contract fixture, not execution of Grafana's
complete datasource frame conversion or a deployed-version comparison.

## Actual Tempo v2.9.0 search engine

`tempo-search-input.protobuf` contains 14 spans in eight traces, with typed
resource strings. `tempo-search-oracle.json` contains eight request/response
cases from **actual Tempo v2.9.0 vParquet4 block creation/read and
`traceql.Engine.ExecuteSearch`**, not a reimplementation or copied response.
The authored producer is `produce_tempo_search.go.txt`; it is placed in upstream
`tempodb/encoding/vparquet4` as `pulse_oracle_test.go` only for optional
regeneration. No upstream generated code is vendored here. Ordinary replay
requires only the native Elixir/Rust toolchain, no Go/compiler/network/provider.

Provenance:

- Public archive: `https://codeload.github.com/grafana/tempo/tar.gz/refs/tags/v2.9.0`.
- Archive SHA-256: `5b652be7d03b3329a5b986fd8678ea4a9c4849adf2966baf19d20eec01046a44`.
- Formatted authored producer SHA-256: `38ec651027b294eb357c1ecce25e7af5cf53571180f820b02c504b1e98e5bbcb`.
- Input protobuf SHA-256: `6b7c1a4ebee57c4bd40986e1ffa0505ff1995842a5af1e4e737f0d13b0cf8632`.
- Oracle JSON SHA-256: `611df661e5137363242cd987cfd4f8c18811b85553a75c531f1e727d13e92a65`.
- Optional generation in the exact public checkout, using its vendored deps:
  `go test -mod=vendor ./tempodb/encoding/vparquet4 -run '^TestPulseOracle$' -count=1 -timeout=180s`.

Cases establish complete-trace overlap (including outside-window matching spans
and envelope-only gaps), full stored starts/durations/root/service summaries,
missing roots, most-recent before limiting, inclusive boundaries, empty
`traces`, final-second exclusion/inclusion and sampled one span with full
`matched: 3`. Provider inspection metrics are removed because physical layout
is not a semantic expected value. Attribute arrays are sorted by key for
comparison. Replay normalizes **only equal-start trace-ID tie order**: upstream
leaves it unspecified, Pulse adds deterministic ID ascending order. These
fixtures do not establish upstream's arbitrary sampling choices for all layouts.

The optional producer consumer-check branch also decoded the Elixir search
protobuf encoder's outputs with the **actual public gogo SearchResponse
unmarshaller**, then compared jsonpb semantic maps with the engine results.
Repeated empty/default traces are protobuf-equivalent; map wire order is not
compared. This check ran locally for all eight cases; the checked-in golden
JSON/input remain independent of it. It is not a mandatory replay dependency.

Neither these fixtures nor lookup fixtures prove Grafana datasource frame
conversion, deployed-version clients, residency, full TraceQL, discovery APIs,
provider/memory capacity or cutover readiness. The separate opt-in search scans
all retained tenant context under explicit cardinality/row/byte limits; tests
must not relabel the old window-local search as Tempo parity.

## Actual Tempo v2.9.0 scoped discovery

`tempo-discovery-input.protobuf` contains two independently written typed spans;
`tempo-discovery-oracle.json` contains 11 **actual vParquet4 `SearchTags` and
`SearchTagValuesV2`** cases for explicit resource/span scopes. Names retain keys
of every type, including bytes. Value cases cover original string/bool/int64,
both signed extremes, Unicode, missing/empty values and matching bool/string
spellings under one key. Expected arrays are sorted for deterministic comparison;
that is not an upstream numerical ordering promise. Provider metrics are omitted.

- Public Tempo archive/version and SHA-256 are the same v2.9.0 source above.
- Authored `produce_tempo_discovery.go.txt` SHA-256:
  `66499476016c0d3772d20d098dee8cacda96e010933984271c00628de2184ae6`.
- Input SHA-256: `c16d4e61dfb1c84f9efe270a2a08b903fd3f10933fff8f71be4981d5e1d7941b`.
- Oracle SHA-256: `fe1b77a7598c7928abcb3b569f8fa5cd8c0d057a2ee1580a7923df3d9dbd9aed`.

Optional regeneration places the authored producer next to the search producer
in upstream `tempodb/encoding/vparquet4` as `pulse_discovery_oracle_test.go`, then
runs `go test -mod=vendor ./tempodb/encoding/vparquet4 -run '^TestPulseDiscoveryOracle$' -count=1 -timeout=180s`.
Its optional public-protobuf-consumer branch also decoded the Elixir v2 names/
values encoder with actual upstream message unmarshallers and compared semantic
responses for all 11 cases. Empty string `value` is omitted as the protobuf
scalar default, not removed from the value set. V1 deliberately flattens types.

Normal replay needs only Elixir/Rust. These are unfiltered scoped name/scalar
subset fixtures, not filtered/time-windowed/default/all/intrinsic discovery,
float/complex value compatibility, Grafana autocomplete frames, deployed clients,
provider/memory capacity or cutover evidence. Unsupported targets fail whole
requests; legacy types never become guesses. No upstream generated code,
external compiler or mandatory Go runtime is added to Pulse.

## Actual Grafana v12.3.0 conversion and stored-status presence

The old `tempo-v?-trace.*` serialization fixtures remain unchanged as historical
raw-export evidence. Actual **Tempo v2.9.0** `traceToParquet` →
`ParquetTraceToTempopbTrace` execution on the official rich input proved default
status is materialized on stored output. `default-status-oracle.json` records
absence on input/presence on output with code 0, plus owner pointers. The authored
`produce_tempo_status.go.txt` runs inside upstream vParquet4 with
`PULSE_FIXTURE_ROOT=<repository> go test -mod=vendor ./tempodb/encoding/vparquet4 -run '^TestPulseDefaultStatus$'`.

`tempo-v?-stored-trace.{json,protobuf}` uses independent public gogo/jsonpb with
only this proven default-status normalization applied to the official input.
Other owner/attribute order and values are preserved. Current native/reference
and public HTTP exports replay against these byte/semantic fixtures. Grafana's
actual converter dereferences status; omitting it panicked before this change.

One-off consumer evidence used unmodified public v12.3.0 `trace_transform.go` and
`protospan_translation.go`. Search frame functions/type declarations were copied
by Go AST source ranges from public `search.go`, without rewriting their bodies.
`extract_grafana_frames.go.txt` is the authored extractor. Only isolated logging
uses the SDK logger instead of Grafana's service logger. Dependencies are pinned
as in Grafana: plugin SDK `v0.281.0`, Tempo
`v1.5.1-0.20250529124718-87c2dc380cec`, gogo `v1.3.2`. The authored
`produce_grafana_frames.go.txt` feeds current Pulse native lookup and eight search
protobuf results to those actual conversion functions and compares frames against
independent normalized lookup and actual Tempo-engine goldens. Only unspecified
equal-start trace ties are normalized. All nine cases passed.

Optional isolated regeneration runs `PULSE_FIXTURE_ROOT=<repository> go test -run '^TestPulseFrames$'`
with the downloaded public conversion source, extracted search transformations,
SDK logger, authored consumer and current result protobufs in `/tmp/pulse-grafana-client`.
No upstream generated source is checked into Pulse and no Go toolchain/network is
required for ordinary Elixir/Rust replay. Checked-in frame goldens establish this
conversion-function slice, **not** full HTTP datasource/browser/autocomplete,
deployed-client, large/shared-ID trace, provider or cutover acceptance. Grafana
itself converts bytes to empty string and times to float milliseconds; its frames
must not be treated as lossless original OTLP.

SHA-256 provenance:

| Artifact | SHA-256 |
| --- | --- |
| Public `trace_transform.go` | `2a2263f663c3242435218a0e43dd9f0ef2ee8003849fa1791a68b622a641fae0` |
| Public `search.go` | `089337ff3197cd108ff641aaad3c9983eb2ab3d7b53cac1d9ce81f5ce83c0dd8` |
| Public `protospan_translation.go` | `775f62822ae51d2d3f93df7d230acd3c6b7479edae9a0a96ab57c03ab5d0d094` |
| `produce_grafana_frames.go.txt` | `aa096dd42701c0eac75983268da832d6a4802a0d58e4ee4b676901f278b4075d` |
| `extract_grafana_frames.go.txt` | `66765927d7db356d216c2b4ef82d2d4f62f61784374d0956e4a9d3f35cc658de` |
| `produce_tempo_status.go.txt` | `969466c779c707d31b77dffefd09eb2f151676be521f46d99eeb9dd5871e9096` |
| `default-status-oracle.json` | `90dfdc4c7d676259ad339dbdb408a0dd9884464adb9eef837edb86ea0f67c835` |
| `tempo-v1-stored-trace.json` | `b69f16d31c06e7f2378272f4affd91b5e27533eb8e9089ab26ac92f8cd95213c` |
| `tempo-v1-stored-trace.protobuf` | `95354dd2b150deccf65768a25579613eae824d85ccfd902a25bc696cc185f049` |
| `tempo-v2-stored-trace.json` | `bff9ef17c175328d3539f3b5f23659d14c0559bca9b9f22d52f1169c137fe9e0` |
| `tempo-v2-stored-trace.protobuf` | `d7430bdbe6471534d9777aa82f830a49307bf50b45874b2dc29ac1fd8767a0f7` |
| `lookup-frame.json` | `714d7bd629d93aaa5c303ddabf946a5dff108af4afa2f87cf61b322b83309523` |
| `search-frames.json` | `d297872bcd86e5cf9e6a93ca12396465e2f0d453922f295ad5ec0d4f606ea047` |

## Actual Tempo filtered value discovery

`tempo-filtered-discovery-input.protobuf` is a three-span/two-resource trace set,
including two sibling spans on one resource with intentionally disjoint filter
attributes. `tempo-filtered-discovery-oracle.json` is produced by actual public
Tempo **v2.9.0 `traceql.Engine.ExecuteTagValues` → vParquet4 `FetchTagValues`**,
not an authored replacement matcher. The authored producer
`produce_tempo_filtered_discovery.go.txt` lives next to the prior authored search
producer in upstream `tempodb/encoding/vparquet4` (it reuses `batch`/`value` helpers).
Optional command: `go test -mod=vendor ./tempodb/encoding/vparquet4 -run '^TestPulseFilteredDiscovery$' -count=1 -timeout=180s`.

Eighteen supported cases establish resource→span, span→resource, same-span AND
(no sibling cross-match), original bool-vs-string distinction, signed int64
extremes, empty/missing values, full regex anchoring/newline dot-all/alternation,
same-target regex and no-match behavior. A nineteenth **unsupported** case proves
Tempo returns a query literal for same-target equality even with impossible
other predicates. Pulse rejects that shortcut explicitly instead of claiming
unproven stored presence. Malformed queries also reject rather than falling back
to unfiltered results. Names, windows, partial editor queries, nonstring filters,
other scopes, hints and structural operators are not covered/supported.

The optional public protobuf-consumer branch also decoded current native-result
Elixir v2 protobuf for all eighteen supported cases and compared actual public
message semantic maps. Normal replay requires Elixir/Rust only. Native/reference
replay reverses/duplicates rows and partitions them into separate objects; HTTP
replay ingests both owners separately and restarts owned manifest caches. Legacy
unknown/corrupt nonmatches, dictionary/output/scan limits, unsupported matching
value types, tenant/auth, v1 flattening and opt-in remain explicit safety tests.
A separate legacy-adapter regression ensures older unfiltered callbacks cannot
silently discard filters: only an explicit filtered callback or the independently
filtered bounded record scan may answer. This does not establish complete
Grafana autocomplete/browser, time/name/default discovery, capacity or cutover.

SHA-256:

- Input: `c3b6d9a720ddb1352fcabbb9eeb71fbd5563955b677011f00f37a3ac7bbb4430`.
- Oracle: `38f9515469e322fb9dc1d366954fac21110371f01372f283068ede61823673be`.
- Authored producer: `96b6fcd8eb30d83f922ae2a9b1b7bc2e510cb2f8e4cfa65f099b49a76bbcbca2`.
- Public source archive/version is the same pinned v2.9.0 archive above.

## Five-scope discovery through actual Tempo Parquet and engine execution

`tempo-scopes-input.protobuf`, `tempo-scopes-oracle.json` and authored
`produce_tempo_scopes.go.txt` extend the same pinned public Tempo v2.9.0
reference with **68 cases / two parents / five explicit attribute scopes**.
The producer builds actual vParquet4 blocks using existing authored `batch` /
`value` helpers from `produce_tempo_search.go.txt`; it invokes `SearchTags`,
`SearchTagValuesV2` and `Engine.ExecuteTagValues` → `FetchTagValues` without
rewriting those upstream bodies. Two events and links under one parent establish
complete parent-filtered unions. Shared keys with different values in every
owner establish isolation; string/int64/bool extremes, empty/absent values,
instrumentation name not becoming an attribute, and impossible filters are covered.
Names include opaque-byte keys; targeted bytes remain unsupported by Pulse and
are exercised as whole-query failures separately. Numeric spellings sort lexically.

The optional producer consumes `/tmp/pulse-tempo-scopes/result-NNN.protobuf`
through actual public `SearchTagsV2Response`/`SearchTagValuesV2Response` decoders.
All 68 current native-result Elixir serializations were compared semantically
with independently executed upstream messages. Go, upstream dependencies and
network access are not required for ordinary Elixir/Rust fixture replay.

Optional reproduction in the pinned upstream tree with the authored helpers:

```sh
go test -mod=vendor ./tempodb/encoding/vparquet4 \
  -run '^TestPulseDiscoveryScopes$' -count=1 -timeout=180s
```

Hashes:
- Input: `2ebb762307e7b3059e05e04c75e034e6bfb304552e0ce96a141490da73ee9d1c`.
- Oracle: `f2047b3107af23be81c3252a9da0898a28482b8ad522fdf3a5cc9b76453e213f`.
- Authored producer: `80e3d462fef4bae694dc3ad0117a1f2c4d699a31d0f801b3728f8982af575722`.

This establishes the explicit attribute subset, not intrinsic/default/unscoped,
nested-predicate/time/name-filtered discovery, full Grafana/browser compatibility,
provider capacity, migration or cutover. Pulse separately enforces 2,000,000
requested-owner-plus-attribute work units per scan attempt before filtering; empty owners count,
attributes count independently, and failed native states cannot return a dictionary.

## Static intrinsic vocabulary and deferred time contracts

`tempo-intrinsics-oracle.json` / `produce_tempo_intrinsics.go.txt` execute the
actual public Tempo v2.9.0 `Querier.SearchTagValuesV2` with only an owned limits
provider and tenant context, **no ingester/backend clients**. Seven canonical
virtual targets return keyword enums or known empty vocabularies with zero
inspected bytes. Names come from actual `GetVirtualIntrinsicValues` (20 entries),
not from executing the frontend HTTP handler. Unknown dynamic aliases return
`nil` from the upstream virtual helper, so Pulse must not invent empty results.
All eight Elixir JSON/protobuf results were consumed by actual public protobuf
decoders and compared with `proto.Equal`; provider metrics are intentionally
omitted. Empty repeated fields are represented as `[]` in Pulse JSON. These are
protocol dictionaries, not stored-value or full TraceQL support evidence.

The optional producer reads `/tmp/pulse-tempo-intrinsics/result-NN.protobuf` when
present. Install it in the pinned upstream `modules/querier` package and run:

```sh
go test -mod=vendor ./modules/querier \
  -run '^TestPulseIntrinsicDiscovery$' -count=1 -timeout=180s
```

- Oracle: `6965837a433969eacc439f6c651a61dcd1ab350f112bd428244d50aab0a4f043`.
- Authored producer: `df329c2e31b29da62ee8a82c1967595bbdb90ac344501de169c16bfc98c0eba0`.

This initial time investigation deliberately did **not** implement time filtering:
`tempo-time-routing-oracle.json` / `produce_tempo_time_routing.go.txt` execute
actual frontend `blockMetasForSearch` over block metadata `[10,21]` in five ranges,
including interior `[15,16]` and inclusive edges. This is whole-block selection,
not per-span filtering. `tempo-time-cache-oracle.json` /
`produce_tempo_time_cache.go.txt` execute the actual ingester tag-value cache-key
function and prove two different request windows share a key. They establish
helper-level behavior only, not a complete HTTP/cached-query execution. Pulse
subsequently implemented explicit immutable-segment envelope routing (capability 7,
below), never strict span-time filtering or cross-window cache-key reuse.

Optional upstream execution in frontend/ingester packages:

```sh
go test -mod=vendor ./modules/frontend -run '^TestPulseDiscoveryBlockTime$' -count=1 -timeout=180s
go test -mod=vendor ./modules/ingester -run '^TestPulseDiscoveryTimeCache$' -count=1 -timeout=180s
```

- Routing oracle: `938eef01325b616dd721c8e67f3dd3f216f9a337511a7479fc131fa3ff77c0ad`.
- Routing producer: `9eaa882799c8c8546e3c3dde28b7226cd246e16f1d0984e1fd4835bb12911418`.
- Cache oracle: `4d9c7ff4bf8a1687035dfa9c4c82772700d1f473649dadb8923a244e750c1198`.
- Cache producer: `b0d32f48ee65bc6b0b41e5d56a2dde6b721be230e6538b6372b95af925323f3a`.

Ordinary fixture replay/tests use Elixir/Rust only. No Go/network/Python probe or
runtime dependency is introduced. None of these fixtures establish deployed
Grafana autocomplete, provider capacity, migration, or cutover readiness.

## Filtered names: raw Tempo evidence and complete conservative hints

`produce_tempo_filtered_names.go.txt` runs actual public Tempo v2.9.0
`Engine.ExecuteTagNames` → vParquet4 `FetchTagNames` over three datasets. It
preserves **75 raw responses**, including promoted-column hints even for false
filters, wrong-type generic attrs, empty promoted strings, absent original
service.name, siblings, five scopes and anchored/dot-all regex cases.

Raw upstream discovery omits shared keys in 11 cases after its pre-join distinct
collector sees them on earlier nonmatching context. Pulse does **not** reproduce
those omissions. The producer independently also runs actual `ExecuteSearch` to
select matching span IDs (proves no fixture sampling/truncation), then reads
requested-owner keys from the **original producer messages**, adding upstream
promotion hints. Each case retains both `response` (raw Tempo) and `complete`
(the independent complete contract); no expected result comes from Pulse.

64 cases are exact, 11 are deliberate complete supersets. The optional actual
public `SearchTagsV2Response` decoder consumed all 75 current native-result
Elixir protobuf responses against **complete**, not raw byte/omission parity.
The contract is name hints, not proof of matching/original key existence:
Tempo's mandatory service.name column can supply a hint without an original
attribute. Value results and unfiltered original-name lookup never do this.
Pulse has fixed standard promotions, not dynamic dedicated-column compatibility.

Replay uses Elixir/Rust only, including native/reference reverse/duplicate/single-
row partitions, missing-type corruption, legacy failure, visible floors, old
value-only adapter fallback, dictionary/escaped-output caps and public HTTP/
S3/cache restart. Go/source/network access is only for optional regeneration.
The producer needs the authored `batch` helper and `tempo-scopes-input.protobuf`:

```sh
PULSE_FIXTURE_ROOT=<pulse-source> go test -mod=vendor ./tempodb/encoding/vparquet4 \
  -run '^TestPulseFilteredNames$' -count=1 -timeout=180s
```

Optional `/tmp/pulse-tempo-names/result-NNN.protobuf` inputs enable the actual
public decoder comparison. Hashes:

- Promoted input: `b1df7099dbdd16290e37ac2421b683c65b8ba454bb5ac037a20d9b9872e35b13`.
- Generic/wrong-type input: `3ba941b1173b3074a1e3dc350ce4f60c51ea840bf4ba494dc4ef868c4a6146f0`.
- No-service input: `0e7d4acc5240ffb2ab421078e936a989671fac7f77f89328cdf09318997fe9f7`.
- Oracle (raw and complete): `ad642c6c44e6554f6e6da64cbea079f46b1ba66d595724b36e972510cb4fa88d`.
- Authored producer: `4da76f100730d321f5d19ee290f18be2b78a483324142dacf871e4439e290acd`.

These are explicit complete-name-hint semantics, not exact upstream omission
parity, time/default/dynamic-column support, full Grafana/browser acceptance,
provider capacity, migration or cutover evidence.

## Default name scope and unscoped-value contract investigation

`produce_tempo_default_names.go.txt` executes actual Tempo v2.9.0 vParquet4
`SearchTags(AttributeScopeNone)` / `Engine.ExecuteTagNames` → `FetchTagNames`
over the three filtered-name datasets above. `tempo-default-names-oracle.json`
retains **15 raw and independently complete cases** (12 exact, three complete
supersets). The complete overlay uses actual ExecuteSearch-matched span IDs and
original producer attributes, never Pulse results. All five stored namespaces
remain separate; required service.name is a hint even unfiltered/absent original.
Static names come from actual `GetVirtualIntrinsicValues`.

Optional public SearchTagsV2Response protobuf decoders consumed all 15 native-
result Elixir serializations against the **complete** dictionary. Reverse,
duplicate and separate-owner partitions replay normally using Elixir/Rust only.
Combined bounds are one 2M work / 5000 scope-name-pair budget, including 20 static
entries even before v1 flattening; they are not five independent query budgets.

The 20-name count above records the original v2.9 fixture, not the current
vocabulary. The [pinned service continuation](tempo_integration/README.md#v2-name-content-tables-and-versioned-static-vocabulary)
independently freezes 25 names from the newer public helper. Current replays
replace only the vocabulary portion of the old complete expectations; original
stored-name and seven static-value oracles remain unchanged. All 25 suggestions
reserve capacity before stored names, including before v1 flattening.

`produce_tempo_default_name_handlers.go.txt` separately executes **actual frontend
HTTP handlers** for 90 cases: all 15 results × v1/v2 × omitted/empty/none scope.
Its backend metadata responses are **owned stubs**, not actual network requests
to Pulse or a running Grafana datasource. The recorded handler oracle establishes
that v2 adds intrinsic suggestions while v1 does not; only metrics are omitted
and scope/key order sorted. It does not establish provider/deployed-client parity.

`produce_tempo_unscoped_values.go.txt` records **12 actual identifier/value cases**
with SearchTagValuesV2 and Engine.ExecuteTagValues→FetchTagValues. Bare `shared`
and `http.method` reject; leading-dot attribute identifiers are required. `.shared`
collects resource/span/instrumentation values, not event/link keys; `.phase`
is empty despite existing event/link phase attrs. Filtered `.service.name` still
returns both `frontend` and `worker` under resource.service.name=worker, showing
that existing same-parent scoped-value behavior is not interchangeable. This
is evidence for continued rejection of **filtered** unscoped values, not permission
to copy ignored filters or union five scopes. The following checkpoint implements
the unfiltered three-owner subset.

In the pinned source tree, optional regeneration/consumer commands are:

```sh
PULSE_FIXTURE_ROOT=<pulse-source> go test -mod=vendor ./tempodb/encoding/vparquet4 \
  -run '^TestPulse(DefaultNames|UnscopedValueContract)$' -count=1 -timeout=180s
go test -mod=vendor ./modules/frontend -run '^TestPulseDefaultNameHandlers$' \
  -count=1 -timeout=180s
```

The frontend producer reads `/tmp/pulse-tempo-default-names/oracle.json`; optional
`result-NN.protobuf` files there enable actual public protobuf consumer checks.
Hashes:

- Default-name oracle: `d72a29397577c847d3abbaffb7b7a2e6f82eb06c2c982713baf7d129392d6287`.
- Default-name producer: `02705939ca47ec1a56d0f54c7fcbddb8a4633c5cd819d4dc62ba999bf2e9761f`.
- Frontend handler oracle: `c5b8635054fe6ad5b7af934baa9ed9fee4c6ee7f9a402a8109ae040d811cf3a2`.
- Frontend producer: `5a2505157bc1061184926cc7cea0aa75840e0c3bb9d58d9d7238f0c24dfbd363`.
- Unscoped-value oracle: `42108f2c413443d6722c041b49b8ac512ba7a576ed4bb3beadeae53f52b8c31d`.
- Unscoped-value producer: `433798a57a0b6fc5d1dd21269505f3340b481c486fb8c868b1246656abeb76a5`.

No Go/Python/network requirement is added to ordinary replay. These fixtures do
not prove full autocomplete, time/dynamic intrinsic, residency, capacity, migration
or cutover acceptance. Discovery capability 5 and all-serving-node upgrades are
required for default names; storage formats do not change.

## Finite floats, unfiltered unscoped values and stored intrinsic strings

`produce_tempo_more_discovery.go.txt` builds 273 official-protobuf parents, each
in an independent trace, with original finite float attrs across five owner scopes,
signed zeros, subnormal/max-finite/exponent edges and deterministic random IEEE
bits. It executes actual Tempo v2.9.0 SearchTagValuesV2 and filtered
ExecuteTagValues→FetchTagValues. The 20 cases establish scalar float dictionaries,
resource/span/instrumentation unscoped unions (not events/links), and seven stored
intrinsic string targets. Absent protobuf strings use effective empty defaults;
event absence does not fabricate a value. Float spelling comes from actual
TraceQL Static.EncodeToString(false), including mandatory .0 for integral fixed
values. No expected result is generated by Pulse.

`produce_tempo_dynamic_filters.go.txt` executes 42 cases (seven targets × six
same-parent resource/span equality/regex selectors). Raw distinct iterators omit
later matching duplicates in 12 cases. Pulse returns complete matching strings;
the producer independently runs actual ExecuteSearch (fixture completeness checked)
and reads fields from original producer messages to record `complete` beside `raw`.
30 cases are exact, 12 complete supersets, not raw omission parity. False predicates
return no field values. This does not authorize the unscoped-value mingled fast
path, which ignores filters and remains rejected for all nonempty queries.

Actual public protobuf decoders consumed **all 62 V2 native-result Elixir wires**.
`produce_tempo_value_envelopes.go.txt` additionally consumed all 62 V1 envelopes,
including empty strings and float spelling/type loss. V1 intentionally uses V2
canonical targets in its string-list envelope; this is **not** executing Tempo's
older target-alias/original-attribute interpretation. Static keyword shortcuts
remain V2-only. The independent decoder establishes wire/envelope fidelity, not
legacy routing parity or a running Grafana datasource.

Ordinary Elixir/Rust tests compare native/reference, reverse/duplicate/partition
inputs, all 273 float spellings, query-aware legacy adapter fallbacks, original
attribute/intrinsic separation, unknown legacy nonmatches, 5001-value rejection,
independent escaped-output overflow and event parent+owner+attribute work limits.
HTTP tests ingest three immutable objects, restart manifest supervision and replay
all 62 cases through JSON/protobuf/V1/V2/auth; footer undercounts cannot return a
partial dictionary. No network, Go, Python or upstream source is needed for normal
replay. Optional regeneration/consumption in the pinned public source tree:

```sh
go test -mod=vendor ./tempodb/encoding/vparquet4 \
  -run '^TestPulse(MoreDiscovery|DynamicFilters|ValueEnvelopes)$' \
  -count=1 -timeout=180s
```

The authored producers reuse `batch`/`value` from the earlier search producer;
outputs and optional `result-NN.protobuf`, `filtered-NN.protobuf` and V1-prefixed
consumer inputs live in `/tmp/pulse-more-discovery`. The envelope consumer requires
those generated wire inputs. Hashes:

- Input: `074a5bc48c218c1f39a4dfdb20d4daa10b258f6e03c574a963d0b7e23ca1615f`.
- 20-case oracle: `7f6a2e6992d78b124865f1fe5bf4690c83348998a308cd75977f617822c77b4d`.
- 273-spelling oracle: `17c48bbcc0aa1d6908c439e284e39ac8e4f4c1764f952100a895b44f8f5fc15b`.
- Main producer: `48d62b3f5cf087227e737a464d70c4d58d019fd71523fe2d27ea949d9b8d8df0`.
- 42 raw/complete filter cases: `f65ce3b464b100b6fd9f2cf330ae560e1993d1b62961cdca922d54d5307f844d`.
- Filter producer: `eaba6f2388f6b5e9bfc71f02ddbc3a68451cba535fe4a54ef71547ccaf206d98`.
- V1 envelope consumer: `11548a9a422a703b29b1f9c809a8d4ccbed0450548005c5b5b0d837e018245b7`.

This slice introduced capability 6; current serving applications require capability 7 / matching artifacts. Scope-none
root aliases and filtered values, root/duration intrinsic values,
complex type discovery, deployed-client/capacity/cutover acceptance remain pending.
Unfiltered values promise original attrs, never invented missing service.name
column defaults. There is no storage-format or mutable coordination change.

## Block-oriented discovery windows, including the subsecond HTTP edge

Capability 7 reads actual Parquet timestamp columns, computes retention-visible
min-start/max-end envelopes and selects whole sources, not per-span start windows.
All raw header rows/provider bytes still charge; selected sources replay the same
immutable binary locally, no extra GET or cross-window dictionary cache. Old/flat
adapters reject without explicit /7 support; default seeds/all scopes use that
single mode. Native/reference tests preserve boundaries, duplicate/reverse sources,
gaps, long spans, retention reshaping, selected/unselected legacy, malformed
headers/physical schema and one million excluded rows; public S3 tests cover both
layouts/restarts/auth/formats/underreported footers. This is not indexed I/O.

`produce_tempo_windowed_discovery.go.txt` builds official protobuf with two traces
at 10..11s and 20..21s and actually executes public vParquet4 SearchTagValuesV2.
It composes these returned values with the earlier actual frontend five-case
routing helper on owned `[10,21]` metadata. The block test helper itself passes
zero timing headers, so this composition is **not** proof of automatic block
metadata construction or full frontend→provider HTTP execution.

A source-only review found the fractional boundary absent from those five cases.
`produce_tempo_span_time.go.txt` actually calls distributor `startEndFromSpan` on
20.5..20.9s; the result is seconds 20..20. `produce_tempo_subsecond_routing.go.txt`
feeds those actual headers through `BlockMeta.ObjectAdded` and frontend
`blockMetasForSearch` in five ranges. `end=20` includes that source. The public
Parquet reader in `produce_tempo_windowed_subsecond.go.txt` supplies its actual
`fractional` value. **Discovery HTTP end seconds expand to the final nanosecond;
MCP nanoseconds and trace metadata search remain exact.** This avoids incorrectly
copying the distinct search-end rule into block-oriented discovery.

Optional execution in the pinned v2.9.0 source, with authored prior `batch` helper:

```sh
go test -mod=vendor ./modules/distributor -run '^TestPulseSpanTime$' -count=1
go test -mod=vendor ./modules/frontend -run '^TestPulseSubsecondDiscovery$' -count=1
PULSE_FIXTURE_ROOT=<pulse-source> go test -mod=vendor ./tempodb/encoding/vparquet4 \
  -run '^TestPulseWindowed(Discovery|SubsecondValues)$' -count=1
```

Output is `/tmp/pulse-windowed-discovery`; optional `TestPulseWindowedEnvelopes`
consumes native-result Elixir wires `result-{1,2}-NN.protobuf` and
`subsecond-result-{1,2}-NN.protobuf`. This establishes response-envelope fidelity,
not a deployed datasource, identical physical layout, ingestion bridge or capacity.
Compaction/layout can broaden context and introduce previously excluded legacy
uncertainty; excluded payload metadata is not integrity-scrubbed. Ordinary
Elixir/Rust replay has no Go/network/Python requirement. Hashes:

- Whole input: `da102fd775b53baca6f069a841bcba89e8c25911d0761832c34e93ba2cbb151f`.
- Whole oracle: `f1071cade0054b90976f6bdee652dd3939205357d9ae18ddbc035213f87b9e2c`.
- Whole producer: `4d20efeabdc8c866084cc316badf7ba20ed229d3a0a2c0a6ea640f9281789a7a`.
- Distributor oracle: `11d5eace551faabb794a7461bf739e14e362715fd346f54886948cd906eee29f`.
- Distributor producer: `a5bb0b5e5e1d8ca281a7a0fb83c98a653c7458afc2278534925fdf2806a9e788`.
- Subsecond routing oracle: `88cd706e2880b5c8523c5446062099a397dd2f030501ec81cef7ea5bcfdacc33`.
- Subsecond routing producer: `7d8dbc2f27c540f6cdf63245df43fdd1089da1d248ad5f9337b54a71beffc462`.
- Subsecond input: `f11ec3ed00c2393ea4aff2e8584651eefab92865a9bf6c45cb80032edde75e15`.
- Subsecond oracle: `e10dade7668b5014135258b9585870e56e8c7bdd46bc0dc49e689511dfd06bc1`.
- Subsecond value/consumer producer: `765317e1cc6f6bf0a03072751186ccc2c3637a28f7812c5c013ad8955eb36812`.

## Filtered unscoped values: selected-parent completeness, not ignored-filter parity

`produce_tempo_filtered_unscoped.go.txt` runs inside the pinned public Tempo
v2.9.0 `tempodb/encoding/vparquet4` test package. It reads the checked-in earlier
273-IEEE-value input, adds distinct string/int64/bool/float owners and excluded
event/link values, then writes `tempo-filtered-unscoped-input.protobuf` and the
36-case `tempo-filtered-unscoped-oracle.json`. Ordinary replay uses Elixir/Rust,
not Go/network/Python. The optional producer uses `PULSE_FIXTURE_ROOT` for input.

Each case records actual `ExecuteTagValues` raw results **separately** from a
complete three-owner dictionary over **actual `ExecuteSearch` selected parent
span IDs** and the original producer protobuf attributes. Counts prove the small
fixture was not clipped. Resource/span/instrumentation are unioned on that parent;
events/links, field-name defaults, inferred original types and name hints are not.
18/36 raw and complete dictionaries differ: upstream's mingled path ignores the
filter, so this is deliberately a complete filtered extension, **not upstream
ignored-filter, frontend, physical block layout or deployed-client parity**.
Two matching targeted complex cases require whole-query rejection; the other 34
cases preserve original types, exact large int64 and shortest-roundtrip floats.

Current native-result Elixir v1/v2 encoders wrote 68 messages. The actual public
`SearchTagValuesResponse`/`SearchTagValuesV2Response` decoders consumed all 68 with
`PULSE_REQUIRE_CONSUMER=1`, which fails if a successful-case wire is missing:

```sh
ROOT="$PWD"
cd "$TEMPO_V290_SOURCE"
PULSE_FIXTURE_ROOT="$ROOT" PULSE_REQUIRE_CONSUMER=1 \
  go test -mod=vendor ./tempodb/encoding/vparquet4 \
    -run '^TestPulseFilteredUnscoped$' -count=1 -timeout=180s -v
```

The producer must first be copied into that upstream package as a `_test.go`
file. Native/reference tests assert complete sets over reversed/repeated/split
inputs, old callback fencing, selected whole-source windows, unknown/corrupt
nonmatches, 2M summed requested-owner work before filtering and 5001 dictionary
rejection. HTTP tests ingest gzip into three S3 objects, restart the manifest
owner, and exercise both JSON/protobuf versions plus MCP windows/auth. These are
owned local transport/provider tests, not live separate-node/provider acceptance.

SHA-256, pinned in replay tests:

- input: `346a89d43a4bdd349aa873e1afa418bc13db3ff282a9612df531ee0a5fbd4349`
- oracle: `9b70e78fe1076fc9a16d74483bea1ef0f11b925c873661af7d775a1176d089a3`
- producer: `44d01467815cbbec2e45247edbdc93852f2cd9679c559b25a9930fb5aad40e23`

## Event-time offsets: integer nanoseconds and complete parent-filtered extension

`produce_tempo_event_times.go.txt` builds 280 original protobuf parents with
unique IDs, zero/one/multiple/absent events, before-start/default-zero times,
exact int64 source-domain endpoints and deterministic signed-range offsets.
It runs the actual public Tempo v2.9.0 Parquet/TraceQL engine, recording raw
`ExecuteTagValues` results separately from complete offsets for **actual
`ExecuteSearch` selected parent IDs** and original event/parent timestamps.
The small fixture verifies sampled-span counts to exclude clipping. Ordinary
replay uses Elixir/Rust only; Go/network/upstream tools are optional provenance.

Important actual evidence: the **unfiltered** column path emits type **`int`**
with signed decimal **nanoseconds**, not Go duration strings. Pulse preserves
that wire type. Seven cases comprise one exact unfiltered dictionary, five
complete filtered supersets versus actual empty upstream filtered responses,
and one empty parent selection. This is explicitly a complete parent-filtered
extension, **not upstream filtered behavior**, deployed Grafana, physical block
layout or provider-capacity parity. Source times stay nonnegative int64, so
subtraction is exact without wrap; timestamp0 may yield a negative offset (minus the parent start),
while absent events never invent a default offset. Ingest writes the protobuf
default as explicit stored0; a missing stored timestamp fails even on nonmatches,
never reconstructed as0. Offsets are high-cardinality and broad dictionaries can
exceed5000; filters/window narrowing help without guaranteed capacity. V1 is a canonical-target
string-list envelope, not historical alias semantics.

Current native-result Elixir encoders wrote **14 v1/v2 messages**. The actual
public protobuf response decoders consumed all 14. `PULSE_REQUIRE_CONSUMER=1`
requires every successful-case wire; initial oracle generation does not claim
consumer coverage when wires do not yet exist:

```sh
ROOT="$PWD"
cd "$TEMPO_V290_SOURCE"
PULSE_FIXTURE_ROOT="$ROOT" PULSE_REQUIRE_CONSUMER=1 \
  go test -mod=vendor ./tempodb/encoding/vparquet4 \
    -run '^TestPulseEventTimes$' -count=1 -timeout=180s -v
```

Copy the optional producer into that upstream test package as `_test.go` first.
Owned local HTTP tests ingest gzip into four S3 sources, restart manifest ownership,
exercise v1/v2 JSON/protobuf, parent filters, MCP exact-nanosecond/HTTP whole-second
windows, auth and raw-footer budget rejection. Native/reference tests reverse,
repeat/split/coalesce source layouts, validate requested corrupt event times even
on nonmatches, retain effective protobuf default0, reject legacy metadata and
5001 values, and exhaust 2M parent+event+attr work before impossible predicates.
Old stored-string callbacks are fenced by a separate event-time /4/reference;
windowed execution requires dedicated /6, never old window /7. Whole source
routing concerns parent span envelopes, not event times; compaction may broaden
values and excluded payloads are deliberately not integrity-scrubbed.

Pinned SHA-256:

- input: `64123afc8f82af3d0d65c11c250810e1cc2e0bfc302695f64f8f353eda5c2ab4`
- oracle: `0df574bf6a30d9bc24b21552f7bc362d36411144f2cf42ec9e4535010b26e49e`
- producer: `792adcde45bf95d357cf9f61e8c7a858dc3fce658ca30f410a67b2d76544effe`

## Complete retained root-name and root-service dictionaries

`produce_tempo_roots.go.txt` runs inside the pinned public Tempo2.9.0 source above
as `tempodb/encoding/vparquet4/pulse_roots_test.go`. It writes eight traces/18
resource-span owners to `/tmp/pulse-root-discovery/input.protobuf` and records44
queries over rootName/trace:rootName/rootServiceName/trace:rootService in
`oracle.json`. Each case records raw actual public `ExecuteTagValues` output.
Independent complete expectations use actual `ExecuteSearch` selected trace IDs
and original protobuf fields, not Pulse-generated expected values. Bounded fixture
search rejects clipped spansets. The normal trace's child is at20s and its root
at1s to exercise cross-source root recovery outside candidate source windows.

There are22 successful dictionaries, all exact for the exercised raw block
results, and22 deliberately stricter root conflict/unknown rejections. Cases
cover identical rich copies, missing roots, absent original service, two equal-valued
but distinct root IDs, child_of links, empty original strings and the same ID
classified as both root and non-root. Upstream's empty/default/arbitrary choices
for unsafe roots are recorded, not adopted. This is not generalized distinct-
iterator/dedicated-column/physical-layout or running datasource acceptance.

Pinned files:

| File | SHA-256 |
|---|---|
| `tempo-roots-input.protobuf` | `ae50a9bc5b06df9eb7e3fde68dae7b2f689ef1898e2f8f70712570b354598706` |
| `tempo-roots-oracle.json` | `179753f73b0f3151e7d4320ae9ceb2a058eceb1bb1cecfab33c77b6fea9b3edf` |
| `produce_tempo_roots.go.txt` | `a569af4d9ad7046b59a6994d4a79e8c4b5432440c16dc124c556270fc01d8783` |

The optional native encoder writes successful-case v1/v2 protobuf messages to
`/tmp/pulse-root-discovery/value-NN-vV.protobuf`. With
`PULSE_REQUIRE_CONSUMER=1`, the producer requires every successful message and
passes it through actual public Tempo decoders. **44 current native-result messages
were consumed**, including empty dictionaries and known empty strings. Initial
producer execution without the messages reports0, never consumer coverage.

```sh
cd /tmp/pulse-tempo-search/reference
PULSE_REQUIRE_CONSUMER=1 GOMAXPROCS=2 go test -mod=vendor -p 2 \
  ./tempodb/encoding/vparquet4 -run '^TestPulseRoots$' -count=1 -timeout=180s -v
```

Normal replay in `tempo_roots_test.exs` uses only checked-in fixtures and Elixir/Rust,
checks all three hashes and native/reference outputs over split/reversed/repeated
sources, full retained root recovery, unknown/corrupt context and independent
input/work/dictionary/escaped-output limits. Owned transport tests use real local
HTTP, gzip,18 S3 objects and supervision restart before both wire versions/MCP.
No runtime Go, network or Python dependency, deployed-client/provider/load/cutover
claim or new persisted format is introduced. Discovery10 matching app/native
artifacts are required on every serving participant.

## Complete retained trace-duration values and conditional wire typing

`produce_tempo_trace_durations.go.txt` runs inside the pinned public Tempo2.9.0
source above as `tempodb/encoding/vparquet4/pulse_trace_durations_test.go`.
It writes280 traces/560 original resource-span owners and records six queries
for canonical `trace:duration`. Each case records actual public block/engine
`ExecuteTagValues` output. Complete expectations independently group original
protobuf fields for actual `ExecuteSearch` selected trace IDs, rejecting clipped
fixture spansets, before max-end/min-start. All six complete sets exactly match
the exercised raw results. No Pulse code supplies expected values.

**Wire type depends on filters:** `{}` yields type int, exact decimal nanoseconds;
nonempty original-string parent filters yield type duration, Go duration strings.
The fixture covers zero, nanos/micros/millis/seconds, >2^53, near signed-int64
endpoints, a1s-to20s cross-source trace and deliberately missing/multiple roots.
Those roots do not prevent retained envelope measurements. This is not exporter
completeness; ongoing ingestion/retention can change the duration.

`tempo-trace-duration-format-oracle.json` additionally records1047 positive
boundary/randomized signed-int64 `time.Duration.String` spellings, including
max int64, hours/minutes and U+00B5. Rust and Elixir replay it independently using
integer math only; an Elixir assertion checks1µs bytes explicitly. No extra JSON
or duration library is introduced by the native test.

| File | SHA-256 |
|---|---|
| `tempo-trace-durations-input.protobuf` | `49937e32dd2b5c270b36d6f404dc22a94b5dbbdea7cba6e27671cd9440b5bba9` |
| `tempo-trace-durations-oracle.json` | `18bced978169149a8d6a59df5bd0c72a649f84e28f7efc1f56db8c30c63402fb` |
| `tempo-trace-duration-format-oracle.json` | `c95f19eba3e475a8d9dc4a96ce0171ad91df6f348af918afae9da0e7150a15e9` |
| `produce_tempo_trace_durations.go.txt` | `497b35d0c505683af78abde85dbbc6a107c2dd2e23989009c6c8077adfc07806` |

Optional producer outputs live under `/tmp/pulse-trace-durations/`. The native
encoder writes six cases × two protocol versions as `value-NN-vV.protobuf`.
With `PULSE_REQUIRE_CONSUMER=1`, every successful wire must exist and actual
public protobuf decoders compare them with the independently expected values.
**12 current native messages were consumed**. Initial producer execution without
wire files reports0 and is not consumer evidence.

```sh
cd /tmp/pulse-tempo-search/reference
PULSE_REQUIRE_CONSUMER=1 GOMAXPROCS=2 go test -mod=vendor -p 2 \
  ./tempodb/encoding/vparquet4 -run '^TestPulseTraceDurations$' -count=1 -timeout=180s -v
```

`tempo_trace_durations_test.exs` replays checked-in fixtures with Elixir/Rust only,
including layout/repetition/retention changes, whole-request legacy/corruption,
2M work,5000/5001 dictionaries, callback and native mode fencing. Owned transport
covers gzip→six S3 sources→restart→both wire versions/MCP, plus exactly two provider
GETs for out-of-window context. Native modes require matching discovery11 artifacts;
old root/string/window callbacks cannot silently approximate them. Static empty
duration/span:duration/traceDuration vocabulary is unchanged. These are scoped
fixtures, not physical-layout, deployed-client/provider/load/cutover acceptance.
No ordinary Go/network/Python test dependency or storage format change.

## Parquet compatibility fixtures

These four small files were written using Arrow/Parquet 54 directly, **not**
Pulse's trace encoder. `native/pulse_codec/examples/trace_metadata_fixtures.rs`
has the complete logical payload and schema. It writes the existing nine search/
payload columns, with either no typed envelope or deliberately malformed metadata.

| File | Expected behavior | SHA-256 |
| --- | --- | --- |
| `trace-legacy.parquet` | Readable; metadata unknown, never inferred from `AP8=` | `45000cacabce44191bedc22c97b3dd2263a8bbefe81eef8638e8c972eac2a9a1` |
| `trace-invalid-type.parquet` | Reject array-valued envelope | `741e701553858a53d6d29ee2363a14c8cb1397e511c7e3ef9a38cb3d17ae741b` |
| `trace-invalid-version.parquet` | Reject unknown envelope version | `1ef170e752919d81147a4d78176bc6c28c229fc90870e98331ca81d3f3aaa3bc` |
| `trace-invalid-value.parquet` | Reject noncanonical byte encoding in typed value | `971e113e71e179b587c5cc8d0a1838744c10bd0219f0dd852f07d09a2fa47760` |

Tests replay checked-in files through record decoding, native query state and
compaction. Malformed typed data must fail closed and poison query state rather
than return a partial result. Legacy/rich projection-equal copies are duplicates
with unknown legacy metadata, not proven typed conflicts.

Optional regeneration with the existing project toolchain:

```sh
cargo run --manifest-path native/pulse_codec/Cargo.toml \
  --example trace_metadata_fixtures -- /tmp/trace-fixtures
```

Compare logical behavior rather than assuming byte-identical Parquet output
across writer upgrades. Do not derive expectations from the decoder under test.
No external SDK, Python, network, provider or production access is required for
ordinary replay. These are compatibility fixtures, not capacity/Tempo acceptance.
