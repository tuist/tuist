# Tempo replacement workstream

## Acceptance target

This application-specific track is compatibility evidence, not Pulse's product
boundary. Generic full public-protocol breadth is tracked in
[protocol breadth](protocol-breadth.md). The latest independent metrics increment
retains remote-write 2.0 source starts and advances the metric artifact tuple to
`{2,2,1,1,1}`; trace `{2,1,3,4,12}` is unchanged. See the generic workstream for
the current object-store tuple and fleet-wide upgrade requirements.
Older metric tuples below describe historical checkpoints.

Replace Tempo for Tuist's tracing workload without weakening acknowledged-write durability, tenant isolation, bounded admission, or query completeness. API compatibility and native MCP diagnosis are separate acceptance surfaces. Passing synthetic tests is not a cutover approval.

## Required increments

1. **Rust-resident queries and fewer copies.** Keep cross-object candidates, filtering, ordering and response construction in Rust. Avoid per-span Erlang maps and metadata re-encoding on the S3/MCP path. Wrap immutable Erlang input binaries with process-independent owners, never borrowed lifetime extensions. Bound retained native bytes and final response bytes independently. Projection must happen before Erlang expansion. Reference-adapter parity and full-metadata multi-object load tests gate this increment.
2. **Native compaction and bounded discovery.** Merge Arrow/Parquet without routing every span through BEAM. Reuse conditional manifest replacement and durable retirement semantics, including lost-response recovery, competing compactors, concurrent appends, reader retries and restart-safe cleanup. A bounded active manifest plus durable partition discovery must replace indefinite whole-tenant manifest rewriting; compaction alone does not bound permanent idempotency tombstones.
3. **Trace assembly and indexes.** Whole-trace lookup across partitions, deterministic duplicate/conflict handling, parent/child graph construction, events/links and typed byte fidelity. Immutable trace-ID postings with conservative legacy fallback. Define oversized-trace and pagination/completeness behavior, not silent clipping.
4. **Operational lifecycle.** Opt-in retention with an explicit acknowledged-data deletion policy, conditional publication before deletion, grace periods and recovery. Object-store lifecycle rules are not a substitute. Default retention remains disabled. Shared paged roots bound metadata over the configured event-time window; committed floors reject expired retries. Retain-forever flat scopes keep permanent compaction tombstones. Root formats and retry policy must remain shared across signals.
5. **Query breadth.** TraceQL selection and structural operators, regex and tag discovery, trace-level metadata, bounded search pagination and aggregations where required by real consumers. Reject unsupported grammar explicitly. Native bounded regex/predicates and graph evaluation, Elixir orchestration.
6. **Compatibility.** Tempo trace lookup/search/tag APIs and protobuf/JSON envelopes exercised against independent clients and Grafana's Tempo datasource. OTLP/gRPC directly or an explicitly validated Collector/Alloy deployment; SDK defaults, partial success, retries and large batches tested. Do not call a collector-dependent deployment transparent without verifying it.
7. **Cutover evidence.** Actual Tuist -> collector -> Pulse shadow delivery, production-shaped cardinality/volume, cold restart, fault injection and sustained ingest through multiple compaction/retention cycles. Compare trace identities, metadata, latency and failure behavior with the authoritative destination. External deployment changes require human authorization.

## Latest OTel checkpoint: Rust SDK/tracing component

The previously paused Rust producer now builds and runs locally with actual
API/SDK/proto 0.31.0, exporter 0.31.1 and tracing-opentelemetry 0.32.1. Its full lock
has 143 dependency identities matching the read-only Kura inventory, including
source/checksum, plus the fixture package. The initially newer hyper/h2/http/
futures-executor graph was replaced, not claimed equivalent. This is a component
profile, not Kura's application/feature graph/bootstrap or deployed exporter.

A real bounded reqwest→TCP HTTP/W3C hop produces a client root, remotely parented
server and locally parented tracing adapter. Direct programmatic-header HTTP,
env-only HTTP and gRPC→Collector 0.137→gzip HTTP share IDs across isolated tenants,
publish through native S3-stub/Parquet/CAS and survive manifest-supervision restart.
Exact MCP assembly, HTTP/MCP retained-context search and cross-tenant denial
agree with reference results. The Rust profile preserves booleans, link
tracestate and explicit event/link dropped-attribute counts of 1; no upstream loss
is inferred away. Actual HTTP 401/whole 413 and pre-publication injected 429/503
each happen once per transport, store zero and yield the expected HTTP/gRPC exporter
errors. One gzip/non-gzip pair distinguishes Collector forwarding from retries.
Malformed env-header entries omit authorization; env tokens override valid
programmatic headers. Untrusted incoming gRPC tenant metadata stores nothing.

Batching is an explicit flush profile, queue/batch 64 with scheduled delay 24h
beyond the owned 30s child await, not Kura defaults or queue/capacity acceptance.
It avoids racing the default five-second scheduler before all three spans end. The
no-proxy/no-redirect/3s blocking reqwest client is an intentional no-TLS/no-HTTP2
component policy, not Kura's default client. Full application/Alloy/TLS,
queue/crash/partial-success/ambiguous publication, provider/node/capacity/restore
and cutover remain unaccepted. Source/embedded-input/lock and binary hashes are
not compiler/dependency attestation; use freshly prepared trusted executables.

Three SDK-derived protobuf requests, three actual delivered payloads, original
SpanData snapshots, 13 attempts/producer outcomes and the resolved feature tree
are SHA-pinned for offline native compaction/assembly/four-format Tempo replay.
Final 15-file index `291f6ec34190591b423bc8520ec5087d48c1e610f18eef962977145fa0ecef56`
replaces initial 3f15... and intermediate 7264... deliberately after explicit
batching/shared constants and source-line changes; original corpus/inputs remain
`/tmp/pulse-rust-sdk/{first-freeze,batch-freeze}`.
The `rust_sdk` tag is excluded from ordinary/S3 CI and missing explicit tools
fail. No SDK/Collector/Go build/run/probe/network is needed for ordinary replay.
See [operator contract](../docs/trace-rust-clients.md) and
[fixture provenance](../test/fixtures/traces/rust_sdk/README.md).

Final assistant-owned validation: bounded `mix precommit --max-cases 4` passes
**1246 tests, 1 skipped, 37 excluded** in 70.4s; replay3 passes 14 offline SDK
fidelity/provenance tests. Rust live6 passes all 13 producer profiles plus four
embedded-input checks; Go regression1 passes one test and Elixir regression1
passes both profile tests. Integration-exclusion1 passes one sentinel/excludes
all four external-client tests with tools unset even under `PULSE_INTEGRATION=1`.
Explicit missing-tools1 fails with the expected environment error, not skip.
Locked/offline producer build5 and strict all-target Clippy3 pass. Fresh native
codec/store suites pass 88/5 tests and both strict all-target Clippy checks
(`--locked --offline`, bounded build/test concurrency). Compile1, Credo3
(340 files/no issues), format/diff checks pass. Source-only review closes
all RS findings separately from assistant-owned execution. Low-concurrency local
passes and variable runtimes are not capacity evidence; older high-parallelism
failures remain unresolved. Logs and prior failures stay `/tmp/pulse-rust-sdk/`.
No Pulse runtime/native ABI, ingest/storage format or
budget changes: traces remain `{2,1,3,4,12}`. No Tuist edit/build, commit,
deployment, production query or provider/node exercise.

## Latest query checkpoint: observed same-span expression gaps closed

The three saved-workflow query gaps from the previous checkpoint are now
implemented generically for default-off retained-context `GET /api/search` and
MCP `search_trace_metadata`: original-string `!=`/`!~`, original-int64 comparisons,
status enum conditions, own-span duration comparisons, and same-parent boolean
AND/OR/groups. All4 sampled saved TraceQL targets parse after representative
substitution, including the3 previously rejected forms. This is syntax evidence,
not exact Grafana interpolation or production-data/residency acceptance.

Actual public Tempo2.9 Parquet/TraceQL execution supplies24 synthetic search
oracles and12 duration-literal conditions, not handwritten expected results.
Native and independent Elixir execution agree, including missing/type-mismatched
negative predicates, no float coercion, exact int64 above2^53, equal-precedence
left-associative AND/OR, same-parent conditions, full retained roots/service stats
and span-versus-trace duration. Go-compatible fractional rounding fixes the
initial rational parser's boundary discrepancy without weakening comparisons.
All24 native protobuf responses also decode exactly with public Tempo's actual
SearchResponse consumer. See [operator semantics](../docs/trace-query-expressions.md)
and [pinned corpus](../test/fixtures/traces/search_expressions/README.md).

New expressions never reach old string callbacks: explicit callback or bounded
complete reference with sentinel row. Native compilation independently validates
types/stack/budgets; storage stays Rust-resident on S3. Expressions disable the
service/ID planner and admit full retained scope, preserving1024/32MiB/1M input,
65,536 candidates and16MiB result limits. A separate20M-work ceiling per attempt
charges all resource/span owners/attrs/instructions before filtering in both
passes. No DNF expansion, sampling/truncation or inferred original types.
Candidate/context replay reuses exact captured bytes with no extra GETs. Native
candidate/non-sampled rows no longer copy matching attribute values.

Search capability4 requires tuple `{2,1,3,4,12}` across serving app/native pairs;
there is no stored-format/idempotency change from these operators. Discovery and
window-local search retain the previous narrower grammar, and full TraceQL,
JSON-versus-Go quoting differences, float/boolean literals, structural operators,
whole application/Kura/Alloy, provider/node/load/restore/cutover acceptance remain
open. No Pulse SDK, Tuist edit, commit or deployment.

Final assistant-owned whole-tree validation: `ERL_FLAGS='+S 4:4' mix precommit
--max-cases 4` passes **1241 tests,1 skipped,36 excluded** in67.3s. Focused5 passes14
expression/workflow tests; focused4 passes37 including existing/planner tests.
Codec Rust passes88 tests; all-target strict Clippy3 passes. Final live2 rerun
passes both actual Elixir profiles in14.1s, including expression HTTP searches
against their stored data after the no-copy fixes. Final encode2/required public
consumer2 accepts24/24 native protobuf results and12 literal conditions. Strict
compile,Credo3 (338 files/no issues),format/diff checks pass. All4 actual saved
trace query targets parse locally. Source-only review closes
SX-L1–L4 and token/Unicode nits, with no open actionable slice finding. Execution
and public-reference provenance are assistant-owned, not reviewer-run evidence.
Logs/checkpoints stay in `/tmp/pulse-trace-expressions/`; these low-concurrency
local passes are not capacity or full-replacement acceptance.

## Latest OTel checkpoint: existing Erlang/Elixir clients and workload gaps

This is the preceding client checkpoint; its three query gaps are superseded by
the expression checkpoint above. Its SDK/transport limitations still apply.

Two isolated profiles now exercise actual API1.5/SDK1.7/exporter1.10 clients,
grpcbox0.18/0.17.1, Phoenix/Bandit instrumentation, Finch git0.3/Hex0.2 and
process-propagator0.3. Real loopback Req/Finch→Bandit/Phoenix requests carry W3C
context into an actual task. Ecto instrumentation receives synthetic telemetry,
not database execution; custom background-job instrumentation remains untested.
The legacy profile uses upstream Bandit1.11.1 rather than the application's
fork: its pinned fork checkout failed, so full application graphs/bootstrap are
not claimed. No Tuist files or deployment configuration changed.

Direct gzip HTTP and gRPC→core Collector0.137→gzip HTTP both reach the owned S3
HTTP stub/native Parquet/CAS, then manifest restart, MCP lookup, cross-tenant
denial and basic/filtered retained metadata search. Original SDK snapshots expose
exporter boolean→string conversion, event/link dropped-attribute counters1→0,
and synthesized link flags256. Strict received/stored/compacted/export parity is
separate from those upstream losses. SDK request snapshots are message re-encoding,
not literal gRPC transport capture or independent upstream oracles.

Actual HTTP401/whole-request413 store nothing and callback:error; injected429
also callback:error without replay. Injected503+Retry-After retries identical
compressed bytes through recorded OTP httpc, then publishes5. Flush returns:ok
even for callback:error. This is controlled pre-publication evidence, not durable
queues, arbitrary retries, postcommit ambiguity or exactly-once delivery.

Read-only Atlas inventory expanded beyond provisioned files:57 dashboard entries
and21 datasources are metadata, not complete usage evidence. One sampled v2
workload dashboard has272 targets:262 PromQL,4 LogQL,4 TraceQL and2 Grafana-side
SQL expressions. Its saved `group` misleadingly says Prometheus for logs/traces;
classification must inspect datasource/model/query type. All262 PromQL and4
LogQL shapes parse after representative variable substitution, not numerical or
residency acceptance. Of4 TraceQL shapes, positive resource/span string regex
AND was accepted at that checkpoint;3 then required unsupported negated regex,
intrinsic/numeric OR or duration comparisons. The new expression checkpoint above
implements these; remaining unsupported grammar still rejects whole. Raw saved definitions remain private under
`/tmp/pulse-elixir-sdk/`, not public docs/fixtures. Configured trace/log/metric,
service-map/profile/streaming links are not proof of use or support.

Four frozen client/transport captures plus source/locks are SHA-pinned and replay
offline through compaction/assembly/four Tempo formats. Dedicated `elixir_sdk`
opt-in remains excluded from ordinary/S3 CI; live setup checks the prepared
producer sources and locks against the frozen copies. See
[operator evidence](../docs/trace-elixir-clients.md) and
[fixture provenance](../test/fixtures/traces/elixir_sdk/README.md).
Final assistant-owned validation:live16 passes2 profile tests/12 SDK subprocesses
in16.8s, with prepared-source/lock identity checks, isolated child BEAM environment,
all-five-completion barrier, stored signed-zero bit checks, four positive
transports and controlled negatives. Replay2 passes7 offline/workflow tests;
full `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4` passes **1229 tests,
1 skipped,36 excluded** in89.3s (precommit1,exit0). Compile1,format-final1,Credo2
and diff checks pass. Go-regression1 live bridge passes after the shared helper
change. Combined CI-exclusion2 sentinel passes1/excludes3 without any SDK/Collector
tool variables, even with `PULSE_INTEGRATION=1`.

Source-only reviewer closes EL-M1 and EL-L1–L5. Prepared `_build` identity remains
a documented trusted-input limitation, not cryptographic artifact attestation;
fresh external preparation is required. SDK snapshots are explicitly exporter
message re-encoding through internal conversion/boot APIs. Upstream exporter tag
and immutable peeled commit sources match both built Hex encoder file SHAs.
Adding the completion observer and child-environment isolation deliberately
regenerated the unreleased synthetic corpus, not fidelity assertions: original
index68fdfb87…/23 files are preserved in `/tmp/pulse-elixir-sdk/first-freeze`, final
index4cc29459… pins24 sources/locks/captures. The fixture README and test pin the
full SHA. All logs and read-only inventory details remain under
`/tmp/pulse-elixir-sdk/`. Live15's79.2s versus live16's16.8s is variable local
timing, not performance/capacity acceptance; prior high-parallelism failures
remain unresolved. No production/native ABI/limits change; current traces
remain `{2,1,3,3,12}`. Rust producer stays paused/unvalidated with its source-review
findings at that historical checkpoint; the later Rust component checkpoint
above supersedes that pause, not application acceptance. No provider/node/
capacity/cutover acceptance, deployment, Tuist edit or commit.

## Prior OTel checkpoint: actual SDK/Collector loopback bridge

At that historical checkpoint, artifacts were traces **`{2,1,3,3,12}`**, metrics `{1,1,1,1,1}`,
object store `{1,1,1}`. No receiver, runtime/dependency or native ABI change.

An actual Go SDK1.43 producer now exercises W3C propagation over a real local
HTTP hop between two services, then gRPC→core Collector0.137→gzip HTTP→Pulse.
Owned runtime-scoped HTTP S3 stub/manifest CAS, supervision restart and MCP reads
verify stored data. Alpha/beta share IDs but have distinct resources/tokens;
unauthorized access fails and incoming gRPC tenant metadata cannot override
static exporter headers. Collector receivers are trusted loopback pipelines,
not an authenticated public multi-tenant gateway.

ReadOnlySpan snapshots and deterministically marshaled SDK request messages
(not literal gRPC packet captures) reconcile flags, typed owners, schemas,
events/links/drops, >2^53 int64, signed zero and nonfinite classes against actual
Collector requests and stored records. Frozen data/source SHA assertions replay
without Go/Collector/network/probes; three ordinary fidelity tests include native
Parquet compaction, assembly and all four Tempo export formats. A fourth owned-
Agent regression proves evidence exhaustion fails without losing history or
rearming injected retries. Optional subprocesses
are owned/bounded with isolated child environments; a dedicated collector_bridge
tag is always excluded from normal/S3 integration CI. Explicit opt-in requires
real directly built binaries. Port handoff race and Unix direct-pid cleanup
remain documented fail-closed limits.

Two upstream losses are captured rather than hidden: SDK1.43 omits link
tracestate before gRPC export; Collector0.137 mixed-resource batch splitting can
lose both schema URLs on a split span. The passing local profile removes all
Collector processors/queues and preserves tiny SDK batches. A frozen split
counterexample proves exact schema loss without teaching Pulse to invent it.
Neither all versions nor an actual Alloy/deployment/default-SDK profile is
accepted. [Operator contract](../docs/trace-collector-bridge.md) replaces old
unqualified batch-processor advice.

Controlled pre-publication429/503 retry unchanged messages; actual401/413 are
permanent in this profile. A malformed public-protobuf probe (not SDK output)
produces one accepted/one rejected span, HTTP200partial and no batch replay;
upstream gRPC is OK with empty partial_success, not the backend rejection count.
SDK background export failures are separate from flush results. No exactly-once,
postcommit lost-response, real overload/provider, persistent queue/crash or
trace-wide atomicity claim.

Validation: final live13 explicit-tag run passes; ordinary replay4 has four
passing tests. Final `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4` passes
**1222 tests, 1 skipped, 34 excluded** in 98.3s (precommit4, exit0). Strict compile,
Credo6, format checks and diff checks pass. A temporary integration-tag sentinel
plus the bridge file proves CI's `PULSE_INTEGRATION=1 ... --only integration`
executes the sentinel and excludes the bridge without tool paths (exit0).
An isolated all-excluded filter probe exits1 because --only executed no tests,
not a binary lookup. Source reviewer closed BR-M1/L1/L3/L4/L5 and accepted
L2/L6 documented scope limits. Final CB-L1/L2/L3 and wording findings also close:
Agent limit sentinel preserves state, SDK build-info SHA is pinned, upstream path/
tag is cited, and example retry defaults are distinct from the tested budget.
Review is source-only, not execution evidence. Local logs:
`/tmp/pulse-collector-bridge/{live13,replay4,precommit4,ci-exclusion2,credo6}.log`;
`source-finalcheck3.md` records the final review. Earlier live iterations found
the schema loss and corrected harness capture/API assertions. Credo4 failed on
new helper nesting; a private pure reservation helper fixes it (Credo5/6 pass).
No production fidelity/limits were weakened. No prior high-parallelism failure
is resolved by this lower-concurrency pass.

Next at that checkpoint: actual required Rust/Elixir SDKs and deployment/Alloy/TLS processing,
queue/restart/ambiguous delivery, meaningful batches/provider/cardinality/native
pressure, retained query/large-trace compatibility and authorized shadow/cutover
acceptance. No deployment, real provider/node exercise, production changes,
commit or replacement approval.

## Prior OTel checkpoint: non-finite trace class fidelity

Current trace artifacts require **`{2,1,3,3,12}`** (metadata, span search, export,
retained-context search, discovery); metric `{1,1,1,1,1}` and object-store
`{1,1,1}` requirements remain unchanged. The prior checkpoint tuples below are
historical, not current rollout requirements.

OTLP/HTTP JSON/protobuf now accept NaN and positive/negative infinity at all five
attribute owners and nested AnyValues. Typed envelopes retain doubleValue,
projection strings remain compatibility-only, and native/reference validation,
Parquet/compaction, stored-trace assembly, JSON/protobuf export and dictionaries
agree. Export canonicalizes quiet NaN; no sign/payload/signaling fidelity claim.
Finite bits/signed zero retain their contract. Actual Tempo v2.9 Parquet/TraceQL
produced 14 dictionary cases over six spans (including a distinct NaN payload),
and its public decoders consumed 14 native discovery protobufs plus two native
v1/v2 lookup exports. Frozen inputs/oracle/producer SHA assertions and an optional
native fixture emitter make this replayable without Go/Python/network in ordinary
tests. These are protocol fixtures, not SDK/Collector or deployed-client proof.

Service promotion requires original stringValue, not projection string type;
new byte-service inputs no longer promote base64. Drain those keyed retries
because normalized fingerprints change. Old/new copies of an identical
byte-service span conflict permanently at assembly/lookup even with equal typed
owners; do not evade by key rotation/unkeyed resend/deletion, and do not claim
automatic repair. Old stored projections remain unchanged. Native/reference
regressions simulate that boundary (not a historical writer artifact), while
raw NaN projection regex matches are explicitly distinct from typed original-string
selectors. All application/native participants must upgrade before new writes;
startup guards cannot fence old serving pools.

[Operator OTel gap matrix](../docs/trace-otel-compatibility.md) now distinguishes:
actual SDK→Collector/Alloy→HTTP delivery/propagation/retry acceptance; optional
direct gRPC only if the bridge is insufficient; ignored resource entity refs and
rejected duplicate singular wire-message forms if actual producers require them;
5,000-span/16MiB whole-lookup bounds/shared client-server-ID semantics; deployed
Tempo/Grafana clients; cold/provider/separate-node/cardinality/recovery capacity.
Collection, spanmetrics/servicegraph generation and sampling stay external.
Live pipeline/shadow/load/fault/restore/deployment/cutover require authorization.

Source-only independent review closed NF-M1–M3/NF-L1–L2; execution provenance is
ours. Validation is recorded in the Grafana replacement checkpoint. Nothing
committed or deployed; full replacement remains unaccepted.

## Prior discovery checkpoint: complete retained trace durations

Discovery **11**, search3, current tuple **`{1,1,2,3,11}`**, adds only canonical
`trace:duration` stored values. Select trace IDs through original-string same-parent
resource/span equality/anchored-regex AND predicates, then recover all retained
candidate spans before max-end/min-start. Source windows do not clip that context.
No new persisted format, mutable authority, dynamic column index or deployment.

**Actual upstream wire evidence changes with the query:** nil/empty/`{}` emits
`int` exact decimal nanoseconds; supported nonempty parent predicates emit
`duration` Go-style strings (`µs` U+00B5), both lexically sorted/coalesced. V1 uses
the corresponding spellings. Preserve this distinction rather than claim stable
units/types across filters; clients must separate caches. Static v2 duration /
span:duration / traceDuration remain empty vocabularies, not stored data. No
floating-point conversion, numeric-order promise or ms clamping.

**Different from strict root lookup:** a complete retained envelope exists without
roots or with conflicting roots; those do not fail duration. Live ingestion can
widen it and retention can shorten it, including expired rows still physically
present in captured sources. It is not exporter completeness, full span-ID conflict
validation or a completeness watermark. Legacy/corrupt nonmatches and invalid
source times still fail whole. Coverage explicitly says complete-retained duration;
window coverage says source candidates with complete trace context, not trace time.

Whole retained S3 input still must fit1024 objects/32MiB compressed/1M raw rows
regardless of window/matches; exact captured binaries replay with no extra GET or
service/ID planner, header/body count agreement and independent1M replay rows.
Noncandidate JSON is not scrubbed while all Arrow sources can decode.65,536
candidate groups;80-byte summary charge per trace within16MiB charged bookkeeping
(not total native memory, container/Arrow/input overhead remains separate).
Work is2 resource/span owners+attrs before predicates and once on additional
candidate context. Events/links are not requested owners, but envelopes validate.
5000 values/independent1MiB dictionary/result ceilings fail whole. Broad nearly
unique nanosecond dictionaries commonly422; filters/windows offer no capacity
or provider/work avoidance guarantee. Root work/error semantics remain unchanged.

Dedicated duration /3 + windowed /5 callbacks fence old root/string/window support;
shared bounded reference uses a sentinel and flat adapters reject windows. Separate
native constructor/finish enforce mode identity; mismatched calls reject. New-trace
insertion charges once without reusing the matched/sample counter. Upgrade/drain
every serving app/native participant; local startup cannot fence old pooled nodes.

Pinned actual public Tempo2.9 producer executes six cases over280 traces/560 spans;
all complete expectations exactly match actual raw block/engine values for this
fixture. Expected retained bounds come from original fields of actual engine-
selected trace IDs, including rootless/multi-root, zero, >2^53 and int64 endpoints.
**12 current native v1/v2 protobuf messages** were consumed by actual public
Tempo decoders.1047 Go boundary/randomized formatter cases replay byte-exactly
in Rust and Elixir, including explicit U+00B5 bytes. No provenance/deployed client,
physical block layout/provider/capacity/cutover inference from these scoped runs.

Owned HTTP exercises gzip→six S3 sources→supervision restart→v1/v2 JSON/protobuf,
MCP exact windows/auth/unsupported predicates, plus two single-owner sources whose
candidate's context is outside the window and requires exactly two data GETs.
Native/reference tests cover reversed/split/repeated sources, retention narrowing,
missing/ambiguous roots, legacy/corrupt nonmatches,2M prefilter work,5000 successes/
5001 rejections for both wire forms, callback/constructor/finish fences and actual
footer limits even for empty/outside-window results. Two old HTTP rejection tests
now use trace:unsupported rather than the newly supported trace:duration.

Validation: `mix precommit --max-cases 4` passed **1169 tests,1 skipped,33 excluded**;
focused46 passed, Rust73 passed,12 actual public native-result consumers passed.
Warnings-as-errors compile, strict all-target Clippy, strict Credo (311 files/
4411 modules/functions), Mix/Cargo format, diff checks and Helm lint/render with
synthetic values passed. Source-only recheck closed TD-L1..4 and the bookkeeping
note, with no Critical/High/Medium. Final Low about missing spaces in operator
duration prose was corrected and source-only recheck confirmed no open findings
at any severity; no source behavior changed after validation. Reviewer ran nothing and did not establish producer/client/provider provenance;
final pass reread the main duration section/tests rather than every abbreviated
configuration/deployment/querying/MCP/chart/index/AGENTS summary. No commit or
production/deployment/load/fault/restore/cutover action.

## Prior discovery checkpoint: complete retained root names and services

Discovery **10**, search3, tuple **`{1,1,2,3,10}`** adds canonical rootName /
trace:rootName and rootServiceName / trace:rootService string dictionaries. Parent
resource/span string filters select trace IDs, then exact admitted binaries replay
all retained candidate context, including roots outside the predicate/source window.
No new authority, format, storage mutation or exporter-completeness claim.

A root is parentless without an original child_of link. Distinct root IDs,
differing root name/service tuples or contradictory same-ID root classification
fail whole409. Missing retained roots or original string root service fail
trace_root_unknown409, never default/infer/skip. Known empty strings remain values.
Root proof does not validate every unrelated span-ID/export conflict.

**Explicit product decision:** strict whole-request completeness takes priority
over always-available autocomplete. In-flight children-before-root, retention-floor
straddles and multi-root instrumentation can make broad/recent dictionaries
unusable. Older windows/parent filters help without a watermark or guarantee.
No skip-incomplete mode is introduced; this is default-off, not transparent parity.

All retained S3 sources must fit **1024 inputs / 32MiB compressed / 1M actual rows**
regardless of windows/matches. No metadata-search service/ID planner. Replay
reuses captured bytes without another GET, decodes all Arrow sources, cross-checks
body/header rows even for excluded sources, and separately caps replay1M rows.
Noncandidate JSON metadata is not an integrity scrub. Native candidate IDs cap
65,536, root bookkeeping16MiB;2M resource/span/link owners+attrs charge before
parent predicates and once on additional context. 5000 values and independent1MiB
dictionary/result limits reject whole. These are per-query/instance safety bounds,
not node/provider/deployment capacity evidence.

New root /4 or bounded complete reference plus dedicated windowed-root /6 fence
old span-local string/window callbacks. Flat references reject windows; root
fallback asks for a sentinel record and rejects excess before assembly, even
for an older max_records-truncating adapter. Memory itself errors rather than
truncating. Upgrade/drain every serving app/native participant; local startup
checks cannot fence old instances in a shared pool.

Actual public Tempo2.9 producer records44 cases over4 targets:22 successful
complete dictionaries exactly match the exercised raw block dictionaries;
22 deliberately reject missing/ambiguous roots or missing original root service
instead of upstream empty/default/arbitrary choices. Expected values use actual
engine-selected trace IDs and original protobuf fields. **44 current native-result
v1/v2 protobuf messages** were consumed by actual public decoders. Fixtures include
identical copies, multiple equal-valued root IDs, contradictory same-ID parenting,
child_of links, missing service, empty names/services and a root outside its child's
source window. Source layout/deployed-client/provider/capacity parity is not claimed.

Owned transport exercises gzip→18 single-owner S3 sources→manifest supervision
restart→both JSON/protobuf versions, MCP/exact windows, auth, unsupported predicates,
409 errors and truthful coverage. Native/reference tests cover reversed/split/
repeated layouts, context outside windows/floor, legacy/corrupt nonmatches,
2M prefilter work,32MiB captured input,1024 inputs,5001 values and escaped-output
1MiB overflow. Raw actual-footer limits apply even to empty/outside-window queries.

Validation: `mix precommit --max-cases 4` passed **1162 tests,1 skipped,33 excluded**.
Focused root5 passed again after adding the successful5000-entry boundary check;
public consumers44 passed; Rust72 passed. Warnings-as-errors compile, strict
all-target Clippy, strict Credo (308 files/4374 modules/functions), Mix/Cargo format,
diff checks and Helm lint/render with synthetic values passed. Two earlier full
runs hit existing test timing issues: membership-scope monitor observed noproc
(focused retry passed; unchanged), then Cartesian work-budget fixture hit its
1s default deadline. That fixture now uses an explicit30s test-only deadline to
separate work exhaustion from scheduler load; production deadlines are unchanged.
Final source-only review found no remaining Critical/High/Medium/Low in reviewed
source/root docs/MCP/chart/AGENTS/leading checkpoint. Reviewer ran nothing and
verified no producer/client/provider provenance; the three short configuration/
deployment/querying summaries were not reread in that final pass.
No production/deployment/load/fault/restore/cutover action or commit is authorized.

## Prior discovery checkpoint: exact integer event-time offsets

Discovery **9**, search3, tuple **`{1,1,2,3,9}`** adds only canonical
`event:timeSinceStart`. Values are exact signed **int nanoseconds**, not duration
strings: each source event time minus its own parent source start, both validated
nonnegative int64, so no overflow. Actual unfiltered public Tempo value discovery
established this integer wire type before implementation closure. Source default0
is normalized at ingest into an **explicit stored timestamp0**; missing stored
fields now fail rather than fabricate defaults. Null/noninteger/exponent/negative/
out-of-range times fail even on nonmatching parents. No events invent no values.
Negative offsets remain valid. Lexical, not numeric order; equal offsets coalesce
in both versions, v1 is canonical strings not historical alias/provenance parity.

Bounded same-parent resource/span string AND filters collect complete offsets,
versus actual upstream filtered event-time omission (empty in five nonempty
fixture cases). No intrinsic/event predicates, hints or malformed fallbacks.
Parent+all events+attrs spend work before filtering, independent 2M/1M/5000/1MiB
bounds remain. Nanosecond offsets are high-cardinality: broad retained dictionaries
commonly fail422 rather than sample/truncate. Selective parent filters and narrow
whole-source windows can help but never guarantee success; compaction can broaden
values and filters do not reduce requested work or raw provider/header costs.
Windows route parent start/end source envelopes, not event timestamps.

New explicit event-time /4 or bounded reference and dedicated windowed-event-time
/6 fence old string /4/window /7 callbacks. Missing support rejects; excluded
payloads are not integrity-scrubbed. Existing8 filtered-none contracts remain.
All serving app/native participants need matching9; local startup is no old-node
fence. No new format, mutable authority or inferred legacy types.

Actual public Tempo v2.9.0 Parquet/engine producer: **280 parents/seven cases**,
**one exact unfiltered/five complete filtered supersets/one empty**, independently
using actual engine-selected parent IDs and original times. **14 current native
public v1/v2 protobuf messages** consumed. Checked-in producer/input/oracle/hash
replay requires only Elixir/Rust; optional Go tooling is not runtime dependency.
Native/reference reverse/repeated/split/coalesced sources, explicit0/no-events,
unknown/corrupt nonmatches, 2M prefilter work,5001 dictionary and old-adapter fencing
are covered. Owned gzip→four S3 objects→restart→both JSON/protobuf versions/MCP/
window/auth/footer paths passed. First21 focused, then35. After source-review
missing-stored-field tightening, full `mix precommit --max-cases 4` again passed:
**1156 passed,1 skipped,33 excluded**. Rust **71 passed**, strict all-target Clippy,
strict Credo305files/4313functions, warnings-as-errors test compile, Mix/Cargo format,
diff check and synthetic Helm lint/render clean. All **14 current native protobuf
messages were regenerated and consumed again after the missing-field change**.

Source-only reviewer found no Critical/High/Medium and three Lows: missing stored
field defaulting now fails (only explicit normalized0 is valid), high-cardinality
warning and MCP/docs contract are addressed. Final source-only check closes all
three Lows with no Critical/High/Medium; its one wording nit (negative offset, not
negative parent start) is corrected in docs/fixture notes. Reviewer executed nothing
and did not independently verify fixtures/consumers or deployed writers.
No deployment, production/provider acceptance, separate-node capacity or cutover.

## Discovery checkpoint: complete parent-filtered unscoped values

Discovery capability **8**, search3, tuple **`{1,1,2,3,8}`** now supports resource/
span original-string AND equality/regex parent filters for unscoped three-owner
values. Resource/span/instrumentation values retain original types; no event/link,
static hints or absent-field defaults. Predicates select one parent, then all its
three requested owners contribute; each returned value need not match the literal.
Same-key resource/span equality remains deliberately unsupported (regex workaround),
not inability to compute other-owner values. Reserved root aliases, malformed/
partial/hinted/nonstring/nested/intrinsic predicates still reject.

Every selected visible parent validates before filters, and all three requested
owners+attrs spend shared 2M work before matching, even absent target/empty owner.
Matching targeted complex values reject whole; known nonmatches can omit them,
never hide corrupt/legacy metadata. Dictionaries keep 5000 typed entries and
independent1MiB retained/output budgets. Window routing/raw footer/provider bounds
are unchanged and do not use the service/ID metadata-search optimizer.

Old none/3 callbacks never receive queries. Explicit query-aware none/4 or bounded
reference is required. Windowed filtered-none requires NEW dedicated /6; the old
windowed /7 cannot receive this mode and missing support rejects. Other windows,
default names and static vocabulary retain their contracts. All serving app/native
participants require matching capability8; local startup cannot fence old nodes.

Independent actual Tempo v2.9.0 public engine selected parent IDs plus original
protobuf three-owner fields establish **36 cases**, not the upstream mingled path
that ignores queries. **18 raw/complete differences**, **34 successes/two matching
complex rejections**, and **68 actual public v1/v2 protobuf decoder messages**.
This is a disclosed complete extension, not frontend/deployed/physical-layout parity.
Checked-in producer/input/oracle replay uses only Elixir/Rust; optional Go remains
provenance tooling, not runtime dependency. Tests cover native/reference reversed/
repeated/split sources, owner budgets under impossible predicates, legacy/corrupt
nonmatches, 5001 entries, old callbacks/window fencing, gzip→three S3 objects→
restart→JSON/protobuf v1/v2/MCP/auth/window paths. Initial old capability6 HTTP
rejection assertion was updated to the retained same-key-equality rejection.

Capability8 full `mix precommit --max-cases 4`: **1148 passed,1 skipped,33 excluded**.
Initial focused **27 passed**; the subsequent 41-test run found only that obsolete
HTTP assertion, now corrected and covered by the full run. Rust **70 passed**,
all-target Clippy clean, strict Credo clean, Helm lint/render passed, diff/format
checks clean. Source-only review found no Critical/High/Medium and three documentation/
contract-clarity Lows, addressed with description/docs/regex-workaround language.
Reviewer did not execute or independently verify oracle/consumer provenance.
No commits, external deployment, production/provider acceptance or cutover.

## Planning checkpoint: publication-proven service candidates and complete ID context

Complete-context search now requires capability **3** (discovery remains **7**),
artifact tuple **`{1,1,2,3,7}`**. Exact resource.service.name equality can use an
optional native publication proof plus complete service sets to omit first-pass
sources. Every row must be rich, strict core/payload-column-valid and represent
original string service.name in its promoted column. Legacy/unknown sources read;
no projected-type inference. Encoder rejects bad core before PUT; compaction
reproves all input bytes and returns distinct trace_projection_invalid on mismatch,
never inventing metadata or repairing/dropping rows. The trace encoder/ingest are
unreleased/untracked in this worktree, not deployed-historical writer evidence.

Seal freezes matching-or-legacy-unknown IDs and replays exact first-pass bytes.
Complete ID-prefix/canonical-bloom context recovery then uses the same captured
manifest/floor, without service/time clipping, before overlap/top-k. No second GET
for captured bytes. Native 2M probe exhaustion reads all remaining sources;
unknown summaries also read. Actual GETs/footer rows/bytes stay cumulatively capped
at 1024 / 1M / 32MiB, including across retry; both native passes cap 1M. Catalog
metadata/page/heap limits can bind before hard 8192 refs. This is not guaranteed
catalog/capacity, representative posting/index or deployed-client acceptance.
Pruned objects are not an integrity scrub; corrupt read context fails even when
noncandidate, and new potential IDs after seal poison rather than clip/expand.

Focused validation **42 passed**, Rust **70 passed**, strict all-target Clippy and
strict Credo clean at the focused checkpoint. Full capability7/search3 precommit
**1140 passed,1 skipped,33 excluded**. An initial run found the new native unit
file used ExUnit.Case; it now uses the required owned Pulse.Test.Case template.
The final source-only Low on permanent projection errors is addressed: trace
controller maps trace_projection_invalid to400 without retry-after, exercised
through owned failing storage in JSON/protobuf, keyed requests. Tests include >1024 cold catalog with two actual GETs and earlier
other-service/gap context, cumulative context budgets/footer lies, spent retry,
legacy uncertainty, missing/malformed proof fallback, original service disagreement,
bool service types, duplicate-key rejection, zero rows, hash/bloom parity, exact
2M fallback, poisoned seal and layout/coalescing equality with unplanned reference.
The initial stricter-encoder test run exposed uppercase span IDs in the codec fuzz
fixture; now it generates spec-valid lowercase IDs, without relaxing production.

Source-only review found no Critical/High, one conditional Medium about newly
strict compaction and six Lows. Distinct projection errors plus offline coherent
backup/recovery guidance address the offered Medium mitigation; earliest invalid
flat groups can still stall compaction, now explicitly documented. Review did not
execute tests/provenance or prove historical producers. Generic proof-violation
500 diagnostics have no dedicated self-metric yet. No deployment/production access,
cutover or commits. All serving apps/native artifacts still require upgrade/drain;
local startup cannot fence old nodes.

## Discovery checkpoint: scalar, stored strings and block-oriented windows

The current default-off discovery capability is **7**, startup tuple
**`{1,1,2,2,7}`**. All serving app/native participants must upgrade/drain; startup
only checks the local artifact. No production access/deployment or format change.

Four additional contracts are implemented with independent native/reference and
actual public v2.9.0 producer evidence: unfiltered resource/span/instrumentation
unscoped values (not event/link); finite float typed text including signed zeros
and Go/TraceQL exponent rules; seven effective stored intrinsic strings; bounded
same-parent resource/span string filters on those strings. Nonempty unscoped
filters still reject the upstream fast path that silently ignores them. V1 uses
canonical v2 target semantics in a legacy string-list envelope, not old alias
interpretation. Actual 273 IEEE spellings/20 scalar cases/42 filtered-string cases
were executed. Filtered results are 30 exact and 12 deliberate complete supersets,
independently derived from engine-selected IDs and producer fields, not Pulse.
Public protobuf consumers accepted 62 native-result Elixir messages in **each**
version (124 wires). Capability-6 baseline: **1113 passed,1 skipped,33 excluded**;
first full attempt had only an obsolete intrinsic-name rejection assertion, fixed
with exact effective values, not a production behavior rollback.

Paired positive HTTP uint32 seconds / MCP int64 nanoseconds now select complete
**retention-visible immutable source envelopes**, not span-start points. Actual
start/end columns establish min-start/max-end; expired starts cannot widen them.
All raw source rows/provider costs remain charged, selected sources replay the
same admitted binary locally without another GET or cross-window dictionary cache.
Flat adapters reject absent explicit window-aware /7 execution. Every selected
visible row validates before attribute predicates; unselected payloads are not
integrity-scrubbed. Layout/compaction/coalescing can broaden values and merge legacy
uncertainty into the selected context. This is not immutable indexed I/O planning.

An independent review identified the subsecond HTTP edge. Actual upstream
`startEndFromSpan`, `BlockMeta.ObjectAdded` and frontend routing confirm that
`20.5s..20.9s` occupies second-20 metadata and selects for discovery `end=20`.
HTTP upper bounds now include the entire final second; **MCP nanoseconds and
trace metadata search keep exact ends**. New public Parquet value fixtures compose
with five whole-second and five subsecond routing cases; these remain helper/block
execution, not full HTTP datasource/provider or identical physical-layout evidence.
Native tests additionally cover gap context, partition-sensitive results, retention
reshaping, long ends, legacy outside/inside selected sources, malformed headers,
one million excluded rows, poison/consume and old-adapter refusal. HTTP→S3→restart
checks cover both layouts, JSON/protobuf/v1/v2, auth and raw-footer undercounts.

Validation: `mix precommit --max-cases 4` **1123 passed,1 skipped,33 excluded**;
**69 Rust tests**; all-target Clippy with warnings denied; strict Credo (299 files,
4232 modules/functions) clean; explicit warning-free test compile; Mix/Cargo
format checks and diff checks clean; Helm synthetic-values lint/render passed
(icon recommendation only). Final focused four-file run **40 passed**. Actual
public protobuf consumers accepted all ten whole/subsecond window cases in each
of v1/v2 (20 messages). First focused attempt retained one obsolete static-time
rejection assertion; replaced with valid-pair success, retaining partial-pair
rejection and no-I/O assertions. Source-only review closed WD-M1/WD-L1..6;
reviewers did not execute or independently verify producers/decoders/provenance.
The two final Low doc refinements now specify required trace schema and avoid
claiming compaction publishes known corrupt payloads. Everything stays uncommitted.

Remaining contracts include filtered-unscoped values without silent omission,
root/duration/event-time intrinsic values, complex/dynamic dedicated-column parity,
indexed planning, large/shared-ID traces and real datasource/browser/load/residency/
operational acceptance. These additions do not establish full Tempo replacement.

## Next implementation order for the captured Tuist workload

The storage/assembly foundation is present. The next work is the consumer contract,
not another trace persistence adapter. The captured registry dashboard uses:

```traceql
{ resource.service.namespace = "tuist" && resource.service.name = "tuist-registry" && resource.deployment.environment =~ "${environment:regex}" } with (most_recent=true)
```

Keep this a generic contract; Tuist's values are a conformance workload, not runtime
special cases. Dashboard variable expansion happens on the client. Pulse must reject
unexpanded macros rather than guessing their values.

1. **Typed attribute fidelity and bounded Tempo v1/v2 lookup serialization implemented.**
   New spans keep discriminated, ordered AnyValues in `otlp` through all attribute
   owners, Parquet, native compaction/query/assembly. Official v1.9.0 protoc fixtures
   and independent Arrow legacy/corruption fixtures exercise type identity, exact
   int64, signed zero and mixed reads. Full normalized budgets are proven before
   append; keyed semantic rejections never become subsets. Legacy strings remain
   unknown, with `metadata_unknown_span_ids` distinct from proven conflicts.
   `query_traces` predicates remain query-projection predicates, not strict OTLP
   type predicates; the newer distinct-trace search uses original string types. Upgrade all readers/writers/compactors, drain legacy keyed retries
   and ship matching native artifacts before rich writes. This does not implement
   full TraceQL, deployed SDK/client parity or a migration; experimental lookup
   envelopes are implemented separately in step 3.
2. **Native window search and opt-in stored-trace-wide Tempo-shaped search implemented.**
   `search_traces` parses bounded resource/span original-string equality/regex AND
   selectors and optional `most_recent=true`. All predicates must match one span.
   Native grouping scans all source-start-window spans, including nonmatching
   context, before distinct-trace limits and deterministic earliest-window-start
   descending/ID ascending ordering. Counts preserve duplicates. The hard 65,536
   all-window trace-group cap is explicit (`:trace_group_limit`), not hidden by
   small result limits or restrictive predicates. Native scans cap 1,000,000 rows;
   whole shared scans/page gathering, actual footer counts and retries remain
   charged. Legacy types fail searches, even on nonmatches; compaction cannot
   upgrade them. See the operator window-sizing/history guidance in `docs/traces.md`.
   This window-local envelope intentionally lacks Tempo trace-wide start/duration,
   root metadata and sampled spansets. A separate experimental `search_trace_metadata`
   and `/api/search` now aggregates every retained tenant span before inclusive
   trace-envelope overlap, full stored roots/duration/service stats, most-recent
   ordering/limits and sampled spansets. It requires explicit `most_recent=true`.
   Actual public Tempo v2.9.0 vParquet4 block creation/fetch and TraceQL engine
   execution produced eight cases/14 spans covering outside-window matches,
   envelope-only gaps, missing roots, ordering before limit, sample count vs
   matched count, empty responses and exact-second boundaries. Equal-start
   ordering is normalized only for Pulse's deterministic ID tie extension.
   JSON and admitted bounded-result protobuf work; the actual public gogo decoder
   also round-tripped the Elixir search encoder against all eight semantic maps.
   These are executable subset/serializer results, not deployed Grafana frames.
   Search is default-off (`PULSE_TEMPO_SEARCH_ENABLED`/`tempoSearch.enabled`):
   All retained rows still consume 1,000,000-row ceilings regardless of request
   window or selector. Native candidate-first replay spends 65,536-ID capacity
   on matching-or-legacy-unknown traces only, recovering complete context from
   up to 1024 exact owned source binaries / 32 MiB compressed input without extra
   provider GETs or snapshot changes. A smaller window cannot solve the current planning cost;
   representative indexed planning, memory/provider capacity and discovery/full
   language/client semantics remain gates. Legacy overlapping uncertainty and
   known ambiguous roots/unrepresentable durations fail, never guess/wrap.
   Public Tempo v2.9.0 `pkg/traceql/engine.go` was inspected (SHA-256
   `e648f937c577d5f40ac247f06e68f68e41495a17925384ce0b041aef9fd6d348`);
   its conversion takes trace-wide metadata from stored spansets. This is source
   context only; the subsequent independently executed block/engine fixtures
   provide limited semantic evidence but still not deployed-version/client parity. A span top-k shortcut remains unsafe. Indexes/two-phase native
   planning may be needed for real windows beyond the conservative group cap.
3. **Serve and verify the remaining required Tempo client APIs.** Experimental
   v1/v2 exact-ID lookup is implemented with independent official-protoc and public
   Tempo v2.9.0 jsonpb serialization fixtures plus HTTP/S3/auth/restart/budget tests.
   Public Grafana v12.3.0 source requests v2 protobuf with v1-on-404 fallback; both
   paths now exist. Actual v12.3.0 conversion functions also executed successfully
   for one rich lookup/eight search cases against current Pulse protobuf and
   independent goldens. Full HTTP datasource/browser/autocomplete/deployed-version acceptance,
   shared client/server-ID rewriting and oversized-trace handling remain gates.
   Lookup deduplicates only identical rich copies; legacy or known disagreements
   fail 409. Start/end are validated uint32-second hints, never span filters.
   A subsequent default-off unfiltered resource/span tag-name/scalar-value slice
   now implements v1/v2 JSON/protobuf plus MCP discovery. It requires explicit
   scope at that checkpoint; current default names and three-owner unfiltered none
   values are now implemented. Strings/int64/bools/finite floats retain types in v2. Values now accept
   bounded same-span original-string equality/regex AND filters through HTTP/MCP.
   Upstream literal-invention shortcuts and malformed-unfiltered fallback reject.
   Instrumentation/event/link scopes now join resource/span, including original
   nested attributes and parent string filters. Complete filtered/default name hints,
   unfiltered unscoped values, finite floats, seven parent-filtered stored intrinsic
   strings and paired block-oriented time bounds are implemented (latest checkpoint
   above). Root/duration/event-time intrinsics, filtered-unscoped/complex values and
   exact dedicated-column/omission/layout parity remain unsupported. This is not
   Grafana autocomplete parity. Complete the remaining required client contracts
   with the actual required JSON/protobuf envelopes,
   authentication, tenant isolation, time units, query parameters, status codes
   and empty/not-found/error behavior. Exercise checked-in responses through an
   independent client and Grafana's Tempo datasource. Do not relabel the current
   Pulse assembly JSON as a Tempo response or claim `query_traces` is TraceQL.
4. **Prove the ingest bridge.** Existing gRPC-producing SDKs can keep Collector/
   Alloy as the receiver and use OTLP/HTTP downstream. Validate the actual
   Elixir/Kura client contracts, propagation, tenant headers, batches, retries,
   compression and rejection behavior. Direct OTLP/gRPC is required only if that
   bridge is not an accepted deployment contract.
5. **Close workload limits and operations.** Measure exact lookup/search against
   representative trace cardinality, provider traffic and retention windows.
   Dedicated trace-ID/attribute postings are the next scale lever if current
   summaries/scans cannot meet those bounds. Verify whether ordinary Tuist traces
   exceed the existing 5,000-span/byte ceilings; either prove that envelope is
   adequate or add complete bounded pagination/large-trace handling. Never clip.
   Exercise separate-node restarts, overlapping owners, compaction/retention,
   provider failures, coherent backup/restore and compatible rollback.

Full TraceQL structural operators, trace aggregations, service graphs and tail
sampling are not automatically prerequisites for this captured selector. Inventory
and validate additional real consumers before making them replacement gates.
Neither checked-in fixtures nor source-only reviews establish live residency,
client compatibility or capacity. Shadow delivery, provider/load/fault/restore
exercises and cutover require separate human authorization; none has been performed.

## Design constraints

Object storage remains authoritative; CAS publication is the only correctness arbiter. No database, WAL, leader election or new cluster-visible mutable authority. Native query resources are disposable per-query state, not coordination. BEAM retains admission and deadlines until dirty NIF work actually exits. No infrastructure-remediation tools.

## Tempo search subset checkpoint

Implemented as a separate native complete-retained-context search resource with
whole-request poison/consume semantics, shared S3/paged metadata and actual-footer
accounting, no source-window/span-top-k pruning, fixed error precedence and bounded
trace/sample/string/output work. Authenticated `/api/search` supports closed
seconds/q/limit/spss parameters, JSON/protobuf and explicit most-recent selectors;
MCP uses positive nanosecond windows. Opt-in is default false. Native bookkeeping
outside BEAM/string budgets and full-retain-history scan cost are documented.

Local validation: `mix precommit --max-cases 4` passed **1058 tests**, with one
skipped and 33 excluded; **67 Rust tests**, all-target strict Clippy, strict Credo,
formatting, warnings-as-errors compilation, diff and Helm lint/render passed.
The public HTTP fixture partitions independently produced ResourceSpans into
separate stored objects, verifying outside-window roots/matches remain context;
owned cache restart/auth/default-off/closed params/protobuf tests also pass.
A source-only review closed two Mediums; its scope excludes test execution,
network/production and deployed parity. Required hint/uncharged native bookkeeping
are explicit documented limitations, not replacement readiness.

Remaining: production-representative bounded ID/attribute planning/postings,
search/tag discovery coverage, actual Grafana frame conversion/deployed client
acceptance, shared client/server span-ID behavior, complete oversized traces and
separate-node/provider/backup/restore/cutover gates. No production changes or
commits. Old native window-local search remains separate.

## Default names checkpoint and unscoped-value contract investigation

Omitted/empty/none HTTP name scope and omitted/none MCP name scope now combine
resource/span/instrumentation/event/link namespaces in **one native retained scan**.
V2 groups names by scope and includes 20 static intrinsic suggestions even when
empty; v1 excludes intrinsics and flattens/deduplicates stored names. Any visible
parent contributes Tempo's required service.name hint even unfiltered/absent
original. Explicitly scoped unfiltered original-key behavior stays unchanged;
merging those queries need not reproduce defaults. Both default variants remain
hints, not data/original-key presence or exact upstream omission parity.

Independent actual Tempo v2.9.0 SearchTags(None)/ExecuteTagNames→FetchTagNames
produced 15 raw and independently complete cases over three existing datasets:
12 exact, three complete supersets. Complete overlays use actual ExecuteSearch
matching IDs and original producer attrs, never Pulse results. Public protobuf
decoders consumed all 15 current native-result Elixir serializations. Actual
frontend HTTP handlers also executed 90 omitted/empty/none × v1/v2 requests,
with **owned stub metadata responses**; this proves handler vocabulary behavior,
not network calls to Pulse or running Grafana/deployed provider acceptance.

Default names share all five owner/attribute work charges under **one 2M work
ceiling** before predicates. For 20 resource + 15 span + 2 instrumentation attrs,
a row costs 40 units, permitting at most 50,000 parents without nested owners.
One global 5000 scope/name-pair dictionary includes 20 intrinsic reservations,
**even before v1 flattening**; one spelling in five namespaces costs five entries.
Scope strings now count toward name dictionary bytes, so near-cap explicit
queries can reject slightly earlier too. Output and dictionary caps remain
independent 1 MiB. Static suggestions never bypass storage/legacy/corrupt/budget
errors: default queries fail whole. A separate optional default-name callback
prevents old scoped/name/value adapters silently dropping namespaces. Native and
reference preserve reverse/duplicate/partition/floor behavior; tests cover empty
context, whole errors, global dictionary/work caps and actual footer undercounts.
HTTP/S3 tests restart manifest supervision and check all name-scope aliases,
versioned coverage, JSON/protobuf, MCP and authentication.

Unscoped **values remain unsupported**. Twelve actual identifier/value executions
establish leading-dot syntax, resource/span/instrumentation value union (not all
five name scopes), empty event/link-only `.phase`, and `.service.name` returning
both frontend and worker under a resource.service.name=worker filter. Existing
same-parent scoped filters are not interchangeable with that retained context.
Bare shared/http.method reject in the upstream identifier parser. The checked-in
evidence is for continued rejection, not permission to fabricate a five-scope
value union or claim unscoped parity.

Discovery capability **5**, tuple `{1,1,2,2,5}`, is required before default queries
reach a shared pool. Upgrade/drain every serving application and install matching
native artifacts; startup only validates its local artifact. Storage formats do
not change. Time/unscoped-value/dynamic-intrinsic/type contracts, indexed provider
planning, large/shared-ID traces and full client/alerting/operational acceptance
remain outstanding. No production access, deployments or commits occurred.

Validation: **1105 Elixir passed, one skipped, 33 excluded; 67 Rust passed**;
strict Credo (4171 functions/modules), all-target Clippy, warning-free compilation,
Mix/Cargo formatting/diff and Helm synthetic-values lint/ingress render passed.
The initial full run hit an existing five-second append-buffer fixture barrier
wait; the isolated original test passed. Its test-only wait is now 30 seconds,
without changing the deterministic zero-timeout caller, reservation/durability
assertions or production deadlines. Scoped source-only review has no open
findings; reviewers did not execute oracles/consumers or verify provenance.

## Complete filtered-name hints checkpoint

Default-off name discovery now accepts bounded resource/span original-string
AND equality/anchored regex filters on one parent, through MCP `query` and HTTP
`q`, in all five explicit stored scopes. It deliberately returns **complete name
hints**, not matching/original-key presence or exact upstream omission parity.
Generic keys come from matching parents, plus fixed resource/span promotions
from all visible retained context. Tempo's required service.name hint appears
whenever a visible parent exists even without an original attr. Empty promoted
strings count; wrong-type originals remain generic; instrumentation/event/link
owners contribute only matched-parent keys. Values and unfiltered original-name
semantics remain unchanged. Dynamic dedicated-column parity is not implemented.

Actual Tempo v2.9.0 ExecuteTagNames→vParquet4 FetchTagNames produced 75 raw cases
in three independent producer datasets. It exposed missing shared keys on later
matching parents, due to pre-join distinct collectors. Pulse will not reproduce
those omissions. The fixture preserves raw `response` AND independent `complete`:
actual ExecuteSearch matches span IDs (fixture sampling proven complete), then
original producer messages provide all requested-owner keys, plus raw promotion
hints. No expectation is generated by Pulse. 64 cases are exact, 11 deliberately
return complete supersets. Actual public SearchTagsV2Response decoders consumed
all 75 native-result Elixir wires against **complete**, not raw omission parity.
This is a disclosed semantic extension, not full Tempo/Grafana autocomplete parity.

Native/reference results stay reverse/duplicate/partition independent. Whole
legacy/corrupt nonmatch failures, visible-floor suppression of old promotions,
actual raw row/footer charges, 5000-name dictionary/independent escaped-output
ceilings, 2M owner+attribute work before filters and poisoned/consumed state remain.
HTTP returns `stored-context-name-hints; not-matching-key-presence`. A name filter
can add service.name while subsequent value lookup is empty; impossible filters
still return fixed promoted hints. HTTP/S3 tests ingest separate owners, restart
manifest supervision and verify all 45 promoted cases, JSON/protobuf/v1/v2/MCP,
auth and closed params; all 75 replay against native/reference and value-only
adapter fallback. Filtered names require a distinct explicit optional callback,
not old unfiltered/value-only callbacks that might ignore the query.

Discovery capability **4** is required, tuple `{1,1,2,2,4}`; storage formats do
not change. Upgrade/drain all serving applications and native artifacts before
clients send filtered-name queries. Startup is only local validation. Time,
default/unscoped/nested/dynamic-intrinsic query contracts, representative indexed
planning, large/shared-ID traces, full client/alerting/operational acceptance and
cutover remain outstanding. No deployments, production access or commits occurred.

Validation: **1097 Elixir passed, one skipped, 33 excluded; 67 Rust passed**;
strict Credo (4155 functions/modules) and all-target Clippy, warning-free compile,
Mix/Cargo formatting/diff and Helm lint/synthetic-ingress render passed. The first
full run only failed the old test's deliberate empty-key rejection expectation;
it now asserts the newly admitted name predicate, without relaxing value literal
or regex rejection. Scoped source-only review has no open C/H/M/Low findings;
all hint asymmetries, impossible-filter results, conservative extras and first-
error reporting are explicit. Reviewers did not execute tests/oracles or verify
fixture provenance independently.

## Static intrinsic vocabulary and time-contract investigation

Explicit `intrinsic` discovery adds static Tempo protocol vocabulary, separate
from stored-attribute discovery: 20 intrinsic names and seven v2 exact enum/known-
empty shortcuts. Public actual `Querier.SearchTagValuesV2` executed with only
limits/tenant context (no clients/rings/backend) establishes `status`/`span:status`,
`kind`/`span:kind`, `duration`/`span:duration` and `traceDuration`; inspected bytes
are zero. Actual names helper, not a running frontend request, supplies the name
list. Actual public protobuf decoders consumed all eight current Elixir results.
Ordinary replay has no Go or Python requirement.

Static dictionaries still require auth, canonical tenant, default-off gate and
raw query admission, but never storage. They do not assert stored presence or
support for every advertised TraceQL intrinsic. Names work in v1/v2; v1 value
shortcuts reject because of attribute conflation. Canonical bare v2 targets only;
dotted span.kind/resource.status remain stored attributes. Unknown dynamic
intrinsic values (even advertised names such as trace:duration/name) reject,
rather than guessing empty results. Nonempty filters/time params remain closed.
Static HTTP coverage explicitly says `static-protocol-vocabulary; not-stored-values`.
Native ABI/storage formats remain unchanged, required tuple `{1,1,2,2,3}`;
upgrade/drain every serving application instance before clients use new modes.

The time investigation did **not** add misleading strict span-time semantics.
Actual frontend `blockMetasForSearch` execution proves inclusive whole-block
metadata selection at five ranges including an interior gap. Actual ingester
cache-key execution proves different request windows share a tag-value key.
These are helper-level evidence, not full HTTP/cached-query acceptance. Faithful
compatibility needs an explicit block/time/cache contract and appropriate
metadata/planning, not a span-start predicate or silent parameter omission.
Time parameters remain rejected. Likewise filtered tag names require independent
special-column semantics: upstream can add promoted-column names despite no
matching generic attributes; existing value filtering cannot be reused blindly.

Tests cover failing storage (no reads), original kind/status attrs distinct from
keywords, gate/key/filter/version/tenant errors, admission/release, public auth,
v1/v2 JSON/protobuf and no object-store GET/LIST/requests. This is not full
Grafana autocomplete/browser, deployed-version, capacity, migration or cutover
acceptance. No production access, deployment or commits occurred.

Validation: **1091 Elixir passed, one skipped, 33 excluded; 67 Rust passed**;
strict Credo (4139 functions/modules) / all-target Clippy, warning-free compile,
Mix/Cargo formatting/diff and Helm lint/synthetic-ingress render passed. Scoped
source-only final review has no open Critical/High/Medium/Low findings. Generic
Storage/S3 additionally reject non-stored scopes before adapters/native dispatch;
static vocabulary cannot accidentally fall through to native decode errors.
Docs explicitly warn that intrinsic suggestions still fail TraceQL predicates,
v1 names cannot yield v1 virtual values, and static polling still gets admission
errors. Reviewers did not execute tests/oracles or independently verify provenance.

## Five-scope discovery checkpoint

Default-off names and original string/int64/bool discovery now supports explicit
resource/span/instrumentation/event/link targets, without flattening nested attrs,
interpreting scope name/version as attrs, or inventing event names/link IDs.
Existing resource/span original-string filters select one parent; all of that
parent's target owners contribute. Nested filter grammar remains unsupported.
V1 intentionally omits scope/type identity; V2 preserves scope/typed pairs, not
individual event/link ownership. Legacy/corrupt nonmatches still fail whole.

Actual public Tempo v2.9.0 Parquet and engine execution establishes 68 independent
cases / two parents / five scopes, including multiple events/links, shared keys
with different values across owners, int64 extremes, bools, absent/empty targets,
instrumentation name not being an attr and parent cross-scope/impossible filters.
Actual public protobuf decoders consumed all 68 current native-result Elixir
serializations semantically. Replay needs Elixir/Rust only. Public HTTP ingests
separate owners, restarts manifest supervision, then checks all cases and auth,
closed params, v1/v2/protobuf and matching unsupported-type errors. Original
row/footer charges still apply even to empty nested-owner scopes.

New explicit `trace_discovery_work_limit` bounds each scan attempt at 2,000,000
requested-scope owners plus their attribute entries, charged before filters;
empty owners count, and each repeated instrumentation owner costs again per span.
This intentionally tightens existing flat resource/span capacity to
floor(2M/(1+attribute count)) parents (about 95k with 20 attrs / 65k with 30).
A million-row cap did not bound nested fanout or flat attribute traversal; this
is safety, not capacity gain. Retries start fresh dictionary/work state while
spent row/provider/byte charges remain cumulative. Native temporary validation/
Arrow/input/output memory is still outside the BEAM heap guard. Native/reference
boundary tests cover empty owners, additional attribute charges, flat-scope
capacity reduction, impossible filters, whole errors and poisoned native state.
Discovery capability is **3**, required tuple **`{1,1,2,2,3}`**, without storage
format changes. Upgrade/drain all serving instances before using new scopes.

Validation: **1085 Elixir passed, one skipped, 33 excluded; 67 Rust passed**;
strict Credo (4123 functions/modules) and all-target Clippy, warning-free compile,
Mix/Cargo formatting/diff and Helm lint/synthetic-ingress render passed. Scoped
source-only review has no remaining Critical/High/Medium/Low findings; the flat
capacity tightening was accepted as intentional safety with explicit formula,
distinct error, repeated-owner/retry semantics and boundary regressions. The
reviewer did not execute tests/oracles or independently inspect fixture evidence.

Remaining: time/default/unscoped/dynamic-intrinsic discovery, nested predicates,
unsupported float/complex values, representative postings, complete large/shared-ID
traces, actual datasource/browser/deployed acceptance and operations. No
production access, deployments or commits occurred. This checkpoint supersedes
older statements below that other scopes are unsupported.

## Filtered value discovery checkpoint

Default-off value discovery now accepts a bounded complete original-string AND
selector through MCP `query` / HTTP `q`. It uses existing trace-selector syntax,
1–16 predicates/at most eight query-local anchored RE2-subset regexes, same-span
matching and no coercion of bool/int/bytes projections into strings. Matching
spans contribute original string/int64/bool target values; unsupported matching
types fail whole, while nonmatching type values are irrelevant. All visible rows
validate and all raw rows/footer/provider work remain charged before matching.
Legacy unknown still fails even under an impossible filter. Dictionary/output/
row bounds and retention/authority/retry/admission semantics are unchanged.

Actual public Tempo v2.9.0 engine `ExecuteTagValues` and vParquet4 `FetchTagValues`
produced 18 supported cases/three spans/two owners: sibling separation, cross-scope
filters, int64 extremes, bool/string distinction, full regex anchoring/newline/
alternation, empty/absent/no-match results. Public protobuf decoders also consumed
current native-result Elixir protobuf for all 18 semantic maps. A nineteenth case
proves upstream same-target equality returns an unproven query literal even with
impossible other predicates. Pulse rejects it instead of claiming stored presence.
Partial/malformed editor queries, hints, name/time filters and unsupported grammar
also reject rather than extracting partial conditions or falling back unfiltered.
This intentionally is not full Grafana autocomplete compatibility.

Adapters need an explicit filtered optional callback with query in the signature;
old unfiltered callbacks cannot silently discard it. Missing filtered support
uses the independently filtered bounded reference scan. Native/reference partition,
reverse, duplicate, legacy/corrupt-nonmatch, dictionary/output limits, stale adapter,
MCP and public HTTP→separate-owner-S3→cache-restart/auth/closed-params/v1/v2/protobuf
regressions pass. Discovery ABI is 2; required tuple `{1,1,2,2,2}`; matching artifacts
must ship together, with no storage format or production configuration change.

Validation: **1079 Elixir passed, one skipped, 33 excluded; 67 Rust passed**;
strict Credo/Clippy, warning-free compilation, formatting/diff and Helm lint/render.
The first full run corrected a test's raw private-NIF corruption expectation
(`fallback`, translated to public decode error); another full run exposed the
numerical oracle's default one-second scheduling assumption. That oracle now uses
an explicit bounded deadline while dedicated expiration tests remain unchanged;
no production deadline/work limits changed. Source-only review has no open
Critical/High/Medium/Low findings in the slice; reviewers did not execute oracles.

Still unimplemented at this earlier checkpoint: time/name/default/unscoped/intrinsic discovery,
float/complex compatibility, partial editor extraction, representative postings,
complete large/shared-ID traces and full datasource/browser/deployed acceptance.
Full-history provider costs remain and the feature remains default-off. No
production access, deployments or commits occurred.

## Candidate-first planning and conversion checkpoint

Candidate-first search validates all visible rows, retaining only original-string
matching or legacy-unknown IDs before replaying exact owned immutable inputs.
Earlier roots/nonmatching candidate context survives; all overlap/error/order/
limit semantics remain. No new authority/index or second provider GET exists.
Input caps are independently 1024 owners / 32 MiB compressed bytes, applied before
S3 metadata planning and bounded GET. They can be tighter than the former general
128 MiB scan limit; this is not a capacity improvement for every tenant. Both
passes independently visit at most a million rows; 16 MiB retained/result bounds
remain. Aborts release captured input before retries; reference adapters do not
have native compressed-input/owner caps. Tests cover >65,536 proven nonmatches,
a late match recovering earlier context, input/owner limits, aborts, upfront
refusal, lying sizes and original error precedence/upstream goldens.

Actual public Grafana v12.3.0 lookup source and unchanged Go AST-extracted search
function bodies, with its pinned original SDK/protobuf dependencies, consumed
current native protobuf and independent expected messages: one rich lookup/eight
search cases produced equal actual frames. Valid default-status spans first
panicked in the converter. Actual Tempo v2.9.0 Parquet conversion independently
materializes Status{}, so export now does too (JSON `{}` / protobuf field 15 body
length 0). Mixed UNSET/OK/message-only tests guard both versions/renderers.
Search/export API versions are 2, startup tuple `{1,1,2,2,1}`; storage formats
unchanged. Upgrade/drain all serving nodes before Grafana uses the pool. Client
frames are lossy for bytes, nanosecond times and downstream JS int64; Pulse stored/
wire fidelity remains separate. Producer/frame provenance lives in fixture docs;
ordinary replay remains Elixir/Rust-only, with no upstream generated code vendored.

Validation: **1070 Elixir passed, one skipped, 33 excluded; 67 Rust passed**.
Strict Credo/Clippy, warnings-as-errors compilation, formatting/diff and Helm
checks pass. Full runs exposed two fixture issues that were corrected: owned
retirement-clock injection removes the load-dependent one-second skew assumption;
cold >1024-object pruning now seeds coherent encoded objects after one public
append rather than 1030 unrelated serial CAS publications. Source-only reviews
have no open Critical/High/Medium findings; reviewers did not execute consumers.

Not complete: time/default/dynamic-intrinsic/unsupported-value discovery, actual
HTTP datasource/browser/deployed acceptance, representative immutable postings,
large/shared-ID traces, alert lifecycle/delivery, recordings/residency/ClickHouse
and authorized multi-node/fault/restore/cutover evidence remain. No production
access/change, deployments or commits occurred.

## Scoped discovery subset checkpoint

Default-off `discover_trace_tags` / `discover_trace_tag_values` and Tempo v1/v2
HTTP tag routes now scan complete retained tenant rows into native bounded sets,
without BEAM span expansion or trace-group retention. Only explicit resource/span
scopes and absent/empty/exact `{}` queries are accepted; window/filtered/all/
intrinsic/unscoped/other-scope requests reject. Names include all typed keys;
values support original string/int64/bool only, failing rather than hiding a
targeted unsupported float/bytes/array/kvlist/empty AnyValue. Any visible legacy
row fails even if the target appears absent. V2 preserves typed pairs (including
same spellings); V1 deliberately flattens/deduplicates protocol string values.

Shared query authority/floors/retries/deadlines/admission/upfront and actual-footer
accounting apply. Discovery charges all scanned rows up to one million, at most
5,000 distinct entries, 1 MiB dictionary bytes including per-entry headroom, and
an independent 1 MiB encoded result. Native bookkeeping/scratch/input/output are
outside BEAM heap bounds. Errors stop at the first detected violation, so tagged
reasons can depend on object order; complete results are never truncated. Native
state poisons on scan errors, consumes on finish and refuses poisoned locks.

Independent evidence: actual public Tempo v2.9.0 block `SearchTags` /
`SearchTagValuesV2` produced 11 cases/two spans, including int64 extremes,
Unicode, absent/empty values and bool/string identity under the same key. Public
protobuf decoders also verified Elixir v2 names/values serializer outputs for all
11 cases. Ordinary replay remains Elixir/Rust-only. Public HTTP→S3 tests partition
producer ResourceSpans into separate objects, restart owned manifest caches and
cover authentication, v1/v2/protobuf, closed params and unsupported types. Known
manifest row undercounts still fail from actual Parquet footer accounting.

Validation: `mix precommit --max-cases 4`: **1063 passed, one skipped, 33 excluded**;
**67 Rust tests**; strict Credo/Clippy, warnings-as-errors compilation, formatting,
diff and Helm lint/render pass. Source-only review: no open Critical/High/Medium/
Low findings in the slice. This review did not execute validation or production
probes and is not deployed-client, capacity, residency or cutover evidence.

Remaining: time-filtered discovery, default/unscoped/dynamic-intrinsic
and float/complex compatibility, actual Grafana autocomplete/frame/deployed-client
behavior, representative indexed planning, large/shared-ID traces and operations.
No production access/change, deployments or commits. Full-history scan costs and
incompatible retain-forever legacy history remain explicit default-off gates.

## Current implementation checkpoint

OTLP/HTTP JSON/protobuf and gzip, durable tenant-scoped Parquet/CAS, typed span search, time/duration/root filters, projection and conservative manifest blooms are implemented.

Increment 1 is implemented: S3/MCP filtering, cross-object selection and JSON rendering stay in a bounded disposable Rust resource. Parquet readers own immutable Erlang binaries without full-blob copies; encoding writes directly to an Erlang-owned binary. Reference ordering/typed-filter parity includes metadata ties, signed zero and cross-segment merges. A 150,000-span regression returns full metadata for 5,000 results with a 200,000-word BEAM query heap. A local 400,000-span provider-double probe returned limits 10/1,000/5,000 in approximately 75/254/483 ms; these are not production capacity guarantees.

Native compaction is independently opt-in through `PULSE_TRACE_COMPACTION_ENABLED`. Arrow merges stay native. Shared signal maintenance handles flat/paged CAS publication, retirement, ambiguous-response recovery and repeatable cleanup. Trace eligibility is separate from metrics eligibility. Decoded-size overflow shrinks original source sets before upload, never truncates rows.

PR #32 is now the sole lifecycle authority. Trace day-based retention (`PULSE_TRACES_RETENTION_DAYS`, default zero) shares checksummed v3 paged catalogs, durable discovery, `.managed` fences, committed floors, cleanup and delete admission with logs/metrics. The unreleased trace receipt-based v3, seconds-based TTL and frozen cutoff were removed to avoid incompatible authority. New unmanaged flat scopes remain unbounded. Development buckets using the unreleased receipt-form v3 are not automatically converted; incompatible roots fail closed, and authority must never be deleted to force LIST reconstruction. Unkeyed expired/future spans use OTLP semantic partial success; keyed fingerprints are unchanged, and publication always checks the latest floor.

New managed active-leaf references carry bounded service sets and ID blooms built from complete capped SHA-256-prefix sets, or identically sized versioned canonical blooms for wider sets, never unions of incompatible adaptive segment blooms. Leaf summaries cap at 2 KiB of bloom plus 512 encoded service bytes; references cap at 4 KiB. Live byte/count reserves and bounded owner wire batches preserve expiry headroom. Capacity-only non-affected spills cannot wedge unrelated ingest. Definitive pre-CAS compaction failures reclaim unreferenced replacements and rotate the paged cursor; ambiguous failures retain their uploads. Exact lookup prunes before leaf fetch/charge. Legacy, malformed and over-budget summaries always scan; false positives and dense metadata can still exhaust budgets. This addresses the immediate leaf-scan regression without claiming a complete posting index or production capacity.

`get_trace` now assembles all stored spans for an exact ID, preserves duplicates, and reports roots/missing parents/conflicting IDs. It forbids caller truncation/projection/time windows and fails on budgets, more than 5,000 spans or oversized metadata. Native assembly refuses ordinary top-k/time-filtered/attribute-filtered state; a dedicated constructor permits only the authority's retention floor. Managed responses report `retention_floor_ns` and `all_stored_spans_at_or_above_floor`. This is stored-snapshot coverage, not exporter completeness or a Tempo response envelope. Structured `attributes_regex` / `resource_regex` filters now execute natively with bounded anchored string semantics and query-local compiled programs/DFA caches. Memory/Parquet/public-S3 parity covers typed, escaped, Unicode and missing values. Native window-local `search_traces` now supports a bounded string-selector subset and cross-object grouping before trace limits. The subsequent opt-in search slice establishes bounded complete-retained-context overlap/ordering/root/duration/service metadata and sampled spansets against actual public Tempo v2.9.0 Parquet + TraceQL engine fixtures. Full TraceQL/discovery, representative trace-ID/attribute indexed planning, deployed Grafana frame/client acceptance and oversized-trace pagination remain unimplemented. See [`tuist-query-conformance.md`](tuist-query-conformance.md).

Latest lookup checkpoint: `mix precommit --max-cases 4` passed **1,053 tests**
(1 skipped, 33 excluded); **67 codec Rust tests** passed. The final focused
lookup/S3/public HTTP suite passed **20 tests**. Warnings-as-errors compile,
strict Credo (3,981 modules/functions, no issues), all-target strict Clippy,
Mix/Cargo formatting and diff checks passed. Helm lint and ingress-enabled
rendering with synthetic bucket/host values passed, including `/api/traces` and
`/api/v2/traces` Prefix paths. An earlier full run hit two localhost provider-stub
connection failures; the 46-test targeted recheck and subsequent full run passed.
Source-only follow-up closed the aggregate protobuf sizing-cache Medium with
per-span plans and the 5,000-span × 40-attribute regression. Reference grouping
keys now have an explicit 16 MiB cap; actual footer rows are charged for complete
assembly even with a known undercounted manifest. No Critical/High/Medium source
findings remain in the scoped lookup slice. These are local/source results, not
search/tag/datasource/deployed/operational replacement acceptance. Nothing was
deployed and the worktree remains uncommitted.

Previous search checkpoint: `mix precommit --max-cases 4` passed 1,045 tests (1 skipped, 33 excluded), including typed trace metadata and distinct-trace search regressions; codec Rust passed 67 tests and all-target strict Clippy. Warnings-as-errors compilation, strict Credo, formatting and diff checks passed. Those prior increments add typed trace attribute fidelity and a bounded native string-selector search, not full/deployed TraceQL parity. The subsequent lookup increment adds bounded Tempo v1/v2 JSON/protobuf serialization and HTTP lookup; it does not establish search/discovery, shared-span-ID, large-trace, datasource frame or deployed parity. Randomized native/reference grouping is partition/order independent; a 5,001-span hot trace cannot hide another trace. Public HTTP→S3→MCP search tests cover auth/cache restart; missing-object retry rebuilds native state without double counts and charges earlier work. Paged search cannot borrow span-top-k metadata exemptions, and undercounted manifest rows are recovered from the footer. Scoped source-only search follow-up closed TS-M1/TS-L1/TS-L2 and found no Critical/High/Medium; parse cost, literal quirks and window-local reference differences remain explicit limitations. Independent compiler/Arrow fixtures and public HTTP/S3/MCP tests cover richer metadata, corruption, keyed rejection and mixed legacy reconciliation. The 150k-overlap/5k-native-response fixture now includes coherent typed attributes with explicit headroom under unchanged 16 MiB key/result caps; a separate wider-row regression proves narrow projection still fails full-key limits without clipping. Historical provider-double timings are not measurements of this richer path. Scoped source-only follow-up found no Critical/High/Medium, with validation parse cost and query-projection predicate semantics remaining Low; no tests were executed by the reviewer. Helm lint/opt-in rendering was last run in the earlier checkpoint, not claimed anew. Reconciliation regressions cover trace migration, mixed-age row filtering, keyed expiry, future rejection, paged native compaction, physical cleanup and missing authority, buffered moving floors, public OTLP/MCP, dedicated native floor assembly, 140-leaf exact lookup and nested-reference cache ownership. Best-effort maintenance progress, unknown/dense metadata scans and global node admission/capacity remain operational validation requirements. Retain-forever flat catalogs, complete-trace indexing/pagination, required query/API compatibility, and live workload evidence still block replacement. Collector defaults can exceed configured safety limits; the 10,000-record cap does not guarantee a rich batch fits all other ceilings. Actual shadow delivery and cutover remain unvalidated. See [`tuist-adversarial-review.md`](tuist-adversarial-review.md) for the fixes, source-review verdict and remaining acceptance gaps.
