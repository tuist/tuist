# Protocol coverage

Pulse's compatibility target is the **public protocols and their full feature
breadth**, not the subset used by one application or deployment. A successful
client example is evidence for that profile, not the product boundary or proof
of full conformance. Today several surfaces remain intentionally incomplete.
Use the linked contracts before moving a mixed telemetry pipeline. Coverage is
evaluated against explicitly targeted protocol versions, not an implicit promise
to support every historical client/session protocol.

## Current boundaries

| Surface | Available | Still unsupported or incomplete |
| --- | --- | --- |
| OTLP logs | HTTP JSON/protobuf/gzip and opt-in [gRPC](otlp-grpc.md) (gzip/zstd); typed bodies and resource/scope/log metadata; source times, context IDs and event names | Resource entity references and remaining OTLP JSON forms |
| OTLP metrics | HTTP and opt-in [gRPC](otlp-grpc.md). Gauges; cumulative and delta sums; cumulative and delta explicit and exponential histograms (exponential projected to classic buckets); summaries; typed owners, original counts, optional fields and embedded exemplars | Unspecified temporality; delta-to-cumulative conversion (deltas are stored as reported); native-histogram storage; full OTLP-to-Prometheus naming/resource promotion; dedicated exemplar queries |
| OTLP traces | HTTP JSON/protobuf/gzip and opt-in [gRPC](otlp-grpc.md); original typed resource/scope/span/event/link data, bounded complete exact-ID assembly and export | Resource entity references, remaining OTLP JSON forms, and proof of exporter completeness |
| Prometheus remote write | 1.0 and 2.0 scalar samples, stale markers and non-finite values, native histograms (integer and float, exponential and custom-bucket), exemplars, retained metric metadata, 2.0 written-count headers, and [source created/start timestamps](metrics.md#remote-write-20-start-timestamps) (legacy rc.3 per-series and rc.4 per-point); also at `/api/prom/push` and `/api/v1/push` | Optional zero-sample injection/start-aware rates, newer stateless-mode validation, full TSDB/client/compliance-suite acceptance |
| Prometheus queries/discovery | Documented bounded PromQL subset, including instant-query string and raw range/subquery matrix results, signed offsets, unitless decimal/hexadecimal/separator time literals, duration-valued scalars and bounded duration arithmetic with outer `step()`/`range()` and `min_of`/`max_of` in windows/resolutions/offsets, numeric/`start()`/`end()` `@` anchors on selectors and explicit/default-minute-resolution subqueries, quoted UTF-8 selector/grouping/matching names and UTF-8 `label_replace` destinations, UTF-8 `label_join` with ordered/missing/repeated sources and name rewriting, `present_over_time`, name-preserving `first_over_time`/`last_over_time`, source-timestamp `ts_of_first_over_time`/`ts_of_last_over_time`, newest-tie float-extremum timestamps `ts_of_min_over_time`/`ts_of_max_over_time`, and chronological `changes`/`resets` for floats/native histograms/mixed windows, least-squares gauge `deriv`, median absolute deviation `mad_over_time`, interpolated `quantile_over_time` with per-step quantiles/invalid-quantile warnings, and `double_exponential_smoothing` (`holt_winters` alias) with per-step factors and fail-whole factor validation; metric-named mixed-histogram info annotations (also for `predict_linear` and extremum timestamps), three-argument `clamp` with per-step scalar bounds and Mimir NaN semantics, basic math (`ceil`, `sqrt`, `exp`, `ln`, `log2`, `log10`), angular `deg`/`rad`, scalar `pi()`, inverse trigonometric `asin`/`acos`/`atan` with per-sample domain NaNs, circular `sin`/`cos`/`tan` with radians and nonfinite-input NaNs, hyperbolic `sinh`/`cosh`/`tanh` with Go-compatible overflow classification, and inverse hyperbolic `asinh`/`acosh`/`atanh` with domain NaNs and signed endpoint infinities; native histograms (Prometheus 3.5.0 base with Mimir's corrected NaN-sum quantiles), plural quantile labels, classic/native fractions, `/api/v1/query_exemplars`, instant/range HTTP APIs, sample-backed label/series discovery, build info, bounded single-line query formatting, `/api/v1/metadata` from retained remote-write metadata, and MCP queries | Full language/function/modifier coverage (including `anchored`/`smoothed`), full warning/info annotation parity, delayed metric-name removal, exact multiline printer parity, OTLP-sourced metadata, and full TSDB/client parity |
| Loki ingestion/queries | JSON/Snappy protobuf push and OTLP at `/otlp/v1/logs`; documented bounded LogQL queries, including scalar instant envelopes, scalar comparisons, decimal/hex-float literals and zero-divisor NaNs, instant/range reset-aware `rate_counter`, missing/empty-field skipping for all `unwrap` aggregations (log codec `{1,1,7}`), post-unwrap label/error filtering and explicit error preservation, typed-filter `LabelFilterErr` generation with first-error preservation, Go-profile signed-int64 runtime duration/unsigned-uint64 byte conversions with bounded fractional rounding and overflow rejection, signed/fractional duration thresholds and offsets, uint64 byte thresholds and separate ordered integer bracket windows, float64 numeric filtering and eager-AND/short-circuited-OR error propagation, pinned Loki double-quoted/raw string decoding with exact byte escapes, logfmt strict byte-position errors, non-strict recovery, empty-value flags, first normalized duplicates and quoted Unicode decoding; stream/metadata collision ownership, released stream names after drops and first-extraction history across parsers; instant-only `approx_topk` with exact ranking and instant/range `approx_count_distinct` with exact string counting under existing budgets; request-local `X-Loki-Query-Limits` maxQueryLength for finite reads; complete stream label, value and series discovery; index stats and volume (`aggregateBy=series` and bounded selector-only `aggregateBy=labels`, using actual line bytes rather than Loki chunk estimates); build info; WebSocket live tail; detected labels and fields; query-time patterns and `|>`/`!>` filters; MCP log reads | Full LogQL, including broader JSON/parser grammar, complete parser-error generation and hint-driven early exits; nondeterministic shared-source alias choice; pinned scanner/test contradictions such as accepted `0B`; probabilistic sketches/distributed merging/high-cardinality acceleration; other per-request policy fields; index-backed volume cost/estimate parity; full client parity |
| Tempo compatibility | Experimental bounded v1/v2 exact-ID export with V2 same-span filters and ancestor/descendant depths; separately opt-in retained-context search and discovery; documented typed predicates; TraceQL metrics with `topk`/`bottomk`, core `span:id` grouping, `event.` predicates, structural `>>`/`>`/`<<`/`<`/`~` search chains and `| select(...)` (`rate`, `count`/`min`/`max`/`sum`/`avg_over_time`, `quantile_over_time`, `histogram_over_time`), bounded scalar/vector `+ - * /` expressions, typed ordered-label matching/ungrouped broadcasting and value-preserving scalar filters; echo and build info | Full TraceQL including spanset `&&`/`||` and negated structural operators, structural metrics, link/instrumentation search owners, `compare()`, exemplars, unlimited-series overrides, full indexed planning, discovery parity and deployed-client acceptance |
| Alerting | Native bounded thresholds, authored mixed-source expressions, experimental recordings and delivery | Full Grafana imported-rule execution, lifecycle, routing, notification and template semantics |
| MCP | Stateless 2026-07-28 tools, capability-scoped Pulse writes and request-scoped subscriptions | Legacy initialize/session protocols; infrastructure remediation is deliberately a separate server |
| Sentry error collection | [Bounded JSON error envelopes, legacy JSON store and pixel GET ingestion](error-tracking.md), gzip/zlib-wrapped deflate/zstd, configured project credentials, Parquet publication before acknowledgment, MCP diagnosis and optional error monitoring | Full Relay/Sentry ingestion and normalization, symbolication/minidumps, attachments, performance/session/replay storage, Sentry REST issue APIs and lifecycle |

Sentry compatibility work also uses actual Relay integration scenarios. The
selected [`test_envelope_without_header`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_envelope.py#L73-L87)
now replays its project-42, envelope-DSN, empty-HTTP-auth-header and exact-message
input through Pulse, including native Parquet/S3 publication and a cold diagnostic
read. Six local credential-rejection controls perform no provider requests.
Pulse retains the scrubbed `message` instead of Relay's normalized `logentry`;
this is an explicit response/storage adaptation, not complete normalization
parity or execution of the upstream Relay suite. An empty header alone never
authenticates, and conflicting credentials still reject.

The same Relay revision's complete two-method
[`test_options_response`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_store.py#L67-L83)
also replays the original GET/POST preflight requests for `/store/`, requiring
POST-only advertised methods and an allowed-header response. Local gzip controls
cover both `/store/` and `/envelope/`: `Content-Encoding` is now allowed alongside
the existing ingest headers, without credentials or arbitrary-header reflection.
Three data-bearing identity/gzip POSTs publish through native Parquet/owned
loopback S3 and remain readable after a cold manifest reload; three invalid-key
POSTs do no provider work. The middleware and endpoint behavior are exercised
through Pulse's production endpoint, not a browser or a running Relay instance.
This does not import Relay's broader CORS header set, compression formats or
security-report API. The original test asserts any successful OPTIONS status;
Pulse retains its existing 204 response.

Relay's [`test_compression`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_basic.py#L253-L271)
contributes all four matching store cases: gzip, zlib-wrapped deflate, identity
and an explicitly empty encoding header, with the original `hello world` JSON
bytes and no content type. An empty header means identity on both ingestion
endpoints. Six native-Parquet/owned-loopback-S3 publications (including two local
envelope controls) survive a cold read with original messages and acknowledged
IDs. Twenty no-provider rejections cover unsupported/stacked encodings, broken
or truncated checksums/streams, raw DEFLATE, trailing/concatenated streams,
invalid JSON, wrong keys and unchanged event/wire/expanded-body limits. These
are local safety controls, not upstream rejection oracles. An exact 16 MiB
expanded unsupported-item envelope succeeds without publication; one byte over
fails whole. Shared decompression remains gzip-only outside Sentry's opt-in
reader. This is production-endpoint replay, not execution of Relay's suite,
complete compression behavior or SDK/client acceptance.

The zstd row of Relay's
[`test_store_content_encodings`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_store.py#L1043-L1067)
now rejects an empty body with `400`, rather than unsupported-encoding `415`.
The zstd receiving hop from
[`test_store_content_encodings_chained`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_store.py#L1071-L1082)
accepts its original `Hello, World!` message through store and an authored
envelope control; both survive native-Parquet/S3 publication and cold reads.
This adapts the receiving hop, not Relay forwarding or normalized `logentry`.
OTP's built-in decoder runs incrementally under the existing wire/output/event
ceilings and a separate 16 MiB window ceiling. Complete standard single frames
are required; preset dictionaries, truncation, trailing/concatenated/skippable
frames and bad checksums reject without publication. These restrictions and
boundary controls are local safety policies, not extra upstream oracles.
Brotli, stacked encodings and full compression/client parity remain open.

The same revision's complete
[`test_corp_response_header`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_basic.py#L274-L291)
replays an empty project-42 store POST with a query key and asserts
`Cross-Origin-Resource-Policy: cross-origin`. The source asserts no HTTP status
or accepted event. Local controls verify the header on both ingestion endpoints'
preflight, body/authentication rejections, successful Parquet/S3 publication and
storage failures. MCP still rejects disallowed origins and receives neither
this header nor wildcard CORS. This is header-level endpoint compatibility,
not browser/COEP testing or a port of Relay's global response policy.

Relay's complete
[`test_store_node_base64`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_store.py#L86-L110)
now replays its original base64/zlib Node payload and octet-stream/auth headers
through `/api/42/store/`. Its offset-free 2018 timestamp means UTC, following
Relay's timestamp decoder, while original payload fields and configured project
ownership remain distinct. Pulse retains `message: "Error: yo mark"` instead of
Relay's normalized `logentry`; this remains an explicit normalization adaptation.
Six native-Parquet/owned-loopback-S3 publications (one source case plus five
local controls) survive cold reads as four distinct event identities. Exact
1 MiB decoded JSON passes in both base64 forms; one byte over rejects, including
during inflation. Seventeen no-provider body/authentication/endpoint rejections
and separate UTC/offset/malformed/range/future controls preserve safety policies.
Legacy decoding is store-only, single-layer and bounded; full
timestamp grammar/precision and legacy SDK acceptance remain open.
The upstream Relay suite was not executed.

The same revision's complete
[`test_legacy_store`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_store.py#L53-L64)
now replays both original `Hello, World!` requests to project-less `/api/store/`
with the helper's octet-stream and Raven authentication headers. The regression
first reproduced 404. Project resolution requires exactly one configured project
matching the key, never payload/query project fields or tenant headers. Two
source requests and two local rotation/second-tenant controls publish through
native Parquet/owned-loopback S3 and survive cold reads with their acknowledged
IDs and configured project/service ownership. Twelve no-provider rejection
controls cover absent/invalid/conflicting/ambiguous credentials, empty
configuration, project-scoped key binding, malformed JSON and unchanged event/
wire ceilings. Ambiguity rejection is a local security policy, not an upstream
oracle. Pulse retains scrubbed `message`, not normalized `logentry`; no Relay
execution, legacy SDK acceptance or storage-format change is claimed.

The same Relay pin's `endpoints/store.rs:106–121` dispatches an exact raw
`application/x-sentry-envelope` POST Content-Type to envelope parsing, after
request authentication. Independently authored public requests reproduced
Pulse's `400 invalid_event` while the equivalent `/envelope/` request succeeded.
Store now reuses its bounded envelope decoder and header-credential validation.
Four store publications and four envelope controls retain IDs, event contents,
project attribution and binary-attachment discard counts through identity/gzip,
project-scoped/project-less requests and cold native-Parquet/owned-S3 reads.
Seventeen no-publication boundary attempts cover credential agreement, DSN-only
store rejection, ambiguous/project-less DSNs, exact raw media type, GET isolation,
framing/size rejection and empty/unsupported-only envelopes; storage failures
remain retryable503. These are consumers of a source-declared dispatch contract,
not imported Relay tests or upstream execution. A header-only JSON object under
the exact envelope media type is no longer ingested as a legacy JSON event.
Upgrade ingress applications consistently; ceilings/native/storage formats stay
unchanged. This does not extend supported envelope item types.

Relay's complete environment-tag promotion cases in
`relay-event-normalization/src/normalize/mod.rs:797–842` (same pin) now have
independent store/envelope consumers. Legacy `environment` tags previously
published with an empty resource projection: the public environment filter
returned zero instead of six matching events after cold native-Parquet/S3
reads. Missing/empty/non-string top-level environments now fall back to object
tags or the first matching ordered pair, using the existing scalar conversion
and trimmed tag value. Nonempty top-level strings retain precedence; empty/null
first tags do not yield ownership to later duplicates. Twenty-four publications
check the two original promotion inputs and empty control plus precedence,
object/list, duplicate, scalar, whitespace and malformed-value controls.
Retained scrubbed events/tags and issue IDs stay unchanged. This is projection
compatibility, not full Relay tag/environment validation or normalized-event
JSON parity. Upgrade ingress apps consistently; stored projections are not
repaired and native/storage formats and ceilings are unchanged. Relay was not
executed and no licensed source test file was copied.

The same Relay pin's `extractors/request_meta.rs:663–687` accepts a
case-insensitive Sentry scheme in `Authorization` or `X-Sentry-Auth`. Public
replay first returned 403 for a valid Authorization-only store request. Both
header locations now share Pulse's existing key parser and all supplied keys
must still agree. Fifteen independently authored store/envelope/pixel requests
cover the alternate header and mixed-case schemes, including project-less
store URLs; a sixteenth request verifies agreement across both headers, query
key and envelope DSN. Cold native-Parquet/owned-S3 reads retain all identities,
raw events and configured project/service ownership despite spoofed tenancy.
Nine no-provider controls cover invalid/missing/duplicate/conflicting keys,
duplicate Authorization fields and ingest/read credential separation. Browser
preflight now permits Authorization without cookies or read-policy changes.
These are consumers of the source-declared authentication contract, not copied
upstream tests or Relay execution. Pulse's agreement policy intentionally differs
from Relay's rejection of multiple auth methods; Basic auth remains unsupported
on Sentry routes. No storage/native/budget change; upgrade ingress apps together.

Relay's complete four-execution
[`test_store_pixel_gif`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_basic.py#L116-L141)
now replays both original JSON/base64-zlib inputs through `GET /api/42/store/`.
Its unused `trailing_slash` parameter preserves two executions per input, not
invented slash variants. Replay first reproduced 404. All four source events
and two local project-less/exact-size controls survive native Parquet/owned-S3
publication and cold reads; successful GETs return a 1×1 GIF, not JSON IDs.
Twelve no-provider rejection controls preserve credential isolation, the
1,000,000-byte query ceiling, the 1 MiB decoded/inflated event cap and envelope
route isolation. A separate storage-failure control returns 503, never a GIF.
Non-cacheable responses and rejecting HEAD probes before publication are local
safety policies, not upstream assertion oracles. URL data can reach proxy logs
before scrubbing; POST is preferred. Normalization, browser/SDK acceptance and
running Relay's suite remain open; storage/keyed bytes and dependencies are unchanged.

Relay's complete six-row
[`test_store_allowed_origins_passes`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/tests/integration/test_basic.py#L169-L203)
now replays project 42, Origin `http://valid.com` and `{"message":"hi"}` with
the original wildcard/exact/scheme-only/domain-only/empty/nonmatching policies.
Optional per-project `allowed_domains` enforces these restrictions after key
resolution. All four accepted source events and five local controls survive
cold native-Parquet/S3 reads; rejected requests perform no provider operations.
No-Origin SDK acceptance, wildcard label boundaries, IPv6/explicit-port matching,
malformed origins and ambiguous project-less keys have separate local controls.
The bounded pattern/origin grammar and explicit `403` are local policies: the
upstream test asserts capture/noncapture, not rejection status. Omission keeps
the existing unrestricted policy. This does not claim browser/SDK acceptance,
Relay execution or full normalization/origin-parser parity.

The complete three-row Relay
[`test_level`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/relay-event-schema/src/protocol/types.rs#L1153-L1169)
decoder oracle now replays through store/envelope ingestion and cold
native-Parquet/S3 MCP log reads: `log` → `info`, integer 30 → `warning`, and
`critical` → `fatal`. Other integer Python levels share the canonical projection.
Original event levels remain unchanged; custom strings and unsupported-value
fallbacks retain existing policies. These are explicitly unit-to-HTTP
adaptations, not original Relay ingestion scenarios or full normalization parity.
Twenty-two publications cover source rows and separate controls, including
distinguishing integer 30 from float 30.0. Projection changes apply only to new
events; upgrade all Sentry-serving apps for consistency, without rewriting history.

Relay's `test_timestamp_to_datetime` additionally supplies five nonnegative
float timestamp oracles, including both sides of second-boundary rounding.
Floating seconds now round their fractional part to microseconds before
assembling integer nanoseconds. Twelve store/envelope publications preserve
original values through cold native-Parquet/S3 MCP reads, including a separate
modern-epoch control. The same source test's four negative inputs retain
Pulse's pre-epoch rejection without provider access; those are deliberate
incompatibilities, not passing Relay normalization cases. These scalar-to-HTTP
adaptations do not establish full timestamp/normalization parity. Integer seconds,
ISO parsing, retention and future-time policies remain unchanged.

Relay's complete three-input
[`test_values_deserialization`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/relay-event-schema/src/protocol/types.rs#L1078-L1119)
also supplies equivalent wrapped, array and single-object exception containers.
These decode oracles are adapted into store/envelope events; titles and Pulse
group identity are separately authored consumer expectations, not original Relay
ingestion or Sentry grouping oracles. Ten durable publications include separate
last-exception/stack-frame controls. Cold native-Parquet/S3 MCP reads preserve
original containers while grouping equivalent new events together. Old persisted
fallback issue IDs are not rewritten or merged, although read-time titles now
recognize the containers. Upgrade Sentry-serving apps consistently; other
container normalization and full Relay compatibility remain open.

Relay's complete
[`test_logentry_from_message`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/relay-event-schema/src/protocol/logentry.rs#L178-L191)
supplies the original string `hi` and decoded `formatted: hi` oracle. Public
store/envelope consumers preserve the raw string while selecting the same title
and new-event group as a formatted object. Eight durable publications include
separate canonical-object, distinct-message and exception-precedence controls,
verified by cold native-Parquet/S3 MCP reads. These are explicit decoder-to-HTTP
adaptations; titles and Pulse identity are authored expectations, not Sentry
grouping oracles. Existing IDs are not rewritten; full logentry normalization,
parameter interpolation and Relay-suite execution remain open.

Relay's seven complete successful
[`fingerprint.rs` decoder cases](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/relay-event-schema/src/protocol/fingerprint.rs#L125-L215)
cover strings, Python-spelled booleans, integers, truncated floats, null omission
and empty defaults. These decoder inputs/oracles are adapted to both ingestion
routes and cold native-Parquet/S3 MCP reads. Forty publications include canonical
string counterparts and separate negative-zero/integer/float-bound controls;
raw fingerprint types survive while equivalent grouping components share an ID.
Twenty-two malformed/precision/size rejections make no provider requests.
Pulse deliberately rejects bad components whole instead of Relay's soft-error
stripping (including the two original out-of-precision float rows). Existing
string identities and supplied count/byte limits stay unchanged. This proves
Pulse grouping consumers, not Sentry issue identity or full normalization parity.

Relay's complete `event.rs:1037–1049` `test_lenient_release` decodes numeric
release `42` as `"42"`. Authored store/envelope and cold native-Parquet/S3 MCP
consumers now find both numeric and canonical-string events under that filter;
previously only strings matched. Twenty-eight publications retain raw values,
with separate scalar/precision/long-string controls and unchanged authorization.
The existing bounded scalar conversion is shared with fingerprints, whose
stricter component count/byte admission remains. This is new-event release
projection, not raw event normalization, old-data repair or Relay-suite parity.

Relay's complete `exception.rs:145–156` object-value decoder oracle converts
`{"value":{"unauthorized":true}}` to a JSON-text value. Public store/envelope
consumers now use that text for titles and new-event default grouping while
preserving scrubbed event types. Thirty-two cold native-Parquet/S3 publications
include canonical-string counterparts, nested ordering, arrays and scalar controls;
five additional publications check scrub-before-render, null/empty behavior,
typed prefixes, custom fingerprints and Unicode title truncation. Unauthorized
requests do no provider work. Numeric text uses Pulse JSON; complete Relay float
formatting and old-ID/materialized-summary migration are not claimed.

Relay's complete message-only normalization cases in
`relay-event-normalization/src/logentry.rs:156–190` retain their message strings
as formatted values; `event.rs:218` aliases top-level `message` to that decoder.
Twelve authored store/envelope consumers of those three cases now project the
same titles/groups through legacy message objects and explicit logentries.
Previously four legacy events fell into `Error`. Eight additional publications
cover formatted/null/empty precedence, exception/explicit-logentry priority,
scrubbing, invalid types and Unicode title bounds; unauthorized requests cause
no provider work. Original scrubbed fields and custom fingerprints stay intact.
These are normalization-to-HTTP adaptations, not original Relay grouping
oracles or full parameter-interpolation/normalization parity. New default IDs
can change; old issue IDs/materialized summaries are not migrated.

Relay's source-declared non-object logentry conversion (`protocol/logentry.rs:119–134`,
`protocol/types.rs:793–802`, same pin) now supplies JSON display text for numbers,
true and arrays across canonical/legacy message names. Sixty independently authored
store/envelope publications include string counterparts and cold Parquet/S3
title/group/raw-value checks; seven boundary publications cover false/null,
canonical presence, object/exception precedence, privacy, truncation and literal
fingerprints. Two unauthorized attempts do no provider work. Public red returned
`Error` for true; the corrected projection returns `true`. No copied upstream
test rows, upstream execution, full float-format parity or old-ID migration is
claimed; budgets and native/storage formats are unchanged.

Relay also declares exact `sentry.interfaces.Message` and
`sentry.interfaces.Exception` aliases (`event.rs:218,364`). Complete selected
message decoder/normalization and exception roundtrip values now retain
canonical titles and Pulse groups across twenty store/envelope publications,
cold native-Parquet/S3 MCP and direct storage reads. Previously ten legacy
events produced `Error`. Twenty-eight authored publications cover canonical
presence (including null/invalid values), case/exact-name boundaries, chain
containers, scrubbing, Unicode title bounds and unchanged custom fingerprints;
two unauthorized requests cause no provider work. Stored event shapes stay
unchanged. These are source-decoder/alias adaptations, not Relay grouping
oracles or general normalization. Upgrade query/ingress apps consistently;
retained issue IDs/materialized summaries are not migrated.

The nested exception `sentry.interfaces.Stacktrace` alias also feeds existing
frame-based default grouping when canonical `stacktrace` is absent. Eight
independently authored store/envelope publications expose the prior split between
equivalent canonical/legacy events and collapse of distinct legacy frames. Cold
native-Parquet/S3 MCP and direct storage reads now retain two frame-specific
groups without changing source exceptions. Twenty-four boundary publications
cover canonical presence (including null, malformed and empty values), exact
names and literal custom fingerprints; two unauthorized attempts do no provider
work. The alias is source-declared in Relay `exception.rs:50–54`; group equivalence
is a Pulse contract, not an original Relay grouping oracle. New-write identities
can change; historical groups are not migrated. Top-level stacktrace grouping,
symbolication and general alias normalization remain open.

Relay's complete user/request roundtrip inputs and explicit legacy aliases
(`user.rs:143–186`, `request.rs:634–723`, `event.rs:345–351`) expose a Pulse
privacy-policy mismatch: canonical fields were scrubbed, but equivalent
`sentry.interfaces.User` / `sentry.interfaces.Http` fields survived persistence.
Eight store/envelope publications now apply identical whole-field filtering,
with cold native-Parquet/S3 MCP and direct storage reads proving write-time
scrubbing. Two further authored publications cover recursive/case/exact-name/
title/custom-fingerprint controls; unauthorized requests do no provider work.
The input shapes and aliases are source-backed; the conservative privacy policy
and HTTP/MCP assertions are Pulse controls, not Relay privacy oracles.
Upgrade ingress applications; retained objects/evidence/IDs are not scrubbed or
migrated. No automatic cleanup, native/storage-format or resource-limit change.

Sentry trace correlation accepts canonical dashed UUIDs as well as undashed
32-digit hexadecimal IDs, normalizing only the projected ID. A disposable replay
of all four active Relay `protocol/contexts/trace.rs:562–615` formatting rows
exposed lost correlation on four dashed-ID store/envelope publications; cold
native-Parquet/S3 MCP and direct storage reads now retain it. Permanent regression
inputs are independently authored, not copied Relay test code: eight publications
cover upper/lower dashed and undashed IDs, with sixteen further boundary
publications and two unauthorized/no-provider controls. Malformed hyphen positions,
invalid hex and unchanged 16-digit span-ID grammar remain discriminating controls.
Raw contexts and issue groups stay unchanged; old absent projections are not
backfilled. This is not complete TraceId grammar, nil-ID repair or cross-signal
automatic correlation parity. No native/storage-format or resource-limit change.

Sentry event IDs also accept braced dashed UUIDs and case-insensitive `urn:uuid:`
prefixes, matching Relay's locked uuid 1.28.0 `test_parse_valid` contract. All
seventeen literal inputs, including repetitions, replay as 34 store/envelope
publications with canonical lowercase IDs: direct cold Parquet/S3 reads retain
all 34 records and MCP retains five unique identities. Separately authored
controls reject malformed/nested wrappers without provider work and retain
authentication, envelope-header precedence and strict trace/span-ID grammar.
This does not execute Relay or establish general event-normalization parity;
upgrade ingress applications, without changing existing IDs or stored bytes.

PromQL, LogQL and trace predicates share a bounded regex profile accepting
braced hexadecimal escapes followed by repetition, literal quoting (`\Q...\E`,
including an omitted terminal `\E`) and Unicode-valued octal escapes. Quoting
inside character classes and backreferences still reject. Whole-value matching
remains anchored even with an unfinished quote. POSIX classes preserve ASCII
membership and Unicode simple case folding, including their complements.
Malformed escapes and actual nested/possessive repetition reject, including
extra lazy suffixes (`a???`, `a{2}??`); valid `a??` remains supported.
Counted bounds and nested products follow Go's 1,000-copy admission limit;
leading-zero and malformed count spellings remain literal braces. Invalid
inner counts cannot hide under an outer zero. Independent admission and
matching oracles retain eight original Go parser-table patterns plus local
controls; Mimir/Loki/Tempo HTTP tests reject invalid patterns before storage.
Repeated `&&`/`~~` inside classes are literal members, not Rust set operators,
including with negation, case folding, named classes and adjacent ranges.
Literal opening brackets and left-to-right scalar hyphen ranges also follow
Go: `[[]` matches `[`, `[--x]` spans `-` through `x`, and `[a--b]` rejects.
Leading Unicode-property carets toggle negation (`\p{^Latin}` / `\P{^Latin}`),
including inside classes, with folding and before quantifiers. Property names
and scalar membership use Go 1.27.3's Unicode 17 categories/scripts, category
aliases and Any/ASCII/Assigned, with loose ASCII case/space/underscore/hyphen
spelling. ISO script abbreviations, binary properties, Unicode whitespace and
property=value forms reject as in the pinned parser. Property-specific folds
precede negation; this does not update literal case folding or prove full Go
regex parity. Property preparation has a separate 1 MiB logical charge before
union/zero-repeat simplification and bounds emitted text independently, alongside
existing program/schema/work caps.
Raw capture/modifier headers validate before literal normalization: invalid
name bytes, quoted/escaped header repairs and unsupported flags reject.
Empty and repeated inline flags preserve scope, atom binding and greediness.
Independent Go matching oracles and local HTTP/Parquet/S3 controls cover
all three protocols; this does not establish full Go regex, protocol or client
parity. Named `regexp` parser admission now inspects native capture metadata,
without imposing PCRE's different directive/quantifier grammar. Eight independent
Go flag/capture cases and a Unicode-property capture replay through log and
metric HTTP/Parquet/S3 queries; original Loki constructor rejections remain
covered. Original capture schemas preserve erased groups as empty values,
including trailing numeric groups, impossible alternatives and first-parser
ownership. Executed Go oracles and local HTTP/Parquet/S3 controls cover these
forms. Predicate/parser/indexed-extraction/template-helper schemas reject above an independent
1 MiB logical ceiling (32 bytes per group plus raw name bytes), even when
optimization removes every group; counting does not allocate capture names.
Flag-separated quantifiers nest the preceding quantified atom, preserving
capture indices, earlier atom flags, subsequent scope and each repetition's
U/lazy greediness. Counted products still reject above 1,000; directly adjacent
quantifiers remain invalid. Executed Go/Loki-fork oracles and local
Mimir/Loki/Tempo HTTP/Parquet controls cover admission and matching; Loki
parser controls cover captures and metric filtering. Numeric/repeated ASCII
names work in selectors and `label_replace`, with original numeric indices and
first-participating named expansion. Loki regexp parsers reject repeated raw
names but accept numeric destinations, normalized before collision suffixing;
first declared captures own normalized collisions, even when empty. Executed
Go/fork oracles and local Mimir/Loki/Tempo HTTP/Parquet/S3 regressions cover
these contracts, not full regex, client or capacity acceptance.
Negated scalar classes correctly exclude separately listed U+D7FF/U+E000
members across the surrogate hole, including raw/hexadecimal/range forms,
folding, captures and repetition. Independent Go/fork oracles and the same
local HTTP harnesses cover matching and rejection before storage.
Upgrade all query-serving app/native pairs to log tuple `{1,1,18}`; trace/metric
tuples, storage and keyed bytes are unchanged. See
[query regex semantics](querying.md#shared-query-regex-semantics).

Explicit LogQL logfmt extraction supports last-definition duplicate destinations,
ordered source remapping and destination-key capture, and empty values for
replacement-character input. Shared-source aliases select one lexical destination
instead of Loki's nondeterministic map choice. Hint-dependent early exits and
broader JSON/parser grammar remain incomplete; see
[query semantics](querying.md#parser-labels-and-quantities).

Loki request-local policies also support `maxQueryInterval`,
`maxEntriesLimitPerQuery`, `requiredLabels` and `minimumLabelsNumber`.
Twenty-five pinned engine/middleware admission cases replay through 64 HTTP
requests, with additional nonempty Parquet/S3 and pre-read rejection controls.
Parenthesized log pipelines before range brackets are accepted. These are
optional client restrictions with existing server budgets, not configured
operator quotas. `maxQueryTime` also tightens the query-worker timeout on all
finite reads without raising the server cap. Blocked-adapter GET/form-POST
controls cover all 15 finite request shapes, and an actual blocked S3 GET checks
timeout recovery. Already-dispatched native/provider work may outlive callers.
Lookback, byte and sharding policies remain
unsupported; see [query limits](querying.md#limits-and-metric-evaluation).

Loki HTTP parameters have 87 frozen rows across 15 complete pinned request and
component tables, including all 35 rejection expectations. Component replay
covers 56 rows; HTTP/native Parquet/owned-loopback-S3 replay covers 51 request
rows (20 overlap), through 82 read attempts including five WebSocket handshakes.
Public HTTP assertions check observable bounds/selectors/grouping/buckets rather
than Go structs; rejected attempts perform no provider requests. Decimal-second
timestamps use float64/millisecond fractional rounding, directions are
case-insensitive, `step` accepts float seconds/durations, `since` governs default
bounds, and repeated/mixed or omitted/lone-empty series selectors work. Positive
log intervals sample globally before limits under bounded collection/sorting;
zero retains streaming top-k. Existing endpoint/scan/work/heap/inclusive-point
ceilings remain. A separate calendar continuation replays all 16 original Go
long-fraction rows plus 89 authored actual-Go helper controls. It accepts
single-digit hours, comma fractions and Go's inclusive 24-hour/60-minute zone
bounds while retaining exact nanoseconds and Pulse's int64/128-byte ceilings.
Six successful spellings and six rejection controls exercise 72 GET/form-POST
query attempts against native Parquet/owned-loopback S3. This is selected
grammar evidence, not exhaustive RFC3339 acceptance. Stream discovery now
uses first-value scalar precedence for `query`/`start`/`end`/`since`, with form
values before URL values. Ninety-seven authored HTTP attempts cover nonempty
retained dictionaries, empty/default and invalid-first values, and unchanged
selector unions; all 27 rejected requests perform no provider work. Prometheus
duplicate rejection and discovery ceilings remain unchanged. A literal-name
continuation adds 66 GET/form-POST attempts: 44 nonempty dictionary successes
and 22 rejections without provider work. Bracketed scalar names remain unused
literal keys, not Plug-expanded arrays/maps; explicit malformed scalar values
still reject. Twenty-eight executed Go 1.27.3 form controls independently cover
literal lookup, first values and body-before-URL precedence, not Loki HTTP.
Index statistics now validates the range-query superset too: uint32 limit,
direction, positive step/11,000 integer intervals and nonnegative interval.
Forty-four authored GET/form-POST attempts cover 12 complete metadata estimates
and 32 pre-provider rejections; accepted parameters do not truncate estimates,
and stats still never reads Parquet payloads.
Scalar precedence on other Loki endpoints, exact HTTP error bodies, tail scheduling and
engine/client/deployed-capacity parity remain open. See the
[source-table qualifications](../test/fixtures/logs/loki-upstream/http-parameters.md)
and [calendar oracles](../test/fixtures/logs/loki-upstream/http-calendar-timestamps.md).

Detected-field requests also follow Loki's legacy limit fallback: missing/empty
`limit` selects `field_limit`, while a nonempty primary value keeps precedence.
Twelve authored combinations exercise 48 GET/form-POST attempts across fields
and field values with nonempty native Parquet/owned-loopback-S3 results; all
24 invalid requests reject before provider work. The 5000 endpoint ceiling
remains stricter than the upstream uint32 helper. These are supplementary
source-derived controls, not additional frozen upstream table rows.

Detected-field step admission follows the pinned request parser: a minimum of
1 ms and at most 11,000 integer-truncated intervals, using the original duration
before millisecond truncation. Nineteen authored controls exercise 76 GET/form-POST
attempts across fields/values, including both interval-boundary sides and 1.5 ms
precision; 40 rejections prove no provider requests, while 36 successes retain
the expected sampled fields/values. This is HTTP admission, not new bucketing or
full detected-field sampling/diagnostic parity. Existing resource limits remain.

The complete pinned `TestNestedJSONFieldDetection` retains both original
two-line setups: seven valid nested-field path/type oracles and ten difficult-key
path oracles. The latter previously returned an empty public response because
its objects contain trailing commas. A detector-local, string-aware fallback
now removes only terminal object commas before strict decoding of the whole
result. GET/form POST replay preserves original line bytes, paths and the valid
pair's types through native Parquet/owned S3. Authored repaired/string-escape/
malformed-input controls distinguish this from broad JSON leniency; arrays,
transport JSON and ordinary LogQL `| json` retain their existing grammar.
Newest-line sampling, no-provider auth/admission rejection and scan exhaustion
remain covered. This is detector compatibility, not complete malformed-input,
duplicate-key, parser-hint or upstream HTTP-envelope parity.

The complete pinned numeric-boolean `TestQuerier_DetectedLabels` subtest now
retains its three-name oracle through public GET/form POST. All five original
names and nine values are adapted from the ingester mock into singleton-label
streams; `/series` independently verifies their native-Parquet/S3 persistence.
Label suggestions now keep nonempty value sets containing only literal `0`/
`1`, not arbitrary signed/decimal numeric spellings. Static-label and other
numeric/UUID filtering, integer-first field typing and resource ceilings stay
unchanged. Separate controls cover singleton/pair/mixed sets, absent windows,
authorization, admission and fail-whole scans. The source mock, carrier lines,
time window and exact-cardinality checks are distinguished; no upstream-server,
HLL-estimation or deployed-client parity claim.

Detected JSON field values also follow the existing frozen JSON parser's
`utf8 error rune` oracle: decoded U+FFFD becomes a space. Public GET/form POST
previously retained U+FFFD even though ordinary `| json` already matched the
original complete three-field oracle. The detector now applies that cleanup
only to decoded JSON string values, not stored lines, keys/paths or structured
metadata. This reuses an existing source row, not an additional imported case;
the detector route/window and boundary/auth/resource controls are authored
adaptations. No transport decoder, native/storage-format or resource-limit change.

Automatic detected logfmt fields also preserve first-retained extraction
ownership after key sanitization and stream-label suffixing. The existing frozen
`duplicate from line property` row (`parser_test.go:1301–1311`) previously
returned the later `10ms` value rather than original `foo bar`; an explicit
`| logfmt` pipeline could then show both. Ordinary parsing already matches the
complete source oracle. The detector now retains the first final destination,
including normalized aliases and suffix collisions, without changing metadata,
raw bytes or resource policies. HTTP detector replay is an authored adaptation
of the existing parser row, not a new source import or full detector parity.

Loki's complete `Test_writeError` table is frozen separately: 25 original rows,
each with direct and gRPC-status-roundtrip assertions (50 upstream executions,
not 50 Pulse tests). Four direct categories have adapted public HTTP checks:
parse/interval 400, deadline 504 and internal worker failure 500. The remaining
21 direct rows and all internal roundtrips retain explicit gaps or incompatible
contracts; none are skipped and counted as passing. JSON/sanitized bodies,
default-tenant behavior and storage 503 remain deliberate differences. The
98 error HTTP attempts cover both methods and all 15 finite-read shapes where
applicable; storage failures no longer expose provider terms, and a native
Parquet/owned-S3 read verifies recovery. Cancellation/499, gRPC/aggregate-error
precedence remain open.
See the [complete error ledger](../test/fixtures/logs/loki-upstream/http-errors.md).

The separate classifier/limit continuation freezes all 22 `TestClassifyFailure`
rows, three wrapped-limit rows and the complete prefix-template constraints.
Pulse has no category/reason classifier: its bounded operational counters retain
success/error/exception outcomes, not Loki's reason labels. Those 22 rows and
prefix matching remain explicit unimplemented internal contracts, not passing
replays. Public equivalents of two wrapped-limit rows verify entry-count and
query-length HTTP 400 admission. The entry message matches exactly inside JSON;
length diagnostics still render exact nanoseconds instead of `800h`/`721h`.
Go sentinel identity/wrapping and the query-byte policy remain unimplemented.
Boundary controls accept a requested log limit of 5000 and a 721-hour window,
rejecting one entry/nanosecond over, with no provider access for rejections and
nonempty native Parquet/S3 reads for acceptance. Provider strings matching the
three source limit bodies remain
sanitized 503, never inferred client errors. These are 36 authored public HTTP
attempts, not 36 upstream rows. See the
[classifier/limit ledger](../test/fixtures/logs/loki-upstream/error-classification.md).

The complete pinned Loki `ParseTestCases` table preserves 206 original rows
(159 admissions/47 rejections), duplicate rows, exact invalid UTF-8 bytes,
symbolic Go ASTs and original diagnostics. Component admission and 824
authenticated GET/form-POST attempts across instant/range endpoints replay
every row. Admission agrees on 204; two existing policies deliberately differ:
invalid line regexes reject eagerly before storage, while empty selectors stay
allowed within server budgets. All 188 rejected attempts prove no provider
access. Empty-store success statuses are admission evidence, not result-value
oracles; a separate nonempty native Parquet/S3 count control checks execution.
No runtime change, Go AST equivalence or exact diagnostic parity is claimed.
See the [syntax-admission ledger](../test/fixtures/logs/loki-upstream/syntax-admission.md).

The three complete matcher-admission tables retain 30 original rows (15 accepts/
15 rejections), five literal matcher tuples and all 13 exact source error
constructors. Component and authenticated HTTP replay cover every row. Eighteen
admission outcomes agree; 12 selectivity-policy rejections deliberately differ
because Pulse admits empty, negative-only and empty-compatible selectors under
existing server budgets. Matcher-only discovery still rejects pipelines.
All eight rejections among 112 table HTTP attempts avoid provider access.
Ten separate nonempty native Parquet/S3 read controls verify full-value regex
selection, negative regexes and negative-only log/metric execution, including
missing labels. No production change or exact diagnostic parity is claimed.
See the [matcher-admission ledger](../test/fixtures/logs/loki-upstream/matcher-admission.md).

The complete label-parsing continuation preserves four original label maps,
four unreserved-name admissions and the trailing 16 MiB rejection. Native
protobuf and authenticated HTTP/Parquet/S3 replay cover all nine source cases.
All four public discovery maps agree, but raw empty labels remain stored by
design; this is not Loki's write-time normalization. All four original queries
accept `variants`/`of` as selector, grouping and pipeline labels. Authored
nonempty controls check actual lines/labels/counts. The oversized input rejects
before provider access with HTTP 413 at the decompressed-request cap, not an
isolated Go label-parser limit. A smaller malformed input uses 204 with one
rejected entry and no publication; valid ingestion/read recovers. The 34 HTTP
requests do not establish exact errors, Go-label ordering or broad grammar/
capacity parity. No production behavior or limits change. See the
[label-parsing qualifications](../test/fixtures/logs/loki-upstream/label-parsing.md).

Complete formatter/round-trip source coverage preserves 196 rows across 20
functions, including all eight prettier functions, 94 literal outputs, four
rejection oracles and symbolic internal serialization. **LogQL formatting and
Loki AST JSON round trips remain unimplemented**, not passing ports. Component
and 1,032 authenticated HTTP attempts check admission of all 185 literal inputs
and 73 applicable output spellings. Dotted logfmt sources, invalid IP operators
and empty IP patterns reject during executable validation despite grammar-only
source success. All four ordinary zero-rank rejection oracles remain explicit
differences: Pulse accepts and returns empty results. Another 338 nonempty reads
check 36 stringer equivalences, two rejected pairs, zero-rank behavior, escaping
and no-op semantics against actual Parquet/S3. Five seed writes bring the total
to 1,375 HTTP requests. Layout, exact formatting/errors, internal optimization,
serialization and deployed/capacity parity are not claimed. No production change
is made. See the [formatter/round-trip ledger](../test/fixtures/logs/loki-upstream/formatter-roundtrip.md).

Complete pipeline ownership source coverage preserves six functions and 48
method executions. Thirty ordinary executions agree on original label ownership,
asserted lines and selected parser-error details through component replay and
240 authenticated HTTP reads over native Parquet/owned S3, in ordinary and
categorized modes. The remaining 18 deletion-wrapper executions are symbolic,
not supported delete semantics. Go hashes, label rendering/cache identities and
the internal empty-keep constructor are not claimed; public replay omits that
identity stage. No production behavior changes. See the
[pipeline ownership ledger](../test/fixtures/logs/loki-upstream/pipeline-ownership.md).

The complete label-builder source inventory retains all 15 tests, 107 assertion
sites and 118 expanded events. Component and 232 authenticated HTTP reads cover
literal lookups/categories, deletion/grouping maps, all nine ordinary
preserve-error identities and distinct original collision inputs through native
Parquet/S3. Received exact error metadata now appears in the parsed category;
ordinary suffixed names, unflagged values and metric-error admission are unchanged.
Raw builder setters, arbitrary error injection, hash/String/cache and hint flags
remain symbolic, not passing ports. Upgrade query-serving applications; native
tuples, resource ceilings and storage/keyed bytes are unchanged. See the
[label-builder ledger](../test/fixtures/logs/loki-upstream/label-builder.md).

Complete sample-extractor source coverage retains 16 tests and 106 method calls,
including 88 ordinary and 18 symbolic deletion-wrapper executions. All 88
ordinary observations replay through both the component query interface and
public HTTP/Parquet/S3, including the three original `trace_id` cases.
Dedicated nonempty trace/span IDs now fill absent metadata names without
overwriting attributes or becoming stream labels. Explicit empty attributes,
stream/parser collisions and native label-cache isolation have separate controls.
Error-preservation and stream-isolation controls bring the source replay to
398 reads plus three pushes. Numeric hash bits, optimized Go types/cache/reference
identity and hint contracts are not claimed. Upgrade query-serving app/native
pairs to `{1,1,18}`; budgets, storage and keyed bytes are unchanged. See the
[sample-extractor ledger](../test/fixtures/logs/loki-upstream/sample-extractors.md).

LogQL range pipelines may precede or follow the bracket/offset, and complete
ranges may be parenthesized recursively. Seventeen original first/last engine
oracles replay in six equivalent placements; split pipelines and invalid
post-unwrap stages still reject before storage. Existing depth/budget ceilings
apply. This closes range placement, not general parser-error or hint parity.

LogQL `label_replace` rewrites final metric labels in instant/range queries,
with anchored captures, missing-source defaults and destination deletion.
Loki's non-dot-all regex default is preserved. All 19 evaluations from the
pinned engine block retain their original 64 loaded entries and output oracles
through HTTP GET/form POST and Parquet/S3; local controls cover nested policies,
capture expansion, newline flags and nonaggregating instant collisions. This
does not establish general parser-error, distributed or deployed-client parity.

Regexp/pattern parser admission, short-line pattern captures and string-only
`unpack` with `_entry` line replacement replay all 30 evaluations from the
remaining pinned parser-engine block through HTTP GET/form POST and Parquet/S3.
Constructor tables and nine unhinted unpack rows add regressions; 528 actual
pinned runtime pipeline comparisons agree. Malformed-input diagnostic and
hint-driven early-exit parity remain incomplete. Existing resource ceilings and
native/storage/keyed bytes are unchanged; upgrade query-serving applications.

`label_format` validates unique/non-error destinations and preserves ordered
renames, self-rename deletion and first-template label snapshots. The complete
three-row upstream validation table and four basic assignment rows replay
through HTTP/Parquet/S3, with stream/metadata/parsed and chained-stage controls.
Unicode literal prefixes preserve byte offsets in both line and label templates.
All 723 additional actual pinned pipeline comparisons agree.

Bounded string templates additionally support pipelines, parentheses, simple
Unicode case conversion, historical Go title casing, Unicode cutset trimming,
literal/counted replacement, repetition, indentation, Unicode-scalar alignment,
byte-based truncation/slicing, signed-int64 constants, query-form URL escaping,
Base64 encoding/decoding, defaulting and current-line lookup. Conditional
`if`/`else if`/`else`, lazy `and`/`or`, `not`, typed comparisons and byte `len`
are supported; all branches validate before storage, but only selected branches
execute and share one output cap. Sixty-five adapted upstream formatter evaluations replay
through HTTP/Parquet/S3. Separate runtime comparisons cover every Unicode scalar
under upper/lower and title/boundary contexts. Expanding functions enforce the
16 MiB intermediate-output ceiling before allocation, even under a later trim.
Base64 corruption returns ordinary Go-compatible byte-offset diagnostic strings.
Another 32,298 actual pinned runtime comparisons cover conditional/logical/
comparison behavior and admission, excluding exact runtime error details.
Literal ASCII-whitespace trim markers and non-nesting template comments follow
Go delimiter rules, without trimming rendered values or Unicode spaces.
Fifteen Go lexer/parser rows replay through the Loki HTTP/storage path, with
AST/token expectations adapted to rendered output or rejection; they are not
additional Loki source rows. Another 29,826 actual pinned Loki comparisons agree
on trim/comment admission, output, errors and label categories, excluding exact
runtime error details. Existing output ceilings remain authoritative.
Integer helpers `int`, `add`, `sub`, `mul`, `div`, `mod`, `min` and `max` support
string/boolean conversion, exact decimal truncation, base-zero parsing and
signed-int64 wrapping. Invalid/overflowing conversions return zero; zero division
preserves inputs with `TemplateFormatErr`. Another 20,826 actual pinned pipeline
comparisons agree, including 1,458 runtime errors, excluding exact error details.
Quantity helpers `bytes`, `duration` and `duration_seconds` retain typed float64
results with Go general-format rendering, numeric-zero defaults/truthiness,
float comparisons and in-range truncation for integer helpers. Invalid quantities
preserve inputs with `TemplateFormatErr`. Of 66,570 actual pinned pipeline
comparisons, 66,438 agree exactly (excluding error details) and 132 deliberately
reject out-of-range float-to-integer casts instead of selecting Go's
implementation-dependent overflow value. No unexpected differences remain in
this batch; those nonportable casts are not an exact upstream-parity claim.
Regex `count` supports integer non-overlapping counts with Unicode-scalar empty
matches, ASCII Perl classes/word boundaries and Unicode script properties.
Non-backtracking native matching retains no match list and charges each match
plus a final probe to shared metric work or request-local stream work across
entries/actions. Invalid patterns preserve inputs with `TemplateFormatErr`;
work exhaustion fails whole even under explicit error selection. Upgrade
query-serving apps/native artifacts to log tuple `{1,1,10}`; storage/keyed bytes
are unchanged. Another 29,952 actual pinned Loki pipeline comparisons agree,
including 3,120 runtime errors, excluding exact error details.
`regexReplaceAll` expands Go-style whole-match/numbered/named captures and
literal dollar escapes; `regexReplaceAllLiteral` inserts replacement text
verbatim. Both share `count`'s native regex profile and request work budget.
Output admission and rendering each charge probes and dollar-expansion work,
including capture-name bytes even when an unknown reference emits nothing.
Without retaining matches, the complete result fits 16 MiB before allocation,
even under later truncation. Another 107,520 actual pinned Loki pipeline
comparisons agree, including 15,360 runtime errors, excluding exact error
details. All 87 Go replacement table rows retain their original oracles through
135 successful mode evaluations, including ten formerly rejected repeated-name
cases. Template helpers accept numeric/repeated ASCII names in both Go spellings
and literal `\Q...\E` runs, including EOF-terminated runs. Named expansion picks
the first participating capture, including an empty match; numeric references
preserve Go's leading-zero and one-billion cutoff rules. Additional duplicate
lookups spend shared work even when they emit nothing. Selector/regexp-parser
admission and full Go regexp syntax/capacity parity remain separate gaps.
Template helpers also accept Go octal escapes in patterns, consuming up to
three digits with Unicode-character semantics through 0777. Nonzero single
digits remain unsupported backreferences. Classes, quantifiers and literal
quoting keep their meanings; these escapes do not expand selector/parser syntax.
Typed JSON and object/array iteration are covered by the continuation below.
Timestamp/Unix helpers are covered by the continuation below. Channel/function
iteration, remaining date functions, non-UTF-8 decoded/sliced values,
exact template errors and general
pipeline-error ownership remain incomplete; this is not full formatter parity.
The complete four-oracle `formatters.logqltest:85–105` block now preserves
active error details across ordinary label formatting. Hidden ordinary values
survive error resets and renames; templates, filters and grouped output retain
their distinct lookup rules. Thirteen additional actual pinned Loki pipeline
comparisons cover those ownership distinctions, separate from upstream engine
rows. Native reserved-label and complete diagnostic parity remain open.

Finite template float literals preserve decimal/scientific/hexadecimal syntax,
signed zero and Go's direct-constant versus typed-pipeline integer argument rules.
All ten original non-complex Go float-number oracles replay through HTTP/Parquet/S3.
Of 6,912 actual pinned Loki pipeline comparisons, 6,874 agree exactly excluding
error details, and 38 deliberately reject nonportable out-of-range integer casts;
there are no unexpected differences. These are not full Go-template/client or
capacity acceptance. Upgrade query-serving apps; no native/storage/keyed-byte change.

Finite complex template constants preserve both components, signed zeros,
truthiness, complex-only equality, generic numeric coercion to zero and
direct-constant versus typed-pipeline numeric arguments. Seven original Go
number rows and separate controls replay through HTTP/Parquet/S3; 8,240 actual
pinned Loki pipeline comparisons agree, including 4,744 runtime errors,
excluding exact diagnostics. These are supplementary Go number oracles, not
additional Loki formatter-source rows. Malformed/overflowing components reject
before storage. Existing nonportable integer-cast exclusions, resource ceilings
and native/storage/keyed bytes are unchanged; upgrade query-serving apps.

Template root maps and `index` support arbitrary string-key label lookup,
missing-key empty values, sorted rendering, map length/truthiness and successive
string-byte indexing. Unsigned byte values preserve comparison/conversion and
typed-argument distinctions. Two original Go comparison regressions replay
through HTTP/Parquet/S3; 7,638 actual pinned Loki pipeline comparisons agree,
including 4,442 runtime errors, excluding exact diagnostics. Root-map output
overflow fails whole even before later drops or explicit error selection.
This is not generic array/JSON-object/field-chain or full built-in parity.
Existing resource ceilings and native/storage/keyed bytes are unchanged;
upgrade query-serving apps.

Template `slice` supports string byte ranges with default indices, exclusive
ends, empty results and integer/uint8 indices; invalid bounds/types fail with
`TemplateFormatErr`. All six original Go string cases replay through
HTTP/Parquet/S3, with separate pipeline/conversion/Unicode controls. Of 4240
actual pinned Loki pipeline comparisons, 4076 agree excluding exact diagnostics
and 164 deliberately reject non-UTF-8 intermediate byte strings; no unexpected
differences. Array slicing and byte-string propagation remain open. Existing
resource ceilings and native/storage/keyed bytes are unchanged; upgrade query apps.

Template `print`, `println`, `html` and `urlquery` support variadic typed values,
Go argument spacing/newlines, explicit HTML escaping and query-form escaping.
Seven original Go cases and seventeen controls replay through HTTP/Parquet/S3;
8504 actual pinned Loki pipeline comparisons agree, including 1488 runtime
errors, excluding exact diagnostics. Combined text/escaped output retain the
16 MiB fail-whole cap; dense HTML escaping stays within the worker heap.
`printf`, typed-interface/pointer values and byte-string propagation remain
open. No native/storage/keyed-byte change; upgrade query-serving applications.

Template `js` adds Go JavaScript text escaping, including variadic typed/nil
joining, ASCII controls and Unicode 17 printability. All eight upstream Go
escaping rows plus fourteen successful controls and three nested runtime errors
replay through HTTP/Parquet/S3. All 19060 actual pinned Loki pipeline comparisons
agree, including 304 runtime errors, excluding diagnostics; grouped Unicode
inputs cover all 1112064 valid scalars. Exact 16 MiB output and fail-whole
intermediate overflow replay through log/top-k/metric paths. This preserves Go's
minimum-width escapes, not JSON string quoting or context-aware sanitization.
Existing ceilings and native/storage/keyed bytes are unchanged; upgrade query apps.

Template `with`/`else with` actions change dot only inside successful branches;
false branches and later actions retain it. `$` preserves the formatter's root
label snapshot, including across label-format destinations, refreshed by a later
stage. Ten original Go cases plus nested/typed/error/admission controls replay
through HTTP/Parquet/S3. All 2387 actual pinned Loki pipeline comparisons agree,
including 516 runtime errors, excluding diagnostics; six syntax/function
rejections also match actual Loki. Exact 16 MiB and accumulated outer/branch
overflow checks retain existing fail-whole policies. Generic object iteration
remains unsupported. Existing ceilings/native/storage/keyed bytes are unchanged;
upgrade query-serving applications.

Template action and `if`/`with` header variables support declarations,
nearest-binding assignments, shadowing/restoration, typed values and saved-map
lookup. Bindings reset across templates/destinations/entries; `$` reassignment
does not mutate the root label snapshot. Three original Go assignment rows,
26 successful controls, ten runtime failures and admission/budget controls replay
through HTTP/Parquet/S3. All 6198 actual pinned Loki pipeline comparisons agree,
including 1454 runtime errors, excluding diagnostics. Eight upstream admission
failures agree. The nested-binding continuation removes the former stricter
parenthesized-pipeline rejection: arguments thread bindings left to right,
lazy operators skip side effects and forward references still reject before
storage. Its 16,622 actual pinned Loki comparisons agree, including 3764 runtime
errors, excluding diagnostics, with unchanged accumulated/intermediate caps.

Template field chains support label-map variables, functions and parenthesized
results, retaining Go's distinct missing-string/nil behavior and skipping field
arguments on nil receivers. Four unchanged Go source rows plus 14 successful,
ten runtime-error and seven admission controls replay through HTTP/Parquet/S3.
The combined 18,838 actual pinned Loki comparisons agree, including 5278 runtime
errors, excluding diagnostics. The JSON continuation below adds typed containers;
methods and full formatter/client/provider/capacity parity remain open.
Existing ceilings/native/storage/keyed bytes are unchanged; upgrade query-serving
applications.

Template `range` supports lexical label-map and integer/uint8 iteration,
single/two-variable bindings where applicable, empty/nil else paths and nested
`break`/`continue`. Dot/root and per-iteration/block scope match the current Go
value profile. Ten unchanged Go parser admission rows, 26 successful controls,
ten runtime errors and syntax/budget controls replay through HTTP/Parquet/S3.
The combined 21,304 actual pinned Loki pipeline comparisons agree, including
5388 runtime errors, excluding diagnostics; 29 constructor rejections also agree.
Each executed iteration shares metric query work or request-local stream-template
work with regex helpers, even without output. Work/output exhaustion fails whole;
early exit charges actual iterations without allocating integer ranges. The
64-expression and 16 MiB caps remain. The JSON continuation below adds object/array
iteration. Channel/function iteration, date/other functions and exact diagnostics
remain open. Upgrade query applications; native/storage/keyed bytes and dependencies
are unchanged.

Template `fromJson` supports typed nested objects/arrays, float64 numbers,
booleans, strings and nil. Field/key/index lookup, container printing/length/
truthiness, numeric coercion, iteration and duplicate-key replacement preserve
the pinned runtime's distinctions from string-valued root labels. Both complete
Sprig v3.3.0 `TestFromJson` oracles plus 29 successful controls and 19 runtime
failures replay through authenticated GET/form POST and native Parquet/S3.
All **10,292 actual pinned Loki pipeline comparisons** agree, including 3874
runtime errors, excluding exact diagnostics. Overflow-to-zero behavior is pinned
to Loki's actual Go 1.27.3 runtime, not an assertion about older Go JSON decoders.
Malformed documents return nil; lone escaped surrogates become replacement
characters. These supplementary Sprig rows are not additional Loki integration
rows, and the comparisons do not establish provider/client/capacity parity.

Each executed decode charges input bytes before expansion to metric query work
or request-local stream-template work, shared with loops/regex helpers. Input
and normalized bytes cap at 16 MiB; containers reuse the 64-level nesting cap.
Growth is checked before allocation and work/size/depth exhaustion fails whole,
including explicit error selection. Public budget controls cover exact output,
raw/normalized overflow, shared entries/actions and nesting. Methods,
channel/function iteration, date/other functions, non-UTF-8 byte
propagation and exact diagnostics remain open. Upgrade query-serving apps;
native/storage/keyed bytes and dependencies are unchanged.

Template array `slice` supports default/exclusive/three-bound indices, retained
decoded backing elements and explicit reduced capacity without copying arrays.
Indexing, iteration and other consumers respect the current view. Ten original
Go slice oracles plus 18 successful/13 failure controls and two explicit
spare-capacity rejections replay through HTTP/Parquet/S3. Of 5984 actual pinned
Loki comparisons, 5980 match, including 4304 runtime errors; four deliberately
reject Go allocator spare cells. No unexpected differences, excluding diagnostics.
Initial capacity is the decoded element count, not Go allocator capacity;
spare-cell access remains a compatibility gap. Shared work and exact 16 MiB/
overflow controls cover ordinary/top-k/metric paths despite error selection or
later shrinking. No native/storage/keyed-byte/dependency/ceiling change; upgrade
query apps. This does not establish full formatter/client/provider/capacity parity.

Template `__timestamp__`, `unixToTime`, `unixEpoch`, `unixEpochMillis` and
`unixEpochNanos` retain typed times and exact source nanoseconds through both
formatters. Unix parsing follows byte-length units, signed-int64 admission and
wrapping; epoch seconds/milliseconds round down before zero. Seven original
Loki formatter rows and both invalid-time inputs replay through authenticated
HTTP and native Parquet/S3, with separate source-time, boundary, scope, wrapping
and error-selection controls. All 28,292 pipeline comparisons against pinned
Loki/Sprig helpers through Go text/template agree, including 100 runtime errors,
excluding diagnostics. Pulse renders time values in UTC, not the host-local
timezone used by Loki. Arbitrary date layouts, named zones, time methods and
`now` remain open. Existing budgets/native/storage/keyed bytes/dependencies are
unchanged; upgrade query applications. This is not full date/client parity.

Template untyped `nil` supports false truthiness/defaults, equality, zero numeric
coercion, function-result `<no value>` rendering and distinct print/escape
representations and spacing. Bare nil commands and typed-argument failures remain
runtime `TemplateFormatErr`, not admission errors; missing labels stay empty
strings. Three original Go cases plus successful/error/admission controls replay
through HTTP/Parquet/S3. All 7528 actual pinned Loki pipeline comparisons agree,
including 812 runtime errors, excluding exact diagnostics. Existing budgets and
native/storage/keyed bytes are unchanged; upgrade query-serving applications.

Template `float64`, `minf`, `maxf`, `ceil`, `floor` and `round` support coercion,
signed zero/nonfinite runtime values, typed float comparisons and integer
precision/float thresholds. Three original Loki formatter rows replay through
HTTP/Parquet/S3; 27,928 actual pinned parser/pipeline comparisons agree, including
30 runtime errors, excluding exact diagnostics. Rounding preserves the pinned
Go 1.27.3 fused-residual profile, not a cross-compiler/platform bit-parity claim.
An independent control records that this runtime rounds `123.5555` to `123.555`
at three places, unlike Sprig's static `123.556` test expectation; this is not
claimed as an unchanged Sprig table replay. Nonportable float-to-integer casts
still deliberately reject. Existing resource ceilings and native/storage/keyed
bytes are unchanged; upgrade query-serving apps.

Template `addf`, `subf`, `mulf` and `divf` use float64 coercion followed by exact
shortest-decimal arithmetic, rounding once on function return. Division rounds
each step to 16 decimal places, halfway away from zero. Two original Loki rows
replay through HTTP/Parquet/S3; all 14,012 actual pinned pipeline comparisons
agree, including 1,524 runtime errors, excluding exact diagnostics. Controls
distinguish decimal cancellation and variadic order from binary arithmetic,
input precision loss, underflow/overflow, nonfinite/zero-division failures and
preserved metric errors. Existing ceilings and native/storage/keyed bytes are
unchanged; upgrade query-serving apps. This is not full formatter/client or
capacity acceptance.

Template rune constants retain integer code-point values, including hex/octal
byte escapes without creating byte strings. Eight original Go number oracles,
three original rejections and all seven selected lexer character tokens replay
through HTTP/Parquet/S3, separately from the 65 Loki formatter evaluations.
Malformed constants reject even in skipped branches; type errors preserve inputs
and existing metric-error selection. Another 10,400 actual pinned Loki pipeline
comparisons agree, including 2,600 runtime errors, excluding exact error details.
Upgrade query-serving applications; no additional native/storage/keyed-byte change.

The Loki conversion-diagnostic gap now excludes numeric, duration and byte errors:
filters and unwrap expose Go-compatible details, including duration byte-oriented
escaping, byte numeric-prefix errors, normalized unknown suffixes and overflow
precedence, and numeric syntax/range failures with Unicode 17 Go quoting.
Exact-detail selectors work through HTTP without changing
error-preservation policies or budgets. Quoted/raw strings now follow Loki's
scanner and Prometheus decoder, including raw byte escapes, literal carriage
returns, surrogate replacement and signed-int32 escape overflow. Single quotes,
unknown/incomplete escapes, literal NUL and invalid UTF-8 source reject.
The 104 frozen cases and HTTP/Parquet/S3 regressions close literal decoding,
not exact parser-error text/positions, full LogQL or client acceptance. See
the [query contracts](querying.md#parser-labels-and-quantities) and
[string-literal fixtures](../test/fixtures/logs/loki-upstream/README.md#string-literal-continuation).

LogQL vector `sum` now uses compensated summation as well as `sum_over_time`.
The pinned Loki `TestVectorAggEvaluator_Precision/sum()` oracle retains all
10,001 original values (`1e16`, then 10,000 ones) and the exact expected
`10000000000010000`. Distinct streams adapt the unit inputs into a public
vector; a sorted instant wrapper restores original numeric order. Authenticated
instant/range GET/form POST replay through native Parquet/S3, with the later
empty window omitted. This is an explicit unit-to-HTTP adaptation, not an
unchanged upstream HTTP scenario. Existing float64 and resource bounds remain.

Four unchanged `range_aggregations.logqltest:409–440` evaluations and all five
original inputs now replay malformed-JSON quantiles through HTTP/Parquet/S3.
Missing/empty unwrap targets supply no observation, so prior parser errors
cannot fail those aggregates. Usable targets and count/bytes observations keep
their error guards. Separate native-eligible/fallback controls and direct native
Parquet replay protect path parity and sample/work accounting. Upgrade all
query-serving app/native pairs to log tuple `{1,1,18}`; storage/keyed bytes and
resource ceilings are unchanged.

Five unchanged `range_aggregations.logqltest:1727–1745` absence evaluations
retain both original streams and malformed JSON. Unwrapped-free
`absent_over_time` omits unused plain JSON extraction only when the entire
pipeline contains plain JSON and line filters. Label/error/format consumers,
explicit extraction and other parsers keep normal execution; metadata errors
and admission/work/scan policies remain intact. General hint-driven parser
parity stays open. This is application-only; log tuple `{1,1,18}` is unchanged.

The complete `log_selection.logqltest:28–36` case retains its two original
lines and start-inclusive/end-exclusive selection oracle. External raw-log
`/query_range` now excludes the line exactly at `end` before top-k selection;
metric ends, instant logs, other APIs and shared storage/MCP bounds remain
unchanged. Equal windows remain empty with ordinary validation and resource
admission. Upgrade query-serving applications; no native/storage-byte change.

Logfmt log-line decoding is a separate covered slice: default recovery, strict
`LogfmtParserErr` byte positions, empty-value policy, normalized first duplicates
and quoted Unicode/surrogate decoding replay all 60 selected upstream
unit/engine evaluations through authenticated HTTP and native Parquet/S3.
Explicit-field source grammar/admission, normalized-key lookup and absent-source
defaults add 15 frozen unit-table rows and separate HTTP controls. One row's
ingest-promoted `detected_level` is asserted separately from Loki's unit oracle;
the empty-expression rejection follows the pinned parser rather than a nil-error
assertion in that test table. The three original expression engine evaluations
remain in the 60-case replay, not counted again.
Thirteen formerly omitted table/engine evaluations now cover structured-metadata
collisions, dropped stream names and categorized output through the same stack.
Additional controls cover repeated parsers, retained extraction history after
drops, explicit JSON overwrites and explicit-logfmt suffix halting. Another
1512 actual pinned pipeline comparisons agree. These do not establish full JSON
parsing or hint-driven early exits. Upgrade every
query-serving app/native pair to log tuple `{1,1,10}`; storage/keyed bytes and
resource ceilings are unchanged. See the
[logfmt fixtures](../test/fixtures/logs/loki-upstream/README.md#logfmt-decoding-continuation).

Plain JSON parsing now preserves source order, first duplicate/sanitized-target
ownership, nested object flattening, scalar numeric spelling and array/null
omission. Explicit JSON missing-source defaults preserve existing destinations,
unlike present nulls. All 16 upstream parser-table rows and 42 engine evaluations
replay through authenticated GET/form POST and native Parquet/S3, including
error-preserving grouped metrics and categorized output. The hinted table row's
public output is checked without exercising Loki's hint object. An additional
1216 actual pinned pipeline comparisons agree. This does not close malformed-input
partial extraction/diagnostic parity or hint-driven early exits. Evaluation remains bounded and outside native pushdown;
the log tuple, storage/keyed bytes and limits do not change further. See
[JSON fixtures](../test/fixtures/logs/loki-upstream/README.md#json-parser-continuation).

Explicit JSON paths now include dot/bracket keys, UTF-8 quoted keys, root/nested
array indices, source-preserving objects/numbers and whole-array escape decoding.
All 29 original expression rows, five constructor rejections, 11 nonempty grammar
paths, six grammar rejections and five engine evaluations replay over HTTP and
Parquet/S3. The grammar table's empty/nil-path row has no upstream error assertion;
it remains provenance, not an acceptance oracle. Pulse rejects empty paths.
Separate controls cover nested duplicates, source-order destinations, shared
paths, arrays and pre-read rejection. Another 3072 actual pinned pipeline
comparisons agree. Exact constructor/whole-parser diagnostic text, general
malformed-input and hint parity remain open; see
[explicit JSON fixtures](../test/fixtures/logs/loki-upstream/README.md#explicit-json-path-continuation).

Loki `ip(...)` line and label predicates now support original IPv4/IPv6 address,
CIDR and inclusive-range matching, negation and embedded-address scanning.
Missing labels, prior errors, mapped families and candidate boundaries retain
the pinned Loki behavior. Fifteen original upstream unit-table rows replay
through authenticated HTTP/Parquet/S3, with separate local pipeline/budget
controls; they are not fifteen integration suites. Invalid forms fail before
provider reads. Existing resource bounds and native/storage formats are
unchanged; IP evaluation does not use native pushdown. See the
[IP fixture provenance](../test/fixtures/logs/loki-upstream/README.md#ip-filter-continuation).
This closes IP predicates, not full LogQL, exact parser-error messages or
deployed-client/provider/capacity acceptance.

Loki line-filter `or` alternatives now work for substring, regex and pattern
operators, including mixed string/IP alternatives under `|=`/`!=`. Positive
groups keep any match; negative groups reject any match. All alternatives
validate before storage, and adjacent stages preserve their authored order.
Two HTTP/Parquet/S3 wrappers replay 27 original upstream matcher-table queries
(121 line decisions) and 29 engine evaluations (26 successful, three rejected),
with a separate local admission/budget control. This removes the line-filter
alternative gap, not full LogQL or exact parser-error text. Evaluation stays in
the bounded Elixir pipeline, without native pushdown or format/limit changes.
See the [line-filter fixtures](../test/fixtures/logs/loki-upstream/README.md#line-filter-or-continuation).

Loki label-filter comma and implicit conjunctions now parse, including mixed
`or` expressions with the pinned parser's right-attaching behavior. Explicit
`and` still binds tighter than `or`; both keywords are case-insensitive.
One authenticated HTTP/Parquet/S3 wrapper preserves 36 original engine
evaluations (27 successful, nine rejected), with a separate truth-table,
error-propagation and admission control. These are engine-script ports,
not additional service integration suites. Existing evaluation paths, budgets,
native/storage formats and generic metric-error envelopes are unchanged.
See the [conjunction fixtures](../test/fixtures/logs/loki-upstream/README.md#label-filter-conjunction-continuation).
Complete parser-error and deployed-client/capacity acceptance remain open.

The complete pinned Loki reserved-error-label comparison matrix adds 68 original
queries: 56 typed-comparison rejections and 12 string/ordinary-label admissions.
All replay over instant/range GET/form POST through native Parquet/S3; rejected
requests issue no provider operations. Typed comparisons on `__error__` or
`__error_details__` now return `parse_error` before evaluation, including nested
and post-unwrap predicates, rather than an evaluation-error category. Exact
full parser wording/positions remain open. Upgrade query-serving applications;
native/storage/keyed bytes and ceilings do not change. See the
[matrix provenance](../test/fixtures/logs/loki-upstream/reserved-label-comparisons.md).

The PromQL subset also includes eight optional-vector UTC calendar functions
(`year`, `month`, `day_of_month`, `day_of_week`, `day_of_year`, `days_in_month`,
`hour`, `minute`), natural `sort_by_label`/`sort_by_label_desc` with histogram
preservation, and quadrant-aware binary `atan2`. Range sorts bypass ordering
and emit query-local warnings; invalid histogram binary pairs emit operand-type
infos. Calendar exceptional-value conversions freeze Go 1.25 arm64 behavior;
natural-comparator empty/leading-zero ambiguities, cross-platform float bit
identity and upstream expression positions are not parity claims. The batch
adds 126 unchanged Mimir query-engine cases, replayed through HTTP with memory
and local S3/Parquet. See [query semantics and limits](querying.md) and
[fixture provenance](../test/fixtures/promql/mimir/README.md).

Six further scalar-function gaps are closed: `start`, `end`, `step`, `range`,
`min_of` and `max_of`. Query-context values retain requested outer boundaries
inside subqueries and remain source-local in batches; extrema preserve Go's
infinity/NaN precedence and signed-zero ties. Another 51 unchanged Mimir cases
run through HTTP on both storage adapters. Pulse retains nanosecond query-time
precision rather than upstream millisecond quantization. Selector `@` modifiers,
including `@ start()`/`@ end()`, are implemented by the separate time-modifier
batch below, not by these scalar calls alone.

Four aggregation gaps are also closed: population `stddev`/`stdvar`, per-step
`quantile` and float/native-histogram `count_values`. Another 88 unchanged Mimir
engine cases exercise grouping, changing membership, nonfinite values,
histogram omissions and complete histogram value labels over both storage
adapters. Invalid quantiles warn even on empty input. Generated value-label
overwrites follow Mimir's group-then-set contract, including retaining a label
named by `without`, where the pinned Prometheus engine differs. Sort and label
construction share query budgets; full language/annotation/client/capacity parity
remains open.

Histogram quantiles now warn for missing/malformed/NaN bounds, omit conflicting
classic/native identities per step, and distinguish real monotonic repairs from
silent floating-point adjustments. Native quantile/fraction NaN-observation
notices reach responses instead of being discarded. Twelve unchanged pinned
Mimir cases replay over both HTTP query endpoints and memory/Parquet/S3, with
separate collision, stale, numeric-boundary and source-isolation controls.
The plural `histogram_quantiles` function adds nine unchanged Mimir evaluations:
per-step quantile labeling, sparse range identities, duplicate-step failures,
mixed classic/native omission, NaN notices and composed native expressions.
Separate controls cover OpenMetrics labels, UTF-8 destinations, overwrites,
form POST and shared fan-out/bucket/label-work quotas. Intermediate fan-out is
reserved before construction; limits and native/storage bytes are unchanged.
Classic fractions add three unchanged Mimir evaluations and 14,400 actual pinned
Go comparisons: sorted/coalesced buckets, linear interpolation and no quantile
monotonicity repair. Another eight unchanged Mimir evaluations cover corrected
selected-bucket native NaN-sum interpolation and ±Inf sums without NaN-observation
notices. That correction intentionally supersedes Prometheus 3.5.0's last-bucket
quirk. Eight further unchanged Mimir evaluations cover count-based zero-point
extrapolation for native counter `increase`, including aligned/unaligned ends
and zero points inside/outside the requested range. One factor scales the whole
histogram; individual bucket increases need not stop at their final values.
Separate public controls cover `rate`, resets, negative sums, custom/negative/zero
buckets and unchanged `delta`/`irate`. Other native arithmetic and upstream
expression positions remain gaps. Generic classic-repair notices match the
pinned Mimir streaming engine; expanded summaries in its vendored Prometheus
engine are not a missing Mimir feature.

`idelta` adds the complete ten-evaluation Mimir engine block: last-pair float/
native subtraction, NaNs, short windows, gauge-type warnings, mixed sample/schema
omissions and custom-bound reconciliation. Native subtraction now coarsens
differing custom layouts to common bounds, matching 4,983 actual pinned Go
helper executions with bit-exact finite bucket results. Additional public controls
cover decreasing gauges, disjoint/asymmetric bounds, nanosecond observations,
anchors/subqueries, form POST, tenant/source isolation and shared budgets.
The complete eleven-evaluation `irate` block adds gauge/mixed-pair warnings,
schema-family resets and custom-bound changes without false resets. Custom
reset detection compares plain interval sums at common bounds including +Inf,
matching 9,950 executions of the actual pinned Go `FloatHistogram.DetectReset`.
Reset branches report no unexecuted subtraction notices. The complete four-case
`delta` block adds non-gauge/mixed-window warnings and full bucket outputs;
public controls distinguish whole-window float mixtures from endpoint-only
histogram schema/hint checks, custom reconciliation, extrapolation and isolated
batch notices. Eleven unchanged custom-arithmetic evaluations add mismatched-bound
`sum`/`avg`, sampling/counting/set controls and binary `+`/`-` with full outputs
and reconciliation info. Addition now uses common-bound compensated mapping,
matching another 9,950 executions of actual pinned Go `FloatHistogram.Add`
(compacted geometry, finite count/sum/bucket bits and reset hints). Binary
subtraction preserves gauge identity through nested queries; binary histogram
work spends the shared query/batch budget. Another 21 unchanged evaluations
cover complete range/group histogram aggregation blocks. Native sum/avg and
their over-time forms now report custom reconciliation, incompatible families,
mixed inputs and original reset-hint conflicts under shared bucket/bound work
limits. Public controls retain source names, stop notices at the first failed
family and isolate query-batch sources. Seven more unchanged counter-range
evaluations cover gauge/schema warnings, nested histogram-count calls and
first-pair layout resets. Rate/increase now report executed subtraction and
reset-addition reconciliation, preserve endpoint-versus-middle warning
precedence, and charge native bucket/bound work before traversal. Another 26
unchanged evaluations cover compensated histogram sum/avg and their over-time
forms, cancellation, overflow-driven incremental means, negative buckets and
singletons. Compensation survives resolution, zero-threshold and custom-bound
changes; public HTTP controls cover those transitions and bucket/zero-field
overflow independently of count overflow. An additional 55,112 actual pinned
Go `KahanAdd` executions across 10,000 chains agree on compacted geometry,
finite field bits and nonfinite classes. This is primitive validation, not
55,112 upstream engine tests. Implicit iterator-generated reset hints and
complete annotation parity remain gaps. Matching-layout/exponential reset
detection now traverses all remaining previous buckets, so leading zero buckets
cannot hide disappeared populations; zero widening uses the pinned compensated
traversal. Fifty thousand actual pinned Go `DetectReset` comparisons agree,
including custom/exponential layouts, both bucket sides, sparse tails,
zero/schema changes, nonreset controls and hint overrides. Public controls
exercise `resets`, `irate`, `rate` and `increase` through both storage adapters.

Another 25 unchanged evaluations cover the complete native multiplication/
division and mixed-arithmetic blocks. Negative scaling and unary negation now
produce gauge histograms, retained through nested arithmetic and double
negation. Public HTTP controls distinguish gauge `delta` from warned counter
`rate` and retain a positive-scaling counter control. Another 26,000 actual
pinned Go `Mul`/`Div` calls agree on full geometry, field bits/nonfinite classes
and reset hints, including signed zero, infinities and NaN factors. These are
primitive comparisons, not upstream engine tests or full native arithmetic
parity. Upgrade query applications; native/storage/keyed bytes are unchanged.

Histogram trimming `</` and `>/` now replays the complete pinned 124-evaluation
block through HTTP and native Parquet/S3: scalar/vector cutoffs, ordinary
matching/grouping, exponential/custom/zero interpolation, infinite endpoints,
empty histograms and fraction identities. Names/reset hints survive; no-op trims
retain original totals. Invalid matched types omit with info; `bool` and
scalar-only trims reject before storage. Shared work/scan/sample/result bounds,
tenant isolation and per-source notices remain enforced. Another 49,840 actual
pinned Go TrimBuckets calls match finite bits, signed zeros, nonfinite classes,
geometry and hints with Go FMA disabled (`-gcflags=all=-d=fmahash=n`), matching
Pulse's existing unfused arithmetic. This does not establish bit parity with
default arm64 FMA builds, which can differ even in overflow/cancellation classes.
Another 37 unchanged property/dispersion and bucket-retention evaluations cover
empty exponential/custom histograms, sparse signed buckets, NaN/infinite sums,
and bucket-sensitive equality/changes/distinct counts beneath scalar wrappers.
These numerical functions already existed; the new runtime correction charges
variance/deviation and histogram equality traversal to shared query/batch work,
including empty slots, sparse bounds and false/`bool` comparisons. Constant-time
count/sum/average remain exempt from traversal charges.
Another 212 unchanged evaluations cover repeated/accumulating histograms,
resolution changes, signed/zero/custom buckets, bucket-only resets, quantile/
fraction interpolation and inverses, and constant-histogram rates. These
already-supported numerical paths now have permanent HTTP/Parquet/S3 coverage.
Multiplication, nonzero division and unary negation also now reserve bucket work
before traversal; empty slots, multiplication by zero, scalar wrappers, repeated
steps and shared batches cannot evade it. Unary plus and zero division remain
constant-time; scaling does not charge unused custom bounds.
Another 25 unchanged native/mixed binary evaluations cover full timestamp grids,
matching, scaling and operand-type/layout/reconciliation notices. Binary `+`/`-`
now warn when incompatible families omit a pair and retain valid computed values
with a warning for conflicting explicit reset/no-reset hints. Schema rejection
precedes hint diagnostics; ordinary gauge/unknown hints do not create conflicts.
Request/batch notice isolation remains enforced; AST positions and implicit
iterator hints remain open.
The complete classic-histogram file adds 183 unchanged evaluations covering
paired classic/custom-native quantiles and fractions, grouping/rates, duplicate
boundaries, empty distributions, zero crossings and infinite-width buckets.
It exposed incorrect exponential zero-bucket clipping of custom fraction
buckets; custom bounds now remain intact. First negative-infinite buckets and
large/tiny linear interpolation also follow the pinned implementation.
Another 24 unchanged evaluations cover paired NaN sums, cross-schema
subtraction, anchored subqueries, mixed-type range ordering, shared-source
properties/quantiles and custom `irate` resets versus reconciliation.
All 425 generated native inputs match the actual pinned classic converter;
expectations remain the unchanged upstream test DSL.
Five more unchanged range evaluations cover custom-bucket equality/inequality,
unsupported ordering info and mixed-schema aggregation omission. Classic
quantile comparisons now also preserve upstream's subnormal absolute floor,
strict tolerance and capped relative scale, avoiding arithmetic failures on
large finite counts. Six public HTTP controls and 10,030 actual pinned Go
quantile/repair comparisons cover these numerical extremes separately from
the imported engine count.
The complete two-failure `ours/binary_operators.test:1706–1718` block retains
all twelve samples and original failure directives. One-to-one comparison
cardinality checks matching inputs before filtering; zero or one surviving
output cannot hide duplicate counterparts. Checks remain evaluation-step-local,
unmatched many-side inputs stay nonconflicting, and grouped output-label
uniqueness remains separate. Public execution failures use Pulse's existing
HTTP 422 envelope, not an exact upstream error-string claim.
Two unchanged `ours/functions.test` evaluations add the complete three-sample
`label_replace` setup, its valid control and literal invalid-regex diagnostic.
Invalid bounded patterns still reject before storage with HTTP 400/`bad_data`,
now retaining `invalid regular expression in label_replace(): <pattern>`.
Destination-validation precedence and the 1024-byte regex ceiling are unchanged;
the upstream engine oracle does not establish HTTP-status parity.
Seven unchanged `ours/functions.test:956–1010` sorting evaluations retain all
ten series/fifty samples. Range `sort`/`sort_desc` now omit native-histogram
points instead of returning five unexpected histogram series; mixed series
retain float points, and emptied series disappear. Label sorting still keeps
histograms. Existing range warnings, ordering, sample admission and budgets
remain; the exact original five instant controls pass too.
The complete two-evaluation `upstream/subquery.test:142–158` reset block retains
all twelve native-histogram samples and one explicit reset hint. A 15-second
subquery previously repeated that hint, yielding increase 40 instead of the
original 30.769230769230766 on both endpoints/adapters; the three-minute control
already returned 25. Subquery materialization clears only explicit reset/no-reset
hints to unknown, preserving gauges, floats and stored/direct-selector metadata.
This follows pinned Mimir `operators/subquery.go:89–95`, not a test-producer
adjustment. Existing work/sample/materialization limits remain authoritative;
upgrade query applications without rewriting stored data or native formats.
The complete selected corpus now contains 1800 evaluations in 107 files, replayed
through 6544 HTTP requests across both adapters. The original NaN-ranking regex
and complete eleven-sample successful setup from `ours/aggregators.test`
retain HTTP 422/`execution` while reporting `parameter value is NaN for topk`.
Bottom-k/computed-NaN controls preserve sampling/overflow diagnostics and ranking
arithmetic. Two unchanged empty-`le`
histogram evaluations retain all fourteen input samples and original warning/
no-info directives. The test load producer now removes empty-valued labels as
the pinned upstream TSDB does, while expected output labels stay untouched.
This restores native/classic histogram identity and warning behavior without
an evaluator, ingestion or historical-record change. Authored public controls
retain nonempty ASCII/UTF-8 labels and a metric whose other labels are all empty.
Seven unchanged float-delta boundary cases retain all four original series/34
samples. Their `_xN` source
tokens now produce N omitted positions in the test loader, rather than N+1;
numeric/histogram repetitions remain N+1. This corrects the fixture producer,
not the already-correct evaluator. Authored public zero/one repetition controls
check counts and complete sums on both endpoints/adapters without changing
upstream inputs or expected results. Three unchanged timestamp/rate
evaluations retain all twelve original samples and require the possible-non-counter
name info only for produced float results. Separate rate/increase controls cover
suffix/empty-name exclusions, insufficient/mixed/histogram-only windows,
nonfinite float outputs and query/batch isolation. Eight unchanged aggregation-extrema
evaluations preserve `min`/`max` histogram-ignored infos for mixed and
histogram-only groups, alongside float/NaN/grouping no-info controls. Nine unchanged dispersion
evaluations preserve mixed-window `stddev_over_time`/`stdvar_over_time` infos,
histogram-only omission and constant-value regression oracles. Eight unchanged range-extrema
evaluations preserve mixed-window `min_over_time`/`max_over_time` info notices
without inventing notices for histogram-only windows; expected values and
the original split loads are unchanged. Twelve unchanged positive-`k`
ranking evaluations preserve histogram-omission info notices for `topk` and
`bottomk`, including empty/mixed results, grouping and range queries.
Zero-`k` range annotation parity remains open; Pulse retains no notices for
unexecuted filters. Three unchanged `scalar()`
evaluations preserve only-float cardinality: histograms are ignored, so one
float alongside histograms returns that float, while zero or multiple floats
return NaN. The preceding 81 evaluations add
absence, timestamp/rounding, complete absence-over-time/staleness blocks and
label replacement, including original failure assertions. Multi-metric absence
no longer rejects distinct source names as intermediate duplicate identities.
Another 62 commands complete upstream selectors/collisions, Mimir stale-grid
and subquery files, and the remaining Mimir range-function collision assertions.
The selector file repeats seven earlier offset evaluations; these are replay
counts, not unique behaviors or full-suite coverage percentages.
Top-level range-vector range queries now return the exact default Mimir error
before storage. Upgrade query applications;
native/storage/keyed bytes are unchanged. Remaining native annotation/iterator
and deployed-client/provider/capacity gaps are not closed by this batch.

Loki's original negative `quantile_over_time(-0.1, ...)` rejection now replays
with its complete seven-row load and original median/+Inf controls. Leading
signs reject before provider access, including `-0` and explicit plus signs;
signed decimal/hex exponents and ordinary signed scalar expressions retain
their existing meanings. Authenticated GET/form-POST instant/range requests
assert `400`/`parse_error`, not exact upstream diagnostic wording. Parser,
storage and query-budget boundaries otherwise remain unchanged.

The complete Loki `binary_operations.logqltest:888–929` block retains all
57 inputs and ten evaluations through instant/range GET and form POST.
Duplicate indexed-side failures now include the original right-hand-side
diagnostic substring; the eight successful group-right evaluations retain
their original labels, values and timestamps. Authored controls cover left-side
failures, unrelated matching diagnostics and fail-whole authentication/budgets.
PromQL keeps its existing public matching error. This is diagnostic content,
not general upstream wire parity or a change to matching/cardinality policies.

The separate complete `binary_operations.logqltest:750–789` block retains 57
source entries and ten evaluations for missing versus explicit `group_left`
modifiers. Four public GET/form-POST instant/range failures previously exposed
`:many_to_many_matching` instead of the original diagnostic substring
`multiple matches for labels: many-to-one matching must be explicit (group_left/group_right)`.
Loki error rendering now retains that message and HTTP 400/`evaluation_failed`,
without changing the shared matcher, indexed-side diagnostics or grouped-output
uniqueness. All eight successful original evaluations retain their label/value/
timestamp oracles, including bare and empty-parenthesized group modifiers.
This is diagnostic compatibility, not exact upstream HTTP framing parity.

The complete `vector_aggregations.logqltest:898–939` topk block preserves all
378 entries and nine evaluations. Seven successful source evaluations already
matched; fractional and missing parameters correctly rejected before provider
access but both exposed `:invalid_aggregation_parameter`. Static validation
and HTTP rendering now distinguish the original `invalid parameter` and
`parameter required` substrings, retaining HTTP 400/`evaluation_failed`.
The readable invalid-parameter message also applies to the existing shared
invalid-aggregation reason; its internal atom and rejection outcomes are unchanged.
Authenticated GET/form POST exercise the original cases plus range placements,
raw-input checks, auth/no-provider, admission/no-provider and fail-whole scan
controls through native-Parquet/owned-S3. Ranking, integer admission, zero-rank
policy and native/storage/budget contracts are unchanged. These are source
substring oracles, not exact upstream HTTP-envelope or Go-suite parity.

The complete `range_aggregations.logqltest:1558–1619` dispersion block retains
thirteen inputs and twelve evaluations. All ten successful variance/deviation/
offset oracles already matched. Missing `unwrap` now reports the original
`invalid aggregation <operation> without unwrap` substrings, still HTTP 400/
`evaluation_failed`, before storage reads. GET/form POST, raw-input, nested-query,
validation-precedence, auth/admission and fail-whole scan/work controls retain
arithmetic, native/storage formats and budgets. Unknown operations keep their
generic error; supported log observations remain accepted without unwrap.

Loki's complete two-row `Test_SampleExpr_Sort_Fail` at `ast_test.go:219–230`
now rejects named grouping on `sort`/`sort_desc` before provider work, instead
of accepting the original invalid queries. Empty grouping and ordinary
aggregators remain valid. Authored nested/placement, empty/nonempty storage,
asymmetric sorting and authentication controls stay separate from the original
parser oracles. HTTP uses 400/`parse_error` with the original diagnostic
substring; this is not exact upstream HTTP framing/position parity.

The time-modifier batch closes signed offsets, unitless duration literals and
numeric/`start()`/`end()` `@` anchors on selectors and explicit-resolution
subqueries. Another 95 unchanged Mimir evaluations cover fixed data windows,
varying scalar parameters, nested clocks and true source timestamps. Bounds
remain outer-query/source-local and preserve admitted nanoseconds; existing
limits and stricter duration/time syntax are documented in [querying](querying.md).
This does not add negative-source-time S3 storage or upstream step-invariant
operator caching.

The sampling batch closes `limitk` and `limit_ratio`, adding the complete two
Mimir limit fixture files: 130 unchanged evaluations over both storage adapters.
They preserve full labels/names and float/native-histogram samples, support
per-step scalar parameters and ratio complements, and validate/cap parameters
even on empty input. Ratio membership uses the pinned default upstream label
hash; `limitk` uses deterministic hash ordering rather than promising Mimir's
iteration-order subset. Sampling spends existing scan/sample/work/result
budgets and is not indexed acceleration or capacity acceptance.

Duration arithmetic now covers range windows, subquery windows/resolutions and
signed offsets, including nested outer-context `step()`/`range()` and
`min_of`/`max_of`. Unit-bearing scalar arguments also work. The complete unchanged
59-case Mimir duration file adds 178 memory/S3 HTTP requests; separate controls
cover instant queries, nanosecond rounding, nested contexts and fail-whole
validation/budgets. Pulse retains its one-year ceiling and nanosecond rounding,
not upstream millisecond truncation. No native/storage/keyed-byte changes.

The grammar batch closes omitted subquery resolutions (fixed one-minute epoch
grids), hexadecimal/separator query time literals, quoted UTF-8 grouping and
matching/include labels, and UTF-8 `label_replace` destinations. Fourteen more
unchanged Mimir evaluations replay through memory and native S3/Parquet HTTP;
local controls distinguish outer clocks, nested grids, nanosecond boundaries,
grouped operand order and invalid names/literals. The selected corpus now has
815 evaluations in 60 files (2732 memory/S3 HTTP requests). Query budgets,
one-year/int64 time bounds and HTTP parameter grammar remain unchanged.

Shared [OTLP wire support](otlp-wire.md) includes bounded recursive singular-message
merging, repeated-field append and protobuf oneof selection, plus exact quoted
and unquoted schema-scoped decimal/exponent integer forms without float rounding
or fractional underflow. Receiver-scoped JSON rejects duplicate known fields,
including escaped/null-valued duplicates, while ignoring unknown names/objects and
foreign signal roots. JSON objects with multiple populated oneof members still
reject. Trace uint32 counts and fixed32 flags accept exact quoted forms too;
enums still require numeric JSON tokens, not quoted digits. Remaining
null/presence behavior and entity references remain gaps. Named enum strings and snake_case keys are invalid OTLP
spellings, not missing generic ProtoJSON features. Shared wire capability **3**
is required across serving ingress app/native pairs.

See [logs](logs.md), [metrics](metrics.md), [traces](traces.md),
[querying](querying.md), [metric discovery](metric-discovery.md),
[trace expressions](trace-query-expressions.md) and [alerting](alerting.md) for
exact supported syntax, data types, defaults and safety ceilings. A Collector
bridge can supply OTLP/gRPC transport, but does not establish every processor,
queue, retry, temporality or TLS/authentication profile. A Collector conversion
must not be assumed to preserve fields without independent evidence.

## Grafana dashboard and alert corpus

The test suite replays a real production query corpus: 1,178 distinct queries
(1,112 PromQL, 66 LogQL) from Tuist's 31 Grafana dashboards with PromQL/LogQL
panels and all 170 of its alert rules. Each query is interpolated as Grafana
does (`$__rate_interval`, `$__interval`, `$__range`, single, multi-value and
All variables), then evaluated over synthetic data shaped like the queried
metric names, labels and log lines. Every answer equals Prometheus 3.5.0 and
Loki 3.7.9 on the same data. That includes `histogram_quantile`, `label_replace`,
`group_left`/`group_right` joins, subqueries, `offset`, `bool`,
`predict_linear`, `absent_over_time`, `topk`/`sort_desc`, and LogQL
`regexp`/`pattern`/`logfmt`/`json` with `unwrap`, `keep` and label filters.
The corpus compares the result sets, not the order in which series are returned.

One known difference affects log-stream results only. Pulse adds `service`
next to a pushed `service_name` label, and `detected_level` next to a pushed
`level` label, with the same value. Loki returns only the pushed labels when
ingest-time discovery is off. When discovery is on (Loki's and Grafana Cloud's
default), Loki instead adds `service_name="unknown_service"` to streams without
a service and a normalized `detected_level` (for example `warn` for `warning`),
detected from log content per line. Pulse does not implement Loki's ingest-time
discovery. Filters and metric queries on the pushed labels behave identically.

## Completeness and operational meaning

- Unsupported OTLP point forms produce explicit **source-point** rejection counts
  on unkeyed partial-success requests. Inspect these counts: many exporters do
  not replay a rejected subset. A keyed request with any rejected point fails
  whole instead of acknowledging different content under the retry key.
- Unsupported query syntax, incomplete storage reads and exhausted budgets fail
  the whole query. Pulse does not drop predicates or return a successful truncated
  trace to make a compatibility check pass.
- Source metadata and projected Prometheus labels/samples are different views.
  Integer counts above 2^53 remain exact in source metadata, not in float samples.
  Naming projections do not infer producer identity, aliases or original types.
- Source-point, projected-sample, request-node, metadata, result, scan and work
  ceilings are independent. Supporting a feature does not remove its resource
  bounds or imply that every valid-sized wire payload can be stored or queried.
- Every authorized instance can serve the shared object-storage authority.
  There is no node-local durable delta accumulator, sticky-routing requirement
  or external mutable schema registry. New cumulative conversion never repairs
  ambiguous producer ownership or conflicting cross-request metric families.
- Upgrade all applicable app/native pairs before relying on new support. A local
  capability check cannot fence an older pool. No protocol feature pass alone
  establishes provider capacity, admission fairness, crash recovery or cutover
  acceptance.

Public schema fixtures and independent semantic references are kept separately
from optional live client exercises. Ordinary tests replay frozen evidence with
the native project toolchain; they do not download or execute SDKs, Collectors,
Go producers or external reference servers.

Selected Mimir, Loki and Tempo public service-integration scenarios also replay
against native Parquet and isolated local S3 test stores. They cover bounded
ingest/query/discovery behavior, not the complete upstream suites, real provider
durability/capacity or deployed-client acceptance. The
[source selections and remaining coverage gaps](../plans/protocol-breadth.md#upstream-service-integration-ports)
separate exact cases from explicit harness/behavior adaptations. In particular,
Loki's adapted long-range metric check supplies an explicit resolution; it is
not evidence for the upstream no-step expectation near the window's end.

The latest increment adds Mimir's original grouped-vector execution-error
scenario, including its full 50-series input and exact HTTP 422 diagnostic,
and both historical stored-result assertions from Loki's schema-change test.
The latter preserve the -72h/-48h/current inputs and expected lines, not TSDB
schema migration or ingester-only lookback phases. Tempo's ten original rich
trace fixtures now replay complete v1/v2 exact-ID content checks before and
after refreshing manifest supervision. Its original multi-root search
expectations still conflict with Pulse's deliberate fail-whole root-summary
policy; separate local checks document the 409, not passing upstream searches.
Likewise, Loki duplicate-suppression/statistics assertions remain unported
because Pulse deliberately preserves duplicate entries. These incompatibilities
are not hidden by regenerating upstream expected values from Pulse's output.
The follow-up preserves five complete original Mimir request-parameter error
envelopes, with separate GET/form controls for precedence, authorization and
bounded reflection. The inclusive 11,000-point ceiling remains stricter than
upstream's interval check. Loki's two original decolorizer rows now replay
alongside 129 separately labeled source-pattern controls; malformed sequences
no longer discard unmatched text, and supported C1/BEL forms are removed.
These are selected diagnostic/unit-table continuations, not complete service
suites. Upgrade query-serving applications; native artifacts, storage/keyed
bytes and resource ceilings are unchanged.

The Tempo name-discovery continuation adds six original `TestTagEndpoints`
HTTP content-table rows over all seven original two-span batches, with complete
scope/name equality and both omitted and ±2-hour bounds. The actual pinned
public helper supplies 25 static names, exposing five missing ID suggestions
in Pulse's Elixir/native vocabularies. These are autocomplete names only;
ID-value discovery remains unsupported. All 25 reserve capacity inside the
existing global 5,000-pair limit, including before v1 flattening; exact-limit
and overflow controls exercise filtered/unfiltered native/reference paths.
Old v2.9 fixture bytes remain unchanged, with only their static vocabulary
explicitly superseded by the independent newer list. Upstream inspected-byte
metadata and gRPC assertions are not covered by these content selections.
Upgrade query-serving applications and native artifacts together for consistent
vocabulary and budget accounting. Native tuples and storage/keyed bytes are
unchanged; no retry drain or data migration is needed.

Five selected `TestParseIdentifier` rows retain their original mixed
quoted/ordinary keys and exact decoded attribute mappings. HTTP discovery now
normalizes dot-separated portions, such as `span."bar z".foo`, before existing
scope/key validation. Authored native-Parquet/S3 consumers cover v1/v2,
JSON/protobuf, filtered/windowed reads, malformed/unauthorized no-provider
rejection and decoded-byte limits. Fully quoted keys retain Pulse's documented
JSON-compatible escapes; mixed portions use Tempo's quote/backslash profile.
This is not full lexer concatenation, predicate/search/metric grammar or
upstream HTTP-result parity. No native or storage-format change is needed.

Four unchanged Tempo `TestQuerierParseSearchRequest` rows retain the exact
`limit=0`, `-5`, `five` and `4294967298` requests and their parameter-specific
error messages. Public authenticated rejection remains HTTP 400 with no provider
work, alongside native-Parquet/S3 successful-selector controls. Default 100,
cap 1000, existing numeric grammar, ten-byte diagnostic context and window/auth
precedence remain unchanged; over-cap policy failures stay generic. These are
helper diagnostic oracles with authored HTTP consumers, not upstream server
execution or complete error-wire parity. No native/storage change is needed.

Three more unchanged search-request rows preserve parameter-specific `spss`
ParseUint errors for `-2`, `four` and `4294967296`. Four authored public tests
issue 33 search GETs and four OTLP publications: nine successes prove default
3, explicit 1/2/100 and existing plus/leading-zero sampling behavior; all 24
rejection/auth attempts avoid provider work. Shared bounded diagnostic handling
preserves limit behavior and auth/window/limit precedence, with the same
ten-byte context cap. Parsed zero/over-100 and longer values remain generic
policy errors. Original helper errors and authored HTTP/count consumers are
distinct; full numeric grammar, server-error and deployed-client parity remain
open. No native/storage or resource-ceiling change.

Three unchanged paired-window rows also retain exact start/end ParseUint
diagnostics for negative bounds and uint32 overflow. The existing bounded
parser now supplies parameter context before digit/window-policy checks;
partial/mixed-zero/reversed windows, plus-prefixed numeric bounds and longer
inputs still reject generically. Four public tests exercise 32 search GETs
and four OTLP publications: eight successes retain equivalent trace results,
while all 24 rejection/auth attempts leave provider histories unchanged.
Original helper errors are distinct from authored producer/numerical/HTTP
controls. Start-before-end and auth/unknown/window/limit precedence remain;
no accepted grammar, storage/native or resource-ceiling change.

Tempo's original empty-Accept format-selection row now selects JSON for a single
explicitly empty header, as it already did for no header. Authored v1/v2 public
lookup consumers use actual HTTP listeners, native Parquet/owned S3 and body
equivalence with no-Accept/JSON controls. Protobuf success, wildcard/list/quality
and multiple-header policies remain unchanged; unsupported media, multiple empty
headers and empty-plus-protobuf still reject without provider work. This ports
one helper row, not general content negotiation or deployed-client acceptance.
No native/storage-format or resource-ceiling change is needed.

Mimir's `TestFormatQueryAPIEndpoint` now replays its exact expression and
formatted result. Formatting covers Pulse's supported grammar over GET/form
POST, without executing queries or accessing storage. Output preserves operator
precedence, selector order, values and vector matching, with the same 16 KiB
input/output ceiling. It removes comments/redundant parentheses and stays
single-line; exact upstream multiline formatting remains a separate gap.
Upgrade query-serving applications; no native/storage/keyed-byte change is needed.

Additional ports cover all three Mimir UTF-8 name-validation rows over both
remote-write versions, Loki's one-minute request-length rejection, and fifteen
Tempo metric-only interval/aggregate/ranking subtests. Mimir ingestion already
retained UTF-8 names; the query parser now accepts their quoted selector syntax.
Loki checks effective finite bounds before storage and never raises server
budgets. It deliberately rejects malformed, duplicate and unsupported policies,
unlike upstream's permissive header fallback; live tail rejects this finite-window
header. Upgrade all query-serving applications before using quoted names or
relying on policy enforcement. Neither change affects native ABI, storage or
keyed bytes. The Tempo metric cases passed unchanged; they omit exemplar
requests/assertions and gRPC transport, with timed/random input frozen for
offline replay. Separate asymmetric controls check ranking identities and
span-weighted duration averages. These are selected public behaviors, not full
language, policy, exemplar or client acceptance.

Further ports cover Tempo's two empty-selection counts and three HTTP step
validation cases, plus Mimir's exact two-series fingerprint fixture. Ungrouped
trace counts/rates now return zeros for empty selections; grouped and numeric
observations remain empty. Range admission caps the requested interval quotient
at 10,000 before alignment, without increasing other ceilings. The small-step
case also preserves Tempo's actionable diagnostic: a six-minute range with
`35ms` step returns HTTP 400 containing
`step of 35ms is too small, minimum step for given range is 36ms`, before any
provider read. Zero/malformed steps retain their existing rejection behavior.
All four original `TestParseQueryRangeNegativeStep` rows also preserve
`step must be positive` for negative numeric/duration steps; authored controls
prove no provider work with visible Parquet and unchanged instant-step ignoring.
Only the application diagnostic changes; metrics capability 5 remains sufficient.
The complete four instant/range wrappers from `TestParseQueryRequestInvalidBounds`
also retain `could not parse 'start' parameter` / `could not parse 'end' parameter`
on malformed bounds. Visible-Parquet/authentication and discovery controls
preserve no-provider rejection, existing validation order and generic errors
for admitted invalid windows. Full Go parser diagnostics and multi-error
precedence parity are not claimed; accepted timestamps/defaults are unchanged.
The complete `invalid since` row from `Test_determineBounds` retains its original
December 17–18, 2022 bounds, `HI!` value and `could not parse 'since' parameter:`
substring through both metrics endpoints. Query/step/span producers are authored
HTTP adaptations of that helper row. Parsed nonpositive `since` policy failures
remain generic; malformed parsing alone gains context, with no provider work.
Mimir's fixture already
passed and its two series do not collide under Pulse's hash, so it is not proof
of Pulse hash-collision handling. Upgrade all query-serving app/native pairs for
consistent trace metrics; storage, keyed bytes and the native ABI are unchanged.

Tempo's complete `TestTiesInBottomK / all values tied` engine subtest additionally
replays all three original arrays (`x/y/z = [5,5,5]`, `k=2`) through an explicit
nine-span HTTP adapter. Bottom-k now keeps `y,z`; top-k still keeps `x,y`.
Both standalone and arithmetic-leaf native finalizers are exercised through
authenticated OTLP ingestion and cold native-Parquet/S3 reads. This verifies
homogeneous string-label tie direction, not full mixed-type/multi-label ordering.
The three original `TestMetricsSecondStage` filter-before-ranking query strings
also retain their parser acceptance oracle through HTTP. Their numerical OTLP
loads are explicit local adaptations, not upstream numerical expectations.
A single finite scalar filter now executes before native ranking on an unranked
leaf, including arithmetic-leaf finalization. An order-sensitive grouped bottom-k
control distinguishes this from ranking first. All finalized slots spend shared
native work before filtering; repeated ranking, multiple prefilters and ranking
arithmetic results remain unsupported.
Upgrade all serving app/native pairs to trace metrics capability **5**;
trace search/export/discovery tuples, storage/keyed bytes and ceilings are unchanged.

The original `Test_parseTimestamp / RFC3339nano format` scalar oracle also
retains the final nanosecond in `2009-11-10T23:00:00.000000001Z`. A one-span
HTTP metric consumer is an explicit authored adaptation, not an upstream metric
evaluation. Instant/range endpoints now preserve RFC3339 fractional tails;
numeric bounds, timezone controls and adjacent boundary exclusions guard the
fix. This application-only change retains trace metrics capability 5 and
existing numeric-time/window policies, not full RFC3339 grammar parity.

All fifteen rows of Tempo's public `TestDefaultQueryRangeStep` engine table also
replay through authenticated HTTP and native Parquet. Omitted range steps now
follow its window-dependent granularity, including 50 ms minimum steps below
one minute. Explicit steps, instant queries and interval admission are unchanged.
These engine-table ports are distinct from the upstream service-integration
selection; they do not establish metrics-expression, exemplar or client parity.

The continuation includes all seven selected Mimir ingester-query table rows,
native/custom histogram and exemplar distributor cases, all four Loki
categorized-label cases, detected-field windows and grouped stream counts,
basic Tempo unscoped/default-window search, and all 31 selected V2 exact-ID
filter-depth combinations. V2 validates the complete stored trace before
returning an explicit filtered PARTIAL subset; nonmatching unknown/conflicting
copies and resource errors still fail whole. A large filter URI returns 414 at
the default HTTP ceiling instead of upstream's 400; this is documented rejection,
not exact status parity. Filtering uses extra bounded query-task heap/CPU without
changing storage formats or the native tuple.
Independent public Tempo engine fixtures cover span-over-resource precedence;
omitted HTTP bounds search bounded retained context, not an ingester-only tier.
Tempo requires search capability **7**, tuple `{2,1,3,7,12}`. Remote-write
float/histogram timestamp collisions now normalize to the float, and empty-valued
labels are removed before identity/merging. Invalid label names/duplicates still
reject before removal; a nonempty reserved RW2 symbol fails the entire request
with zero written counts and no metadata publication. Drain affected collision
and empty-label keyed retries and replace all receiving application/native pairs
before resuming them; the native tuple does not fence older receivers. These scoped passes
do not close the remaining distributed, provider, language or client gaps.
