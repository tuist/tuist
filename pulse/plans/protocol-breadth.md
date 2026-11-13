# Public-protocol feature breadth

## Goal and acceptance rule

Build a generic observability backend against public protocol contracts. Real
application inventories, including Tuist, are compatibility examples and useful
regressions, not the scope boundary. No feature is accepted merely because its
currently observed queries parse or its sampled client exports successfully.

Keep a versioned contract matrix with supported forms, explicit rejections,
semantic references, bounds and operational qualifications. The operator-facing
current boundary is [protocol coverage](../docs/protocol-coverage.md).

### Bounded metric decoding increment

Metric reader API1 extends the current metric tuple to `{2,2,1,1,1,1}`.
Ordinary S3 selector folds materialize at most 4096 input rows per native call,
sharing the full decoder's pruning, validation and sample semantics. The Kura
regional latency regression exercises a packed 191,551-row object at 160 MiB,
with independently derived regional outputs and an exact shared sample-limit
boundary. Streamed/full codec comparisons preserve histogram, metadata,
exemplar, source-start and non-finite fields. No safety limit, keyed encoder
byte or stored format changes. This is local bounded-allocation evidence,
not deployed-query parity or total native-memory capacity acceptance; see
[operator boundaries](../docs/metrics.md#bounded-metric-decoding).

### Grafana Tempo query-builder increment

The current search/autocomplete profile accepts typed single-spanset filters,
quoted keys, all five owner scopes and the advertised intrinsics, including
retained root/duration context and stored ID dictionaries. Search capability
10 and discovery 13 require matching query-serving app/native artifacts; metric
capability 7 and stored/keyed bytes stay unchanged. The pinned
[fixture ledger](../test/fixtures/traces/tempo_integration/README.md#grafana-builder-autocomplete-engine-probes)
records 53 actual engine/Parquet autocomplete outcomes, separating 46 exact
dictionaries from 7 complete-filter/stored-value extensions. These extend the
selected public integration tables, not replace production/client acceptance.
Full TraceQL, discovery omission parity, structural/select autocomplete,
indexed capacity and provider/failure cutover validation remain separate gates.

Error collection belongs in this same compatibility backlog. Use Sentry/Relay's
actual ingestion integration tests as independent inputs and expected outcomes,
not only SDK smoke tests or Pulse-authored cases. Pin selections and explicitly
record unsupported features and normalization/security adaptations. The first
selection is Relay `a68f1dbec05258cfa27b01059e1c1816d10c7257`,
`tests/integration/test_envelope.py:73–87` (`test_envelope_without_header`):
project 42, DSN envelope authentication, an empty `X-Sentry-Auth` header and
`Hello, World!`. The local controller regression proves durable Parquet/S3
publication and cold reads, alongside six no-provider credential rejections.
Pulse retains `message` rather than Relay's normalized `logentry`; complete
Relay/Sentry integration coverage and normalization remain open.

The next selection at the same revision is the complete two-method
`tests/integration/test_store.py:67–83` (`test_options_response`). Original
GET/POST request-method and `X-Sentry-Auth` requested-header inputs replay through
Pulse's production endpoint; successful OPTIONS, POST-only advertised methods
and header presence retain the original assertions. Pulse's exact 204 status,
wildcard origin, absent allow-credentials and unreflected arbitrary headers are
separate local controls. Gzip admission follows the same shared upstream
[`middlewares/cors.rs:11–28`](https://github.com/getsentry/relay/blob/a68f1dbec05258cfa27b01059e1c1816d10c7257/relay-server/src/middlewares/cors.rs#L11-L28)
installed on both store and envelope routes (`endpoints/mod.rs:94–112`), not an
invented complete port of security-report preflight. The regression first
reproduced `POST, OPTIONS` instead of `POST`, then the missing
`Content-Encoding` admission. Two extra preflight requests and three authorized
identity/gzip POSTs exercise both endpoints with native Parquet/owned loopback
S3, cold reads and three no-provider invalid-key rejections. Broader upstream
CORS headers, additional compression formats, actual browser/Relay execution
and security-report ingestion remain outside this increment.

Compression admission continues with the same revision's complete four-input
`tests/integration/test_basic.py:253–271` (`test_compression`). Its original
`{"message": "hello world"}` bytes, omitted content type and all gzip/deflate/
identity/empty header forms now replay with successful durable publication.
The regression reproduced 415 on the empty header and later on zlib-wrapped
deflate before admitting either. Sentry alone opts into deflate; the existing
incremental inflater and shared expansion budget are reused without changing
other callers' default gzip handling or storage. Two local envelope controls
bring successful publications to six, checked by acknowledgment IDs and original
messages after a cold manifest reload. Twenty no-provider rejection controls
cover unsupported/stacked encodings, malformed/truncated/checksum-invalid streams,
raw DEFLATE, trailing/concatenated streams, bad JSON, invalid keys and unchanged
1 MiB event/4 MiB wire/16 MiB expansion ceilings. An exact 16 MiB expanded
unsupported-item envelope succeeds without publishing; a separate reader test
checks an injected exact expansion boundary and default-off deflate behavior.
These are local bounds/strictness controls, not invented upstream rejections.
No upstream server or Python is required for replay. Brotli, full compression
behavior and client acceptance remain open; legacy store decoding follows below.

Response-policy coverage adds the same revision's complete one-value
`tests/integration/test_basic.py:274–291` (`test_corp_response_header`). Its
empty-body project-42 store POST and query credential first reproduced a missing
`Cross-Origin-Resource-Policy` header. Both SDK ingestion routes now send
`cross-origin` before body validation, preserving the source's sole header
assertion. The empty request's local 400 is not an upstream status oracle.
Eight local preflight/body/authentication controls, three existing successful
Parquet/S3 publication cases and an existing storage-failure case also verify
the header. Unlike Relay's global middleware (`services/server/mod.rs:72–76`),
Pulse scopes this policy to SDK ingestion; disallowed MCP origins still fail
without CORP or wildcard CORS. Browser/COEP execution, upstream server execution
and global response-policy parity are not claimed.

Legacy store coverage selects the same revision's complete
`tests/integration/test_store.py:86–110` (`test_store_node_base64`) and
`fixtures/__init__.py:122–157` (`send_event`), with the original version-5
Raven authentication fields from `get_auth_header` at lines 87–95 and no
`Content-Encoding` on the source request. The original 988 base64 bytes live
in `test/fixtures/sentry/relay-store-node-base64.txt` (one file-final newline is
removed for replay). The literal's SHA-256 is
`e8da888f6fe4422022aa1d3a27cfa7d174f93d75150671ad87ac7c3f44067cbe`;
the upstream test file hash is
`c3c4057b54a7726ea93c9e8ad122838601d11264340377b8be1978ccfdf8511f`.
Independent Elixir source extraction verifies the bytes without Python. The
1847-byte decoded Node event is not rewritten: original event/project IDs,
exception array and `2018-08-27T13:24:00` remain. Replay first failed with
`invalid_event`, then `invalid_timestamp` after body decoding. Offset-free UTC
follows `relay-event-schema/src/protocol/types.rs:951–963`, not host-local time.

Pulse adapts the original normalized-logentry assertion to its retained scrubbed
`message` contract. One upstream input plus five local controls produce six
Parquet/S3 publications and four unique identities after a cold read. Controls
include plain base64, gzip plus legacy decoding, whitespace-preserving ordinary
JSON and exact 1 MiB decoded JSON in both base64 forms. Seventeen no-provider
rejections preserve authentication order, single-stream/one-layer decoding,
decoded-event and wire ceilings, and envelope isolation. Separate timestamp
controls check UTC, asymmetric explicit offsets, fractions, malformed values,
negative dates, future dates and int64 overflow. These local rejection/retention
policies are not upstream error-status or normalization oracles. The existing
bounded inflater is reused with a 1 MiB output budget before legacy expansion;
ordinary HTTP decompression defaults are unchanged. Pixel routes, full legacy
store semantics, timestamp grammar/precision, exception normalization and running old
SDKs or Relay's suite remain open. No storage/keyed-byte format change.

Project-less store coverage follows the same revision's complete
`tests/integration/test_store.py:53–64` (`test_legacy_store`), including both
original requests and both normalized-logentry assertions, adapted to Pulse's
retained scrubbed `message`. `send_event` at `fixtures/__init__.py:122–157`
supplies `{"message":"Hello, World!"}`, the `/api/store/` URL and octet-stream
content type; `get_auth_header` at lines 87–95 supplies the original Raven fields.
The source test-file SHA-256 remains
`c3c4057b54a7726ea93c9e8ad122838601d11264340377b8be1978ccfdf8511f`;
the helper file SHA-256 is
`fed5dd74d4fe8da79fd97526ab4e975fc1c4416e7d87d7db6f2fae0e8a48d128`.
The first production-endpoint replay reproduced 404. Key lookup now resolves
exactly one project from the existing bounded operator configuration, without
a project registry, provider lookup or mutable cluster state. Project-scoped
URLs still limit authentication to their named project. Payload/query project
fields and tenant headers cannot resolve an ambiguous key or redirect writes.

Two source requests plus two local rotation/second-tenant controls yield four
native-Parquet/S3 publications. Cold manifest reloads recover all four identities
with configured ownership, including a second-tenant event despite spoofed
project and tenant fields. Twelve no-provider rejections cover credential
absence/malformation/conflicts/unknown keys, ambiguous mappings, empty
configuration, scoped-key isolation, invalid JSON and existing event/wire caps.
Ambiguity rejection is a local fail-closed adaptation, not an upstream oracle.
Shared decoding, publication and body limits are reused; full legacy,
normalization and client compatibility remain open. No upstream Relay execution,
new dependencies, storage or keyed-byte changes are claimed.

Pixel ingestion selects the same revision's complete
`tests/integration/test_basic.py:116–141` (`test_store_pixel_gif`): two original
JSON/base64-zlib inputs times two `trailing_slash` values. That parameter is
unused in the source function: all four executions target `/api/42/store/`,
and no additional slash behavior is inferred. The source file SHA-256 is
`6c36e7f7453a5df8d689e6155f33d701c8a29c340bc09c7af18e399c500589d2`.
The original decoded query inputs, GET method, project/key binding, successful
HTTP response, exact `image/gif` media type and retained message replay locally.
The normalized `logentry.formatted` assertion remains adapted to scrubbed
`message`. The 1×1 GIF follows `relay-server/src/endpoints/store.rs:135–158`,
file SHA-256 `686b21c01060d11c2bd68eb582ca26a138a189cbfb5005f27dbd64b8a32cd93a`.

Replay first reproduced 404. Both project-scoped and project-less GET routes
reuse authenticated store decoding, native Parquet and conditional publication;
GET envelopes remain unsupported. Four source requests and two local
project-less/exact-1-MiB controls survive cold S3 reads as six distinct events.
Twelve no-provider rejections check missing/malformed data, missing/invalid/
ambiguous credentials, route isolation, exact/over query boundaries, expansion
overflow and HEAD probes. The existing Plug 1,000,000-byte query limit and
1 MiB decoded-event limit remain authoritative; transport request-line limits
can bind sooner. An existing publication-failure regression now also requires
503/Retry-After instead of a successful GIF on GET. `Cache-Control: no-store`
and early HEAD rejection are local safety policies, not upstream test assertions;
HEAD is rejected before Plug.Head could turn a probe into an ingesting GET.
Operator guidance prefers POST because raw query payloads can enter proxy logs
before scrubbing. No browser/SDK/Relay execution, new dependency, storage-format
or keyed-byte change is claimed.

The next Sentry increment selects all six rows of Relay
`tests/integration/test_basic.py:170–202`, `test_store_allowed_origins_passes`,
at `a68f1dbec05258cfa27b01059e1c1816d10c7257` (file hash above). Origin
`http://valid.com`, project 42 and `{"message":"hi"}` remain unchanged.
Capture/noncapture expectations follow the source; `403` is Pulse's local
fail-closed status and retained `message` is not normalized `logentry`.
`relay-filter/src/origin.rs` SHA-256 is
`ae450e26d77c9fdead859fbf5223b2365ab56230496062a5fc7c22c43a97cc82`;
`relay-server/src/services/projects/project/info.rs` SHA-256 is
`0fa56b15479d509755dad7e07d14f9a851a97a4e346dd7bb215b68b52f96601f`.
The latter's `is_valid_origin` explicitly accepts absent Origin independently
of the allowed list. Optional `allowed_domains` is checked only after unique
credential resolution; omission preserves existing unrestricted behavior.
Thirty-two patterns/256 bytes each and a single 2048-byte HTTP(S) Origin are
local ceilings. Scheme/domain/explicit-port matching and label-boundary suffixes
follow the source profile, but malformed/opaque origins reject and default
ports are not inferred. This is not complete Relay URL normalization parity.
The red HTTP replay published an event for the first denied row. Green replay
recovers four source events plus five local controls after cold native-Parquet/S3
reads, while denied store/envelope/pixel and ambiguous-key requests perform no
provider operations. Configuration boundary checks preserve no-Origin SDK
admission and credential authority. No upstream Relay execution is claimed.

The zstd continuation selects Relay's empty-body zstd row from
`tests/integration/test_store.py:1043–1067` and the zstd receiving hop from
`test_store_content_encodings_chained:1071–1082`, at the same pinned revision.
The source file SHA-256 is
`c3c4057b54a7726ea93c9e8ad122838601d11264340377b8be1978ccfdf8511f`.
`fixtures/__init__.py:122–153` supplies the original default
`{"message":"Hello, World!"}` store payload. The replay adapts forwarding
into a single receiving hop, with separate envelope and resource-policy controls;
it retains `message`, not Relay's normalized `logentry`. Baseline returned `415`
for a valid compressed event. Accepted store/envelope events now survive native
Parquet/S3 publication and a cold MCP read, and the original empty-body row
returns `400`. No Relay chain, Python or external codec dependency is required.

OTP's bounded streaming decoder enforces a 16 MiB window and the existing
expanded-body budget. A framing-only pass proves complete standard frame/block/
checksum byte geometry before decoding, because the OTP stream interface does
not expose end-of-frame status. Only complete headers reach its header API.
Preset dictionaries, skippable/concatenated/trailing frames, truncation and corrupt
checksums reject without provider operations. Exact 1 MiB event/16 MiB body
boundaries remain inclusive; both known and omitted content-size bombs reject.
The single-frame/window restrictions are local safety policies, not additional
upstream assertions. Other HTTP receivers remain gzip-only; Brotli, stacked
encodings, full Relay normalization and deployed SDK acceptance remain open.
No native/storage/keyed-byte format change.

Relay's complete `test_level` scalar decoder table (`types.rs:1153–1169`)
adds three unchanged oracles: `log` → Info, integer 30 → Warning, and
`critical` → Fatal. Store/envelope events explicitly adapt those scalar rows,
with separate integer-code/custom-text/float/nil controls. Twenty-two durable
publications survive cold native-Parquet/S3 MCP reads, proving canonical
severity text/numbers and exact original event-level types/values. This is not
an original Relay ingestion test or full normalization parity. The source file
SHA-256 is `488cfe5cca0b4a48699a019c92cd23efb78c6766697788016408c7e199743578`.
Only new events change projection; upgrade Sentry-serving applications without
rewriting retained events. No storage/native/keyed-byte change.

The same pinned `types.rs:1038–1063` timestamp test contributes five nonnegative
float conversion oracles, preserving 2.99999951 → 3 seconds and
2.99999945 → 2.999999 seconds. The public red replay retained 2.999999510 instead.
Floating seconds now round their fractional part to microseconds and assemble
integer nanoseconds, avoiding whole-epoch float multiplication. Twelve durable
store/envelope events cover those five rows and a modern-epoch control; cold
MCP reads preserve raw float values and exact projected timestamps. The four
negative source inputs deliberately reject under existing Pulse timestamp
policy, with eight no-provider-access controls. This explicitly adapts scalar
tests, not original Relay ingestion cases, and does not claim negative-time or
full normalization parity. Integer/ISO timestamps, retention and future-time
limits are unchanged. Upgrade Sentry-serving apps for new writes only.

Relay's complete `test_values_deserialization` (`types.rs:1078–1119`, same
revision and source-file hash) contributes three original JSON inputs and their
equivalent decoded exception: `Test`, `aha!`. Store/envelope consumers adapt
those rows explicitly; title and Pulse issue identity expectations are authored,
not original Sentry grouping tests. Ten Parquet/S3 publications include separate
two-exception/last-frame controls, then cold MCP reads check original container
shapes and two distinct issue groups. The red replay returned six fallback
`Error` events instead of recognizing the direct array/single-object forms.
Both now share wrapped-event selection for titles and new issue IDs. Retained
IDs are not rewritten or merged; read-time titles can improve without changing
old grouping. Upgrade all Sentry-serving apps; no native/storage/keyed-byte
change or full container-normalization/Relay-suite acceptance is claimed.

The same Relay revision's complete `logentry.rs:178–191`
`test_logentry_from_message` contributes JSON `"hi"` → `{"formatted":"hi"}`.
Its source file SHA-256 is
`87bb01129e24a19acc46f21007194fe23527a347563ffe1907a99cc188dcec46`.
The public red replay returned `Error` for the string form and used a conflicting
top-level message instead of another string logentry. The projection now selects
nonempty string logentries before that fallback, retaining exception precedence.
Eight store/envelope publications and cold native-Parquet/S3 MCP reads preserve
raw input, matching canonical-object grouping and distinct-message controls.
These are explicitly authored HTTP/grouping consumers of the original decoder
oracle, not original Sentry issue identities. Existing persisted IDs stay put;
upgrade Sentry-serving apps for consistent new IDs. Parameter interpolation,
full normalization and deployed-client acceptance remain open. No native,
storage/keyed-byte or resource-limit changes.

Relay's same pinned revision contributes seven complete successful fingerprint
decoder cases in `fingerprint.rs:125–162,198–215`. Source-file SHA-256:
`ef7c72a7f74873cc7dd58c5b37bdf4959947b8cc4e9e9a09e8c0c32bc7690c0d`.
Public baseline rejected `[true,false]` with HTTP 400 `invalid_fingerprint`.
Grouping now converts accepted booleans, signed/unsigned integers and in-precision
floats to Relay's strings, ignores nulls and preserves raw event values. Floats
truncate toward zero with `-0` retained; absolute values at or above 2⁵³ reject.
Forty store/envelope publications include all seven source inputs and authored
canonical-string/negative-zero/integer-width/float-bound controls. Cold native
Parquet/S3 MCP reads prove equivalent and distinct identities, not original
Sentry grouping. Twenty-two invalid/over-limit requests cause no provider work.
The two original large-float decoder cases deliberately retain whole-event
rejection instead of Relay's soft metadata stripping. Supplied 32-component and
256-byte string ceilings, existing string identities, default expansion and
scrubbing stay intact. This application-only change needs consistent ingress
upgrades but no native/storage/keyed-byte migration or retry drain. Full
normalization/error metadata and deployed-client acceptance remain open.

The complete Relay `event.rs:1037–1049` `test_lenient_release` input
`{"release":42}` and oracle `{"release":"42"}` expose another projection gap:
only canonical-string events matched release `42` in cold public MCP queries.
The existing LenientString conversion now serves release projection as well as
fingerprints, with fingerprint-specific limits still applied separately.
Twenty-eight store/envelope publications preserve original values while proving
exact query/issue counts for numeric/string, boolean, truncated-float and
signed-zero releases, integer endpoints, long strings and empty fallbacks.
Source-file SHA-256:
`e35094c8e696792aa908643a25784f2eb4aabf37918edfeef24d812d9396ec2d`.
HTTP/MCP consumers and extra controls are authored decoder adaptations, not
Relay ingestion/grouping oracles. Source baseline finds two rather than four
events; the fixed replay and all 41 errors/controller tests pass. No old-data
repair, raw-value rewrite, identity change, storage migration or native bump.
An exploratory uint64-overflow control instead returned503 before projection
changes; its admission/error classification is a separately offered follow-up,
not claimed fixed or included as a successful source oracle here.

The complete Relay `exception.rs:145–156` object-value oracle exposes another
message-projection gap: a retained `{"unauthorized":true}` value produced
`Error` instead of JSON text in Pulse issue titles. The existing canonical JSON
encoder now supplies non-string exception messages after scrubbing, preserving
original scrubbed body values and the existing title/grouping bounds. Thirty-two
store/envelope publications with string counterparts prove exact cold S3/MCP
titles, counts and equivalent Pulse groups. Five further publications cover
scrubbing, null/empty handling, type prefixes, custom fingerprints and Unicode
truncation; unauthorized writes do no provider work. The original source-file
SHA-256 is `7670f47cbb0ea241612cf07c0f256d742726889dbfbd27b72ed3dca02b88ece5`;
the supporting `JsonLenientString` implementation file hashes to
`488cfe5cca0b4a48699a019c92cd23efb78c6766697788016408c7e199743578`.
This is an explicit decoder-to-HTTP adaptation, not a Relay grouping oracle or
complete numeric-format parity claim. New default IDs can change, while old
stored IDs/materialized summaries are not rewritten. All 63 Sentry errors,
controller and projection tests pass. No native/storage/keyed-byte change.

The same Relay revision's three complete message-only normalization cases,
`relay-event-normalization/src/logentry.rs:156–190`, retain `hello, %s!` without
parameters and `hello, world!` with message-only/equal-formatted inputs.
`event.rs:218` routes legacy top-level message values through the logentry
decoder. Twelve authored store/envelope consumers preserve those inputs while
checking canonical and legacy titles/groups through cold native-Parquet/S3 MCP
reads. Before the fix, four legacy events produced `Error`; they now share the
canonical groups. Eight further publications test formatted/null/empty behavior,
explicit logentry/exception precedence, scrubbed credentials, invalid message
types and Unicode truncation. Two unauthorized requests cause no provider work.
Source normalization SHA-256:
`bbb58bb570c79364fd7ea808f75c971b125cce327433ce6b06330981c091450f`.
These are explicitly adapted normalization consumers, not original Relay
ingestion/grouping cases or full parameter interpolation. All 65 errors,
projection and Sentry-controller tests pass. Upgrade query/ingress applications
consistently: new default IDs can change, while retained IDs and materialized
summaries are not migrated. No native/storage/keyed-byte or resource-limit change.

Relay's exact legacy message/exception aliases (`event.rs:218,364`) now feed
the existing title and default-grouping logic without rewriting event bodies.
Complete `protocol/logentry.rs:178–191`, normalization `logentry.rs:156–190`
and `protocol/exception.rs:89–117` inputs yield twenty authored store/envelope
publications over canonical and legacy names. Cold native-Parquet/S3 MCP reads
and direct storage reads preserve the source values and canonical title/group
equivalence. Before the fix ten legacy events produced `Error`; both new
source-backed tests fail on the prior application. One additional authored test
publishes twenty-eight events covering canonical presence, exact-name/case
boundaries, exception chains, post-scrub rendering, custom fingerprints and
Unicode title caps; two unauthorized attempts leave provider history unchanged.
Canonical fields take priority even when null/invalid, matching the alias
selection in `relay-protocol-derive/src/lib.rs:407–420`. Source SHA-256 values:
`protocol/logentry.rs` = `87bb01129e24a19acc46f21007194fe23527a347563ffe1907a99cc188dcec46`,
`protocol/exception.rs` = `7670f47cbb0ea241612cf07c0f256d742726889dbfbd27b72ed3dca02b88ece5`,
alias derive = `90307a791b2113cbedc3e9fcf8ce23b00429802241fbf556cb07e4110f2d8c65`.
Event/normalization hashes remain as recorded above. These are explicit decoder/
alias-to-HTTP adaptations, not original Relay grouping oracles or general
normalization/interpolation. Upgrade all query/ingress apps consistently; old
issue IDs/materialized evidence are not rewritten or merged. No native/storage/
keyed-byte or resource-ceiling change.

Relay's same pin declares `sentry.interfaces.User` and `sentry.interfaces.Http`
as canonical user/request aliases (`event.rs:345–351`). Complete roundtrip input
values from `user.rs:143–186` and `request.rs:634–723` are transcribed without
semantic changes, with adapted JSON whitespace. Public store/envelope ingestion
and cold native-Parquet/S3 MCP reads showed the canonical fields filtered but
legacy payloads retained. Both regression tests fail against the old application.
The existing recursive scrubber now includes those exact case-insensitive names,
with no general prefix matching or additional protocol normalization.
Eight source-derived publications and two authored control publications cover
raw persistence, nested map/list traversal, null/scalar/container values, alias
coexistence, similar-name nonaliases, title rendering after scrubbing and stable
custom fingerprints. Two unauthorized requests add no provider work. Input shapes
and aliases are upstream facts; privacy filtering is Pulse's own conservative
policy, not a Relay privacy test or complete PII guarantee. Source SHA-256 values:
`user.rs` = `652e2a7fdd775974f14e2c2fad2b02f31e3556ff587303bfa5888de0af1bd931`,
`request.rs` = `a2ea2a7609ba7a480ee824a85478a206279962dcef7c16e69def511a62dce1f9`,
`event.rs` = `e35094c8e696792aa908643a25784f2eb4aabf37918edfeef24d812d9396ec2d`.
Upgrade every ingress application for new-write protection. Retained objects,
backups, materialized evidence and stored identities are not automatically
redacted or migrated; prior legacy traffic may have left sensitive copies.
No native/storage/keyed-byte/resource-ceiling change or destructive cleanup.

Relay's complete active `test_trace_id_formatting` table at the same pin,
`protocol/contexts/trace.rs:562–615`, confirms canonical dashed UUID and undashed
hexadecimal trace-ID spellings. A disposable four-row store/envelope replay
showed four dashed-ID publications losing their projected correlation IDs,
despite retaining their raw contexts. Reusing Pulse's existing strict UUID
normalizer fixes only that projection; the 16-digit span-ID grammar is unchanged.
Cold native-Parquet/S3 MCP and direct storage reads verify the result. Permanent
tests use independently authored asymmetric IDs, not copied FSL-licensed Rust
test code: eight normalization publications and sixteen further boundary
publications, plus two unauthorized attempts with no provider work. Incorrect
hyphen placement, invalid hex, nonstring IDs, raw contexts and unchanged issue
groups remain covered. Whole source SHA-256:
`3122dce0d438e3335174b1bdd69c08b4dd8bdecb205a7e7db84599603be0ed69`.
The original four-row red/green replay and the independent kept regression tests
are distinct evidence, not an imported upstream fixture. Upgrade ingress apps;
old absent projections are not backfilled. No full TraceId grammar, nil-ID repair,
upstream execution, native/storage-format or resource-ceiling claim follows.

The same Relay pin declares nested exception `sentry.interfaces.Stacktrace`
as an alias for `stacktrace` (`protocol/exception.rs:50–54`), with canonical
presence precedence in `relay-protocol-derive/src/lib.rs:407–420`. Eight independently
authored store/envelope publications reproduce a Pulse grouping mismatch:
canonical and legacy copies split, while distinct legacy frame locations collapse
into one fallback group. A single existing frame lookup now applies the declared
alias. Cold native-Parquet/S3 MCP and direct storage reads retain raw exception
shapes and the expected two frame-specific groups. Twenty-four further publications
cover canonical null/malformed/empty presence, conflicting frames, exact names and
custom fingerprints; two unauthorized attempts preserve provider history. Red
passes one boundary test and fails the grouping regression; both pass after
normal compilation, seed2041. These are independently authored consumers of an
upstream field contract, not copied Rust tests or original Sentry issue identities.
Exception/derive hashes remain `7670f47cbb0ea241612cf07c0f256d742726889dbfbd27b72ed3dca02b88ece5`
and `90307a791b2113cbedc3e9fcf8ce23b00429802241fbf556cb07e4110f2d8c65`.
Upgrade ingress apps: new legacy-stacktrace issue IDs can differ, while stored
IDs/materialized summaries remain unchanged. Top-level stacktrace grouping,
symbolication, general alias normalization and upstream execution remain open;
no native/storage-format or resource-ceiling change.

The fifteenth pass verifies Relay's non-object logentry conversion at the same
pin (`protocol/logentry.rs:119–134`, `protocol/types.rs:793–802`). Authenticated
store/envelope requests reproduced `true` becoming the fallback `Error`; title
projection now JSON-renders numbers, true and arrays, retaining false/null
absence, object string fields and exception precedence. Sixty independently
authored publications include string counterparts, all three message names,
cold native-Parquet/S3 reads and equivalent Pulse groups; seven boundary
publications cover privacy, bounds, canonical presence and literal fingerprints.
Two unauthorized attempts leave provider history unchanged. No upstream tests
were copied or counted. New-write default IDs may change; old IDs/materialized
summaries are not migrated, and full Relay float-format parity remains open.

The same pass found no mismatch in Mimir's complete deriv/predict-linear table
and initial eight range-query blocks (26 original evaluations, 88 public requests
across both adapters), Loki's complete detected-byte-values case (both original
oracles on GET/form POST), or Tempo's two instant nanosecond-bound count/average
cases (4 and 4.5). These use unchanged original inputs/oracles with documented
HTTP/storage adaptations and owned loopback S3, not upstream server execution.
No matching case was imported or used to justify a runtime edit. Mimir corpus
remains 1796 evaluations/105 files/6530 fixture requests/210 wrappers.

The sixteenth pass reproduces Relay's store envelope-media dispatch contract
(`endpoints/store.rs:106–121`, `extractors/content_type.rs:24–37`, same pin).
The exact raw POST media type selects the existing bounded envelope decoder,
but store request credentials remain mandatory before dispatch. Authenticated
public red returns 400 where the same `/envelope/` request returns 200; after the
correction, both project-scoped and uniquely resolved project-less store URLs
publish identity/gzip envelopes, retain header-selected event IDs and report
binary attachment discards. Four store publications plus four baseline controls
survive cold native-Parquet/owned-S3 reads. Seventeen no-publication controls
cover auth/DSN disagreement, ambiguity, exact media-type grammar, GET isolation,
framing/size errors and empty/unsupported-only envelopes. An existing storage
failure test now covers store envelopes returning retryable 503. Both focused
tests pass, seed 94003; all 78 Sentry/error/body tests pass, seed 94004. One initial
boundary assertion incorrectly assumed an absent S3 manifest reads as an empty
query; the corrected test verifies unchanged provider history and no objects.
These are independently authored consumers of source declarations, not copied
Relay tests or upstream execution. Store raw JSON with the envelope media type
now means a header-only envelope, not an event; upgrade ingress apps together.
No new item support, native/storage format or resource-ceiling change.
Source hashes: store `686b21c01060d11c2bd68eb582ca26a138a189cbfb5005f27dbd64b8a32cd93a`,
raw content type `807b37d3e4538b6f519d2ccd7493920ef1a10ea3af4a14b6d708de469ddd0172`,
envelope `124fc055fc6b0c7fa0d04669fcb056f5312c21fcae54ab3d9c64ea5b57d92ce1`.

The seventeenth pass reproduces Relay's complete environment-tag promotion
cases (`normalize/mod.rs:797–842`, same pin), adapted into store/envelope
requests and cold native-Parquet/owned-S3 queries. A public environment filter
returned zero instead of six matching events. Projection now uses the first
legacy environment tag when the top-level field is missing/empty/non-string,
without rewriting the scrubbed event or tags. Twenty-four publications retain
the two original promotion inputs and empty control, plus authored precedence,
object/list/duplicate, scalar, whitespace and malformed-value controls. The
source owner is `event.rs:635–646`; tag scalar decoding is in `protocol/tags.rs`
and first-removal ownership in `protocol/types.rs:219–227`. This is not full
Relay tag/environment validation or normalized-event JSON parity; original
source tests and Relay itself were not executed/copied. Existing projections
are not repaired; upgrade ingress apps together. Native/storage formats,
resource ceilings and issue identities are unchanged.
Source SHA-256: normalize module
`f155363755a5e5ff01b3450d93c5e77340ea70e2ccbf881e238fe7714907147b`,
event normalization
`5c40db31a1387925814b4954124d8bfe0135fd3a587b381ea057c4496e08fa42`,
tag schema `084614016a699e3fffe30972aa2d91774d24b16f04d5c234b162cb8c4e8a5eca`.

The seventeenth pass also replays complete previously unreplayed selections
without finding further mismatches: Mimir `ours/functions.test:658–767`
(`idelta`/`irate`/`delta`, three range oracles over 114 samples on both adapters,
plus all nine timestamps through instant queries), Loki
`range_aggregations.logqltest:1657–1671` (constant non-exact float variance and
deviation, exact zero through GET/form POST), and Tempo
`TestQuantileOverTime` (`engine_metrics_test.go:886–993`, all ten observations,
six typed series/eighteen samples). Auth, admission/work or scan controls and
actual native-Parquet/owned-S3 reads accompany these bounded replays. No
matching case was imported or used to justify a runtime correction. None of
the upstream systems was executed; the Mimir corpus remains
1798 evaluations/106 files/6538 fixture HTTP requests/212 wrappers.

The eighteenth pass reproduces the same Relay pin's alternate Sentry auth
header contract (`extractors/request_meta.rs:663–687`). An Authorization-only
store request first returns 403. Both header locations now share the existing
Sentry key parser with ASCII case-insensitive scheme spelling; all supplied
credential forms must still agree. Fifteen store/envelope/pixel consumers
cover Authorization and mixed-case schemes across scoped/project-less paths;
one more verifies matching Authorization/X-Sentry-Auth/query/DSN credentials.
Cold native-Parquet/owned-S3 reads retain all sixteen identities, raw payloads
and operator-owned project/service despite spoofed tenancy. Nine no-provider
controls cover malformed, invalid, duplicate and conflicting keys and ingest/
read credential separation. CORS preflight permits Authorization while keeping
POST-only, credential-free browser policy. These are independent consumers of
source code, not copied Relay tests. Pulse's matching-key agreement policy is
deliberately distinct from upstream multiple-method rejection. Basic auth and
full auth-parser parity remain open. Upgrade ingress apps consistently; no
native/storage/resource-ceiling change. Source SHA-256:
`0e91152fc6ad6b23eab1e1ec1574a81d0f5cfb083c91c56df4ee0e146229cb49`.

The same pass finds no mismatch in Mimir's remaining active
`ours/histograms.test:1–149,187–199` (fourteen original evaluations, nine loads,
132 complete samples on both adapters, including histogram quantile notices,
mixed-type lifetimes and changing buckets) or Tempo's complete
`TestAvgOverTimeCombine` (`engine_metrics_test.go:2410–2445`, six observations
in three source sets). The weighted average is exactly 416.6666666666667, with
NaN intervals omitted on public serialization. Auth/no-provider and work or
admission controls pass with actual owned native-Parquet/S3 reads. These
matching cases are not imported and justify no runtime correction; upstream
systems were not executed and Mimir corpus accounting is unchanged.

The eighteenth Loki continuation preserves the complete pinned
`vector_aggregations.logqltest:898–939` block: 378 entries and nine evaluations.
Seven successful evaluations already match through GET/form POST, while both
original invalid queries reject before storage but collapse their required
`invalid parameter` versus `parameter required` diagnostics into one atom.
The correction retains the distinction during static validation and renders
the source substrings at HTTP 400/`evaluation_failed`. It changes no ranking,
integer normalization, zero-rank, grouped-output or resource policy. Public
controls retain the complete raw input, range placements, authentication and
admission no-provider behavior and fail-whole scans. This is message-content
compatibility, not upstream HTTP framing or Go-suite execution. Source block
SHA-256: `ccefc4098de08103c8bd55f3938912de4233e862a22e09f44fc179be0563e14d`.

The sixteenth pass also closes native-histogram subquery reset-hint propagation using the
complete pinned Mimir `upstream/subquery.test:142–158` block and original headers.
Its twelve samples contain one explicit reset. At 10m, `increase` over `[10m:15s]`
returned 40 instead of the unchanged 30.769230769230766 oracle through both public
endpoints/adapters; `[10m:3m]` already returned 25. Subquery point materialization
now clears only explicit reset/no-reset hints to unknown, as Mimir's
`operators/subquery.go:89–95` requires. Gauges, unknown hints, floats and stored/
direct-selector metadata remain unchanged. Six focused regressions fail red and
pass source-loaded green; 14 focused/affected HTTP tests and 50 evaluator/semantics/
batch regressions pass separately. Authored controls cover both hints, gauge
warnings, direct-source behavior, auth/no-provider, query-local batch ordering
and shared work/materialization limits. The exact fixture hash is
`02da6b9211a5c387c22da1304d7ffaa57e6d1db927b542901ee5c8bb83bbcf9c`.
Corpus delta is two evaluations/one file/eight HTTP requests/two wrappers:
1798/106/6538/212 total. No producer, native/storage-format or quota change;
upgrade query applications. Upstream Mimir itself was not executed.

Loki's complete pinned `binary_operations.logqltest:750–789` block proves a
separate error-rendering mismatch: matching correctly rejected missing group
modifiers but exposed `:many_to_many_matching`, not the original actionable
`group_left/group_right` diagnostic. A controller-only rendering clause keeps
HTTP 400/`evaluation_failed` and all matching policies unchanged. The complete
ten-evaluation block retains 57 source entries, asymmetric non-bool counts and
five-point matrices; the original eight successes and exact raw loads pass
before the diagnostic assertion. Source-loaded targeted green passes four tests
covering 90 queries/four pushes, including the unchanged group-right block,
auth/no-provider, admission/no-provider, fail-whole scan/work and distinct
indexed-side/grouped-output failures. Exact frozen block SHA-256 is
`d9e81a45f4e23edae4b474092b3d6dcc630c2bc99053221019b3b3b5f3f15714`.
No shared matcher, native/storage/budget change or upstream Go execution.

Tempo's complete `TestMinOverTimeForSpanAttribute` (`engine_metrics_test.go:2221–2291`)
matches the original 21 observations across two distinct native Parquet sources.
Original typed-label samples remain bar=(1000ms,100),(2000ms,200), and
baz=(1000ms,204),(3000ms,200), omitting absent intervals rather than zero-filling.
Authenticated OTLP/HTTP and cold owned-S3 reads cover both sources; a complete
count control returns [7,8,6]. Four auth/invalid-step/unsupported-parent/reversed-
bound rejections leave provider history unchanged. This public adaptation is
matching evidence, not justification for an edit/import or execution of Tempo's
internal multi-layer evaluator. No external-provider/deployed-client claim follows.

Final persisted validation passes all four complete compatibility HTTP files:
897 tests, seed 94005. Shared error/PromQL/LogQL/trace-metric/query-controller
regressions add 420 tests, seed 94006: 1317 selected tests total, without adding
overlapping focused runs. Warnings-as-errors compilation, strict Credo across
464 files, scoped formatting and whitespace checks pass. Logs use
`.amp/in/artifacts/four-surfaces-sixteenth-{compile-final,http-final,shared-final,credo-final}.log`.
All work remains local and uncommitted; this is not the complete repository suite.

The nineteenth pass follows the full-suite-verified main push of the accumulated
eighteen batches. It closes three independently reproduced public gaps:

- Sentry EventId uses Relay's locked uuid 1.28.0 parser contract: all seventeen
  literal `test_parse_valid` calls, including repeats, replay through store and
  envelope. Braced/URN forms formerly rejected with `invalid_event_id`; they now
  normalize to lowercase hex, with all 34 raw records and five unique cold MCP
  identities retained. Authored malformed/nested-wrapper and auth controls make
  no provider requests, and envelope-header precedence stays intact. The crate
  archive SHA-256 matches Relay's lock:
  `7cc1186384beb7dd8eedea376413fd654937285ea6c9cfbb928dc3043ea4b606`.
  Correlation-field grammar, existing IDs, stored bytes and budgets do not change.
- Mimir's original `ours/aggregators.test:411–420,605–609` keeps all eleven samples,
  successful ranking and the original NaN regex. Only topk/bottomk NaN errors gain
  operation-specific diagnostics; HTTP 422/execution, sampling, overflow and rank
  policies remain. The fixture adds two evaluations, one file, six fixture HTTP
  requests and two wrappers: current corpus 1800/107/6544/214. Four separate
  asymmetric authored wrappers add 28 requests, not upstream evaluations.
- Loki's complete `range_aggregations.logqltest:1558–1619` retains thirteen inputs
  and twelve evaluations. All ten numeric/offset oracles already matched; only
  two missing-unwrap diagnostics failed. Validation reuses supported unwrap
  operations to retain their names, preserving HTTP 400/evaluation_failed and
  parameter/grouping precedence. Native/arithmetic/storage/budgets stay unchanged.

Tempo's complete grouped attribute-average case at
`engine_metrics_test.go:2552–2629` matched unchanged: all sixteen zero-duration
spans across two retained sources yield bar `[260,200,100]` and baz only final
`300`. It warrants neither a correction nor a fixture import. These are Pulse
public-interface replays against source contracts, not execution of upstream
servers or deployed-provider/client acceptance. The nineteenth pass remains
local and uncommitted; its delivery is separate from the preceding main push.

## Full-surface acceptance gate

The requested target is now every public surface and error contract before a
customer deployment, not just additional selected green fixtures. **This gate
is not met.** The current source inventory below is a discovery baseline, not
an assertion-level completeness report or permission to deploy to Twilio.
Local passes, an application inventory and a passing happy-path client are
necessary evidence for their profiles, never substitutes for this gate.

Keep each upstream assertion classified as exact replay, explicitly adapted,
intentional incompatibility, unported, or implementation-specific/not applicable.
Adapted/incompatibility controls must not count as exact upstream passes. Record
source revision/ranges, independent inputs/oracles, HTTP method/path, content
negotiation, tenant/auth setup, status, complete error body and relevant headers.
Keep dynamic table rows and generated combinations separate from top-level
test-function counts. Completing the assertion inventory itself remains work;
do not infer a coverage percentage from today's replay totals.

### Pinned source inventory

| Backend | Revision and enumeration | What the count does not establish |
| --- | --- | --- |
| Mimir | `dd039cdd4ba466adb5d28280bf1b8a374a98432e`: 114 top-level `Test` functions in `integration/*_test.go`; 47 comparison-runner `.test` files across `upstream`, `ours`, `ours-only`, containing 3,795 evaluation directive lines | Table/helper/deployment executions are not counted individually. Local selected extractions overlap, so subtracting local evaluations from 3,795 is not a missing-case count. Disabled source fixtures are not working upstream contracts. |
| Loki | `5aa4b9212d64d723f63b2770452054aa23df114d`: 22 top-level `Test` functions across 15 `integration/**/*_test.go` files | Includes infrastructure/helper tests and dynamically generated cases. HTTP/parser/pipeline/template/error tables outside `integration` must also be inventoried. Older v3.5 volume fixtures retain their separate provenance. |
| Tempo | `1a7373ee774b2ee5a40957c2310179b0ef7ff843`: 34 top-level `Test` functions across 16 `integration/api/**/*_test.go` files | Does not include every storage/limits/operations integration test or TraceQL/API unit table. HTTP content selections do not establish gRPC, inspected-byte telemetry, provider or deployment parity. |

Reproduce entry-point counts with `rg '^func Test'` in those pinned directories;
enumerate fixture files with `rg --files` and count directives matching
`^eval(_ordered|_fail)?\s`. Current local corpus totals count replay commands,
not unique queries or complete upstream assertions. Never copy AGPL runtime
implementations to fill a gap: retain test attribution and independently
implement behavior within Pulse's architecture and resource bounds.

### Surface and error backlog

The [Grafana datasource contract ledger](../test/fixtures/grafana/README.md#datasource-http-request-contracts)
adds current-client discovery limits/escaped names, optional query statistics
selectors, Prometheus result-limit tables and Loki health/log-volume requests.
These close verified request-shape gaps, not the complete HTTP handler backlog
below; bounded whole-query safety failures remain authoritative before caps.

The [Tempo ledger](../test/fixtures/traces/tempo_integration/README.md) also
records actual engine/Parquet oracles for empty/typed/name/kind search and
complete-retained trace-duration comparisons, plus actual HTTP-parser outcomes
for Grafana's discovery `limit`/`tag`. The subsequent builder increment adds
quoted search keys, link/instrumentation owners, all 25 advertised intrinsic
spellings and single-spanset typed/boolean/intrinsic discovery filters with
stored ID dictionaries. Search10/discovery13/metrics7 supersede older snapshots.
The 76 search and 53 discovery engine/Parquet probes distinguish unchanged
upstream predicates from authored probes and deliberate completeness extensions.
Full TraceQL, structural/selected discovery, streaming and deployed-client
acceptance remain open.

| Area | Remaining source-backed work and qualifications |
| --- | --- |
| Mimir ingestion | Complete remaining `TestDistributor` policies: HA deduplication, label drop/relabel, old/disabled exemplars and native downscaling. Port applicable OTLP translation/status cases, ordering/partial-write and metadata-policy errors. Legacy name-validation, injected creation-time zero samples and stateful policies differ from current contracts. |
| Mimir query language | Finish remaining blocks of partially selected aggregators/functions/literals/operators/subqueries/native histograms/name dropping. Unmapped files include Mimir selectors, extended/fill vectors, info, anchored/smoothed, optimizer-equivalence and delayed-name-removal cases. Preserve complete warning/error assertions, not only values. `upstream/{selectors,collision,staleness}.test` and `ours/{collision,staleness,subqueries}.test` are now fully replayed. |
| Mimir HTTP/errors | Remaining frontend unknown-function and aggregation-type diagnostics; blocked-query, length, cancellation/deadline and public annotation tables. Complete label-name/value handlers, metadata errors, format-query tables and request parsing. Remote read/streamed chunks, active-series/cardinality, metric/label search and analyze APIs are absent, not covered by ordinary discovery. |
| Mimir additional APIs | Tenant federation, ruler CRUD/evaluation/lifecycle, Alertmanager compatibility, backfill and Influx ingestion remain distinct public surfaces. Native Pulse rules are not equivalent Mimir API ports. Consul/Kafka/ring/cache/sharding internals need classification, not pretend Pulse replicas of those services. |
| Loki HTTP/errors | All 87 rows from 15 complete `pkg/loghttp` parameter tables have component/public-effect replay. Calendar parsing additionally replays all 16 Go long-fraction rows and 89 authored actual-Go controls, with 72 public HTTP attempts covering single-digit hours, inclusive timezone bounds and unchanged int64/byte policies; exhaustive grammar remains open. Complete `Test_writeError` retains 25 original rows/50 upstream executions, with four adapted HTTP categories and 21 explicit direct-row gaps/incompatibilities. Classifier/limit continuation retains all 22 classifier rows, three wrapped-limit rows and 11 prefix constraints; two limit policies have adapted public checks, not internal wrapping/classification parity. Cancellation/499, gRPC/aggregate precedence, reason labels, query-byte policy, exact bodies and duplicate-scalar/default edges remain open. Instant log-query admission and ignored tail delay still differ. |
| Loki language/pipelines | Complete syntax and three matcher-admission tables now retain all original rows with explicit policy differences, not full AST/diagnostic equivalence. Malformed partial JSON extraction, parser/pipeline error ownership, hint exits and exact diagnostics remain open. The complete reserved error-label comparison matrix replays 68 queries through both endpoints and HTTP methods; required error categories/fragments pass, not full diagnostic text/positions. Remaining formatter rows include date/layout/zone helpers, `now`, runtime errors and non-UTF-8 propagation. Existing broad selected Go/Sprig controls do not close whole-table gaps. |
| Loki additional APIs | Original OTLP promotion/drop policy block, enabled LBAC/aggregated-metric access, federation, deletion lifecycle, ruler compatibility, index shards and legacy query/tail aliases. Manifest stats, exact approximate-aggregation implementations and retained duplicates remain explicit adaptations/incompatibilities. Infrastructure-only bucket/scheduler/bloom assertions are separate. |
| Tempo discovery/search | Remaining `TestTagEndpoints` rows and complete helper assertions, including inspected-byte telemetry; malformed identifiers/query errors, condition-group limits and tenant validation. Full TraceQL structural/spanset/compare operations, federation and stored ID/span-duration discovery remain open. Multi-root original search assertions deliberately fail today. |
| Tempo trace/metrics | Span-pruning/default-pruning cases, complete no-polling trace assertions, trace diff/summary formats; remaining query-range exemplar/single-trace/max-series/end-cutoff/combine scenarios. Existing metric-content selections omit exemplars, unlimited overrides, streaming and backend lifecycle. Complete `pkg/api` parsing/default/error tables independently. |
| Tempo other APIs | Management/status/rings, overrides CRUD and the upstream MCP smoke surface remain unmapped. Pulse's stateless MCP version, tool risk boundary and absence of Tempo topology must not be silently changed to imitate an initialize/session-based upstream client. |
| Cross-surface operations | SDK/Collector/Grafana clients and real HTTP/gRPC transports, packaged artifacts, provider protocol failures, multi-instance publication/recovery, restart/retention/compaction, isolation/admission, cancellation and resource/capacity tests remain separate release requirements. A loopback store is not provider durability or representative customer load. |

Loki's complete `TestParseExpr_ShouldValidateLabelComparison` now passes all
68 original queries across instant/range GET/form POST: 272 requests, including
224 rejected requests verified to issue no provider operations. Typed reserved
error-label comparisons reject at parse time, not as evaluation failures.
The complete Loki HTTP query/parameter block now retains all 87 rows/35 original
rejection expectations. Component replay owns 56 rows; 51 request rows (20 overlap)
use 82 authenticated HTTP/WebSocket attempts with native Parquet/owned loopback S3.
Go request-struct assertions adapt to observable HTTP effects; source partial
assertions, int64/endpoint/resource boundaries and tail scheduling qualifications
remain explicit in [fixture provenance](../test/fixtures/logs/loki-upstream/http-parameters.md).
Index-statistics admission now reuses the same range parser as queries, matching
the pinned `ParseIndexStatsQuery` delegation. Forty-four authored GET/form-POST
attempts cover 12 unchanged metadata totals and 32 pre-provider rejections,
including the integer interval boundary. Payloads remain unread; full Loki
chunk-estimate, diagnostic and scalar-precedence parity is not implied.
Decimal timestamps/steps, `since`, global interval-before-limit sampling and
mixed/repeated or omitted/lone-empty series selectors no longer form unported
gaps. Positive intervals require bounded collection/sorting, not ordinary
streaming top-k. The complete Loki public error-writer table is now frozen,
including all incompatible outcomes, in [the error ledger](../test/fixtures/logs/loki-upstream/http-errors.md).
Four adapted source categories retain HTTP 400/504/500 statuses through public
endpoints; no exact-body or internal gRPC parity is claimed. The 98 error attempts
also expose and fix provider-term leakage in discovery responses, with all
15 finite-read shapes/both methods using fixed 503 JSON and a successful native
Parquet/S3 recovery control. The other 21 direct rows remain explicitly open or
incompatible, not skipped green tests.
The separate [classifier/limit ledger](../test/fixtures/logs/loki-upstream/error-classification.md)
now freezes all 22 classifier rows, three wrapped-limit rows and 11 logical
prefix constraints. No unused classifier or message-matching layer is added.
Two limit rows have public HTTP equivalents, including original quantities,
exact and one-unit-over boundaries and nonempty native Parquet/S3 controls.
All 22 category/reason pairs, internal Go identity/wrapping, prefix fallback and
the byte-limit policy remain unimplemented. Original length text `800h`/`721h`
still differs from Pulse's exact nanosecond diagnostic; entry-limit text matches
inside JSON. Provider strings matching the three source bodies stay sanitized
503, not inferred client 400. The 36 authored HTTP attempts pass on the existing
runtime; there is no runtime change or red-to-green claim for this increment.

The complete [syntax-admission table](../test/fixtures/logs/loki-upstream/syntax-admission.md)
now preserves all 206 original rows (159 accept/47 reject), duplicates, invalid
UTF-8 bytes, symbolic ASTs and exact source error arguments. Component replay
and 824 authenticated instant/range GET/form-POST attempts cover every row;
204 original admission outcomes agree. Eager invalid-regex rejection and
empty-selector acceptance remain two explicit existing policy differences,
not omitted or passing upstream cases. All 188 HTTP rejections avoid provider
access; a two-request nonempty native Parquet/S3 count control checks real reads.
The existing runtime needs no change. Exact diagnostics/categories/positions,
Go AST equality and syntax/helper tables outside `ParseTestCases` remain open.

The three complete [matcher-admission tables](../test/fixtures/logs/loki-upstream/matcher-admission.md)
add 30 original rows (15 accept/15 reject), all five matcher tuples and all 13
source error constructors. Component and 112 authenticated HTTP attempts replay
every row; eight rejected attempts make no provider requests. Eighteen original
admission outcomes agree. Twelve source selectivity rejections remain explicit
policy differences: Pulse accepts empty/negative/empty-compatible selectors,
including nested metric leaves, under existing budgets. Matcher-only discovery
still rejects a pipeline. Ten separate native Parquet/S3 read controls check
full-value/negative regexes and negative-only metric/log execution with missing
labels. No runtime change, exact diagnostic or Go error-identity parity is
claimed. The formatter source coverage below supersedes the earlier table gap.

The complete [label-parsing continuation](../test/fixtures/logs/loki-upstream/label-parsing.md)
now retains all four `TestParseLabels` rows, its trailing oversized-input
rejection and all four unreserved-word admissions. Native protobuf/component
and 34 authenticated HTTP requests replay every case with nonempty Parquet/S3
controls. Public discovery agrees on all original label maps; raw `bar=""`
retention is an explicit existing difference from Loki's write-time removal.
The original 16 MiB input rejects before provider access/publication at the
whole-request cap, not an isolated replay of Go's label-parser ceiling. A small
malformed-label control retains 204/per-entry-drop semantics, with subsequent
valid push/read recovery. Source error-presence/value/admission assertions stay
distinct; exact diagnostics, Go-label ordering and broader grammar/capacity
remain open. No production change is needed.

The complete [formatter/round-trip corpus](../test/fixtures/logs/loki-upstream/formatter-roundtrip.md)
now retains 196 rows across 20 source functions, all eight prettier functions,
94 literal outputs and four explicit rejection oracles. Component and public
HTTP checks cover admission of every literal input and applicable output
spelling; 1,375 HTTP requests include nonempty native Parquet/S3 semantic controls
and five seed writes. Actual validation still rejects unquoted dotted logfmt
sources, invalid IP operators and empty IP patterns, while ordinary zero-rank
topk/bottomk retain the existing empty-result difference from Loki's rejection.
No LogQL formatter, layout renderer, optimized-stage identity or Loki-internal
AST JSON codec is implemented; string/AST round-trip and exact response contracts
remain explicit gaps, not passing ports. Shared `ParseTestCases` provenance is
referenced without duplicating its 206 rows. No production behavior changes.

The complete [pipeline ownership corpus](../test/fixtures/logs/loki-upstream/pipeline-ownership.md)
retains six functions, 31 source rows, 95 assertion sites and 48 original method
executions. Thirty ordinary executions replay exact labels/categories, asserted
lines and the selected JSON/logfmt diagnostics through component tests and
240 authenticated HTTP reads plus one native Parquet/S3 seed write. Both output
modes and GET/form POST instant/range queries are covered. Nine deletion-wrapper
rows / 18 executions remain symbolic and unsupported; hash/String/cache internals
are not public ports. Empty keep has no public syntax, so its identity stage is
omitted explicitly, without changing or claiming the internal empty constructor.
Drop's unasserted lines and discarded match flags remain separate from authored
transport controls. No production behavior, budget or format changes.

The complete [label-builder corpus](../test/fixtures/logs/loki-upstream/label-builder.md)
retains every one of the 15 source tests and four helpers, with 107 test assertion
sites / 118 expanded events. Component tests and 232 authenticated HTTP reads
plus four native Parquet/S3 seed pushes replay literal public lookup/category,
deletion/grouping and preserve-error observations, and the original colliding
label inputs. Source completeness is not execution of Go's cache, HashSorted,
String, raw Set category priorities, arbitrary SetErr injection or hint flags.
The original metadata Add case exposed incorrect categorized output ownership:
received exact error labels now appear under parsed rather than metadata.
Flat values/name protection, metric-error guards and resource ceilings stay intact;
ordinary suffixed names remain metadata. Upgrade query-serving applications;
native tuples, storage and keyed bytes are unchanged. The ledger accounts for
every source function's replayed channels and symbolic boundaries separately.

The complete [sample-extractor corpus](../test/fixtures/logs/loki-upstream/sample-extractors.md)
retains all 16 tests, 185 assertion sites and 106 expanded method calls. All 88
ordinary calls have component and HTTP/native Parquet/S3 coverage, with
error-policy and interleaving controls totaling 398 reads and
three seed pushes. The 18 deletion-wrapper calls and Go hash/type/cache/hint
contracts remain symbolic. The original correlation-metadata gap at sequences
85/91/92 is closed by query-side projection of dedicated trace/span IDs, not by
renaming inputs or changing ingestion. Explicit attributes (including empty
values) retain ownership; stream/parser collisions use existing rules. Native
label reuse includes both IDs, with independently varying same-batch controls.
Additional public controls cover raw/categorized output, pipeline filters,
grouping and exclusion from stream selectors. Upgrade every query-serving
app/native pair to log tuple `{1,1,18}`, superseding historical snapshots below;
resource ceilings and storage/keyed bytes are unchanged.

For Mimir, continue with complete remaining binary,
aggregation, Mimir selector and upstream subquery blocks and error tables.

### Decisions that cannot be hidden by a green subset

Full upstream passing behavior conflicts with current documented choices:
Loki suppresses stored duplicate results while Pulse retains them; Tempo's
original multi-root traces search successfully upstream while Pulse rejects
ambiguous root summaries; Mimir injects creation-time zero samples while Pulse
retains start timestamps without synthetic points. Exact capacity/default/time
policies also differ. These are not authorization to discard data, guess roots,
relax ceilings or alter source oracles. Resolve each as an explicit product
decision before changing its implementation. Incompatible tests remain release
blockers for a full-equivalence claim, even when local rejection controls pass.

Before customer rollout, finish the public assertion/error inventory and close
or explicitly scope every remaining gap; run the exact shipped app/native
artifacts with real client/provider acceptance and representative load. Establish
an isolated staging rollout, tenant/privacy/security checks, a reversible
migration/rollback plan and explicit deployment approval. None of these gates
is proven by the selected fixture suite, and this work does not deploy anything.

## Product priority: reliability signals before archive replacement

The [reliability-first plan](reliability-first.md) sets the next product sequence:
persist bounded cross-signal service summaries, periodically assess them through
a budgeted decision model, and feed capped external investigations; then safely
separate processing from optional raw archival retention. Object requests,
summary/evidence storage and compute matter alongside model tokens. Existing
error/alert feeds remain useful, not the sole assessment gate. Full
Loki/Mimir/Tempo replacement is not a prerequisite
for that experience. This changes delivery priority, not the generic public
protocol scope or acceptance rules below. Existing correctness and operational
blockers still apply; no current retention or acknowledgement default changes.

## Upstream service integration ports

The normal Elixir suite now includes selected public request/response scenarios
from all three upstream service suites. These remain selected ports, **not a copy of
their complete integration suites or proof of full compatibility**. Each source
selection is pinned and separately licensed; expected data comes from upstream,
not from regenerating answers with Pulse.

| Backend | Imported selection and provenance | Elixir replay |
| --- | --- | --- |
| Mimir | [52 selected scenarios](../test/fixtures/promql/mimir/services/README.md): RW1/RW2 scalar/classic/native/custom histograms, summaries, exemplars and metadata; all seven ingester-query table rows; lookback/discovery windows; UTF-8 names, fingerprint fixture, invalid-range requests, query formatting and the exact grouped-vector execution-error scenario with all 50 source series | `test/pulse_web/controllers/mimir_service_conformance_test.exs` (79 tests: 51 upstream wrappers, 23 local controls and five shared-regex wrappers) |
| Loki | [30 integration-derived checks plus the separately catalogued engine/unit selections](../test/fixtures/logs/loki-upstream/README.md): ingest/query/labels/series/errors, disabled label policy, categorized labels, count/unwrap/filter results, detected fields, stream ordering, request policies, tail, approximate aggregations and both historical stored-result assertions; one range-resolution adaptation is explicit | `test/pulse_web/controllers/loki_upstream_integration_test.exs` (218 wrappers, including separately identified local controls; not 218 upstream service scenarios) |
| Tempo | [Selected service entry points plus public engine rows](../test/fixtures/traces/tempo_integration/README.md): discovery/special-character batches, basic search, V2 filtering, metric/step/cardinality selections and all ten original rich traces from `TestTraceByIDandTraceQL` for exact-ID retrieval. Multi-root search failures are explicitly separate incompatibility controls | `test/pulse_web/controllers/tempo_upstream_integration_test.exs`; independent native/reference/MCP replay in `search_expression_test.exs` |

The separate [Mimir query-engine corpus](../test/fixtures/promql/mimir/README.md)
now replays 1800 verbatim math, range-function, label, calendar, scalar-context,
operator, histogram, aggregation, time-modifier, sampling and duration-expression
evaluations through 214 memory/S3 HTTP fixture checks (6544 requests), plus
separately labelled local controls.
Two empty-`le` histogram evaluations from complete active `ours/histograms.test`
cases at lines 149–186 preserve both clears, seven samples per load, classic/
native inputs and warning/no-info oracles. The test producer now removes empty
load labels like pinned TSDB `head_append.go:565–574` (`WithoutEmpty`), leaving
the expected-output parser unchanged. The native empty-`le` case then correctly
omits the classic/native conflict and returns only `{le="3"}` with a warning.
This is a producer correction, not a runtime/ingestion/historical-record fix.
Four authored public tests cover both endpoints/adapters, nonempty ASCII/UTF-8
labels, all-empty non-name labels, authenticated success and denied/no-provider
controls. Exact two-case extraction SHA-256:
`5fd5026df225a350f120abb7c5956e6bcdb083d059e327d6067fc83a5d0e44e2`;
whole source `46b4ae0681f54d45704e3c4904efb54bd9dc69c76b2214d6af86b57fc1ad7374`;
TSDB source `ca88062c340dca7e70945a9cb5b823dd9ff8f90f67ea277feaba7568328e8f19`.
No upstream Mimir execution or production-provider/client acceptance is claimed.
Seven float-delta boundary evaluations preserve the complete four-series/
34-sample setup from pinned `upstream/functions.test:2704–2741`, with source
headers 1–5. Correct producer semantics already match Pulse; the test loader
instead inserted six rather than five missing positions for `_x5`, incorrectly
moving the late series from 5–10 minutes to 6–11 minutes and returning 4.5 rather
than the original 5.5 oracle. `_xN` now emits N omitted positions, while numeric/histogram
repetitions retain N+1. The exact new fixture has SHA-256
`9b566196238ffa16555200c4de0b3a6dc16c935ce95462fccc69fe785c65d960`.
It contains no `clear`; independently owned empty wrappers preserve that source
instead of inventing a directive. Both imported wrappers fail red with the old
producer and pass with the correction. Separate public `_x0`/`_x1` and numeric/
histogram `x0`/`x1` controls check counts, complete sums and no-provider auth
denial. No evaluator/runtime/native/storage/admission policy changed.
The complete three-evaluation `scalar()`-with-histograms block now ignores
histograms before applying the per-step singleton-float rule. Its duplicate
histogram load is retained; unchanged inputs and expectations replay through
both instant and one-step range HTTP endpoints on both adapters.
Twelve more unchanged positive-`k` topk/bottomk evaluations preserve required
histogram-omission info notices, including empty/mixed inputs and grouped/range
queries. The complete source load is retained. Separate controls cover
operation-specific notices, deduplication, request isolation and changing `k`.
Zero-`k` range annotation parity remains open: Pulse still emits no info for
unexecuted filters, unlike Mimir's eager range input reader.
Eight unchanged `functions.test:1915–1977` range-extrema evaluations retain the
complete original split loads. Mixed float/histogram windows now preserve info
for `min_over_time`/`max_over_time`; histogram-only extrema remain empty without
info. Values were already correct. No native or arithmetic change is needed.
Nine unchanged `functions.test:1558–1599` dispersion evaluations extend the
same mixed-window info policy to `stddev_over_time`/`stdvar_over_time`, retaining
histogram-only empties, ordinary float results and the constant-value regression.
Eight unchanged `aggregators.test:229–274` evaluations add `min`/`max`
histogram-ignored infos for both mixed and histogram-only groups. The four
float-only/NaN/grouping controls retain `expect no_info`; numerical results
are unchanged. The exact extraction is headers 1–5 plus that complete block,
SHA-256 `9e67bff7f892b8baa709efd2b2c1e20bab4b966272c7e4e88e91f91245dacdf7`.
Three unchanged `ours/functions.test:920–944` range evaluations retain the
complete timestamp/rate block and twelve original samples, including sparse
float, native and mixed series. `rate`/`increase` now emit the naming-heuristic
info only after producing a float-class result, including NaN/Inf, for nonempty
names without `_total`/`_sum`/`_count`/`_bucket`. Nil/histogram-only results do
not acquire it. Independent annotation-source controls cover exclusions,
insufficient/mixed outputs and request/batch isolation. The exact extraction
includes original headers 1–2, SHA-256
`7fcbe95f663373df144daaffb67ff66af8fba116eec7199f0f3d73e578f79c77`.
Two unchanged `ours/binary_operators.test:1706–1718` failures retain all twelve
input samples and both original one-to-one/group-right diagnostic regexes.
The pre-filter cardinality case previously returned a successful matrix because
only one left sample survived equality at any step. The pinned Mimir contract
checks matching input signatures before filtering, independently of output
presence. This is step-local; unmatched many-side inputs remain nonconflicting.
The sibling group-right case already rejected. Exact extraction includes
headers 1–2, SHA-256
`3d6f189743b7d4b391f25a76cb48eca0203d129af981b91c369ea2257eff9b1c`.
The harness retains the upstream failure directives and separately asserts
Pulse's existing HTTP 422 execution-error envelope, not upstream diagnostic-text
equality. Actual Prometheus 3.5.0 promtool execution confirms the historical
post-filter expectations; pinned Mimir's Prometheus fork includes the later
pre-filter bugfix (Prometheus PR 17668). Two authored expectations now follow
that modern contract without changing original source oracles.
Exact selections and per-file counts live in the fixture README;
these are not service-suite scenarios or additional Mimir cluster permutations.

Two unchanged `ours/functions.test` evaluations retain all three original
`label_replace` samples, including NaN, the valid replacement control and the
literal invalid-regex diagnostic. Bounded regex failures retain their original
pattern in `invalid regular expression in label_replace(): <pattern>` before
storage. Existing HTTP 400/`bad_data`, destination-error precedence and the
1024-byte ceiling remain; the engine oracle does not establish upstream wire
status parity. Authored authentication and multibyte/size controls stay separate.

Seven unchanged `ours/functions.test:956–1010` sort evaluations retain all ten
series/fifty samples, including nonfinite float and histogram sums. Public range
sorts previously returned ten series instead of five float series. Only range
`sort`/`sort_desc` now remove histogram-valued points and empty output series;
float/name preservation, label sorts, existing warnings and ordering bypass
remain. Authored one-step, mixed-type-at-different-times, label-sort, signed-zero,
authentication, batch-isolation and budget controls stay separate. A histogram-only
query still pays selected-sample admission before filtering. Exact extraction
includes original headers 1–2 and the final clear; SHA-256
`9825c23ece56ab718e935d9b3a7b45bbe91ef536d1b5c15645b74ade97924bf3`.
No native/storage/dependency or resource-ceiling change is needed.

The separate grouped-inclusion case at `ours/binary_operators.test:1543–1561`
remains an explicit divergence, not a passing import. With all twelve original
samples, `one_side == ignoring(disk) group_right(__name__)` over three
`many_side_*` metrics returns an empty result on Pulse but fails upstream;
the sibling multiplication already fails correctly. Memory/native-Parquet/S3
instant and one-step-range probes confirm it. Changing this would reverse
Pulse's documented post-filter grouped uniqueness contract, which actual
Prometheus 3.5.0 also follows. No policy change is made in this batch.

The complete four-oracle Loki `formatters.logqltest:85–105` block now separates
ordinary error-named labels from authoritative pipeline errors. The original
three loads and both malformed-JSON grouping oracles replay through GET/form
POST and native Parquet/S3. Hidden labels survive resets and genuine later
errors; rename/filter lookup differs from rendered templates/grouped output,
including Loki's single-field line-format optimization. Thirteen authored
comparisons against an actual clean pinned Go pipeline agree on lines,
labels and categories. No native change is needed; full native reserved-label,
diagnostic and parser-hint parity remain open. Nine older authored consumers
are explicitly adapted to preceding exclusive-end/missing-unwrap fixes,
without rewriting original source queries or oracles.

The complete Loki `binary_operations.logqltest:888–929` block retains all
57 entries and ten instant/range evaluations. Duplicate indexed-side failures
now preserve the original `found duplicate series on the right hand-side`
substring; the eight successful group-right controls keep their original values.
Authored controls cover left-side failures and unchanged unrelated diagnostics,
authentication and budget exhaustion. Shared matching carries side context only
for indexed duplicates; PromQL normalizes it to its existing error contract.
No matching, filtering, native or storage-policy change is intended.

The complete two-row Loki `Test_SampleExpr_Sort_Fail` (`ast_test.go:219–230`)
rejects named sort/sort_desc grouping; both original queries instead returned
200 on Pulse against empty and visible native-Parquet/S3 data. Recursive static
validation now rejects nonempty group labels before provider reads, including
nested calls, while empty grouping and ordinary aggregators remain admitted.
The original rejection substring survives HTTP 400/`parse_error`; HTTP framing
and positions are not upstream oracles. Separate authored controls cover
placements, empty/nonempty storage, asymmetric rates/order, absent windows and
authentication. Empty `without()` does not promise global cross-group ordering.
Block SHA-256: `182ba8fb9a9b0077bd465776e4fc2491acb8763d7416af0cb3f03e3d115473fe`.
No sorting algorithm, native/storage or resource-ceiling changes are needed.

Loki's pinned `vector_aggregations.logqltest:246–277` additionally contributes
four unchanged instant/range evaluations for compensated `sum_over_time`.
Both 7/10 residuals and total 17 survive HTTP native-Parquet/S3 replay, including
the final absent 20-second window. The first replay returned zeros. The fix
reuses existing compensated float64 summation; the materializing reference's
same historical bug is explicitly corrected against these independent oracles.
Unrelated source streams are omitted because all selected queries match only
`app="k"`; matching observations and expected results are unchanged.

The independent Loki `TestVectorAggEvaluator_Precision/sum()` case additionally
retains all 10,001 numeric inputs (`1e16`, then 10,000 ones) and the original
`10000000000010000` oracle. A distinct-series HTTP adaptation makes the input
vector observable through LogQL; sorted instant evaluation preserves original
numeric order. Vector `sum` now reuses compensated summation too, separately
correcting the materializing reference's same historical bug. Instant/range
GET/form POST native-Parquet/S3 replays include the absent later window; this
is a unit-to-HTTP adaptation, not an original upstream HTTP query.

Loki's `range_aggregations.logqltest:225–274` adds the complete seven-row load,
original negative-quantile rejection and median/+Inf oracles. Range parameters
now follow the unsigned `NUMBER` grammar, rejecting `-0.1`, `-0` and leading
plus signs before provider access without rejecting signed exponents or
changing ordinary signed scalar expressions. Fifty-six authenticated HTTP
requests cover original rows and explicitly labelled admission/positive controls.
HTTP `400`/`parse_error` is asserted, not exact upstream wording. Storage,
native formats and query ceilings are unchanged.

All five inputs and four quantile evaluations from Loki's
`range_aggregations.logqltest:409–440` additionally replay malformed JSON without
an unwrap target. Baseline returned pipeline errors instead of medians 5/6.
Missing/empty fields now discard earlier errors before sample creation, in
native and Elixir paths; usable targets and count/bytes retain their guards.
Separate native/fallback and direct Parquet controls retain scan-work charges
and skipped-sample accounting. Log tuple `{1,1,18}` fences old artifacts; upgrade
all query-serving app/native pairs. Storage/keyed bytes and ceilings are unchanged.

The complete `range_aggregations.logqltest:1727–1745` absence block retains both
original inputs and five instant/range oracles. Unwrapped-free absence omits
unused plain JSON execution only when the entire pipeline consists of plain
JSON parsers and line filters, after ordinary validation and pushdown planning.
Explicit fields, label/error/format consumers and other parsers disable this
narrow hint. Existing metadata errors and selected scan/work charging survive;
this is not blanket pipeline-error suppression or general parser-hint parity.
No native/storage/keyed-byte change; log tuple `{1,1,18}` remains sufficient.

Loki's complete `log_selection.logqltest:28–36` selection block independently
pins `[start,end)`: both original lines remain loaded, but the one at 20s is
excluded by the original 0–20s forward query. The raw-log HTTP range boundary
now normalizes its exclusive end before selection/top-k, after original-bound
request-policy checks. Metric windows, instant log queries, discovery/detected
APIs and shared evaluator/storage/MCP bounds retain their contracts. Empty and
minimum-bound windows must still validate within ordinary resource admission
without reading storage. This application-only correction changes no native
tuple, storage/keyed bytes or resource ceilings.

Tempo's `TestTiesInBottomK / all values tied` additionally retains all original
`x/y/z=[5,5,5]` arrays and `k=2`, using an explicit nine-span HTTP adapter.
Bottom-k keeps `y,z`, while top-k keeps `x,y`; standalone and arithmetic-leaf
finalizers replay through authenticated OTLP/native-Parquet/S3 after cold reload.
The native tie comparator changes bottom-k direction only. This establishes
homogeneous string-label ties, not general mixed-type/multi-label ordering.
The three original `TestMetricsSecondStage` filter-before-ranking query strings
retain their acceptance oracle, with explicitly local numerical loads. A single
finite scalar prefilter now runs before native ranking on an unranked leaf;
order-sensitive bottom-k and arithmetic-leaf controls guard against reordering.
All finalized slots spend shared native work before filtering. Arbitrary stage
chains and ranking arithmetic results remain unsupported.
Trace metrics capability **5** fences old artifact behavior; all serving
application/native pairs must upgrade together. Trace tuples, storage/keyed
bytes, request admission and resource ceilings are unchanged.

Tempo's original `Test_parseTimestamp / RFC3339nano format` row retains its exact
`1257894000000000001` oracle and original timestamp string. The public one-span
metric producer is explicitly authored. DateTime validation still applies;
restoring the fractional nanosecond tail fixes inclusion at the supplied bound
through both metric endpoints. Numeric/timezone/adjacent-bound controls retain
existing alignment and numeric-second truncation semantics. This application-only
fix leaves trace metrics capability 5, native/storage/keyed bytes and ceilings
unchanged; full timestamp grammar/client parity remains open.

Data-bearing replays use native Parquet and the real S3 HTTP adapter against test-owned
loopback object stores. Loki and Tempo also use live authenticated HTTP
listeners; Mimir uses the production Phoenix endpoint through ConnTest. They
require no upstream server, Go, Docker or network downloads during replay. They
do not model upstream WAL/head/block/live-store phases: Pulse publishes durable
segments before acknowledging ingestion. Separate Pulse controls cover malformed
inputs, boundaries, isolation and transport variants, and are not counted as
additional upstream cases.

The current increment preserves Mimir's exact grouped-vector collision error
instead of its former generic diagnostic. Collision checks occur after filtering
and independently per step; unrelated ambiguity/duplicate diagnostics remain
unchanged. It also adds Loki's -72h/-48h stored-result cases and Tempo's original
ten-trace generator, retaining independent upstream expected contents across
v1/v2 JSON/protobuf and fresh manifest reads. No storage, keyed-byte, native ABI
or resource-ceiling change is introduced; upgrade query-serving applications
for consistent Mimir diagnostics.

Two deliberate design conflicts remain unresolved, not reported as passing
upstream tests: Loki's duplicate suppression/statistics versus retained duplicate
entries, and Tempo's successful multi-root search versus fail-whole root-summary
conflicts. Tempo's original search assertions were executed and returned 409;
the separately named local controls preserve that explicit incompatibility.
Do not rewrite the original producer's parent graph or weaken the expected
search results to hide it. TSDB/Kafka/WAL/ring/sharding permutations remain
unported rather than simulated through repeated Pulse ingestion.

The preceding three-service replay, seed 41 and four concurrent cases, passed
**364 checks**. This includes explicitly named local/incompatibility controls,
not 364 passing upstream scenarios. The earlier unchanged-runtime baseline
passed 357 checks. Logs are retained under `.amp/in/artifacts/` as
`upstream-three-baseline.log`, `upstream-three-final.log` and
`upstream-increment-full-suite.log`.

The earlier whole-repository checkpoint passed 2489/2493 checks, with four
failures sharing a missing-authority storage-query defect. The authorized
follow-up fixes optional-boolean handling in `S3.query_manifest`: omitted flags
no longer reach strict `and`/`not`, and callers requesting the distinct authority
failure retain it. A public regression covers all nine omitted/false/true flag
combinations for logs, metrics and traces, without cache population or LIST
reconstruction. The original append-buffer/log-alert/Sentry/reliability set now
passes **124 checks** (`storage-option-before.log`, `storage-option-after.log`).

The follow-up also strengthens five existing Mimir parameter cases to their
complete original envelopes; three separately named controller controls cover
GET/form POST, precedence, authorization, bounded reflection and the inclusive
11,000-point ceiling. No successful grammar or ceiling is relaxed to match
upstream's interval-count boundary. Loki adds the two original `TestDecolorizer`
rows in one wrapper and 129 independently Go-pattern-derived local controls in
another. The controls reproduce ordinary-text loss after malformed escapes;
the independent recognizer preserves unmatched input and supports the pinned
C1/BEL/parameter semantics. Another 20,000 disposable Go-pattern comparisons
match the compiled pipeline with unchanged labels/times. These are unit-table
and diagnostic continuations, not additional complete upstream service suites.
The preceding three-service replay passed **366 checks**, seed 41/four concurrent
cases, in 78.4s (`storage-compatibility-three-services.log`), including the
separately identified local/incompatibility controls.

The preceding whole-repository validation, `ERL_FLAGS='+S 4:4' mise exec -- mix test
--seed 0 --max-cases 4 --warnings-as-errors`: **2499 passed, one optional skipped,
37 optional excluded**, in 208.6s (`storage-compatibility-full-suite.log`). Compile
with warnings as errors, scoped strict Credo, scoped formatting and whitespace
checks pass. Native source/ABI, storage/keyed bytes and resource ceilings are
unchanged; native unit tests were not separately rerun. This is local evidence,
not provider-capacity or deployed-client acceptance. Changes remain uncommitted.

The next Tempo continuation ports six original v2 name-content rows from
`TestTagEndpoints`, keeping all seven input batches and original scope/name
expectations, including the no-match service-name hint. Independent execution
of the pinned public helper yields 25 static suggestions, not the older v2.9
fixture's 20. Initial unfiltered/service-filtered rows fail on the five missing
ID names; the existing explicit-span row passes. Native and reference vocabularies
now match the helper. This does not implement ID-value discovery. All 25 names
reserve entries inside the existing 5,000-pair budget before stored names and
v1 flattening; exact-limit/overflow controls cover both paths with and without
filters. Old v2.9 source bytes/hashes stay intact, and only their vocabulary
expectations are explicitly superseded. The six source rows and two local
controls pass seed52. Inspected-byte metadata and gRPC helper assertions remain
unported, not silently omitted from a full-service claim. Upgrade serving
applications/native artifacts together; tuples, storage and keyed bytes remain
unchanged. Provenance and red/green logs are recorded in the fixture README.

Current whole-repository validation passes **2507 checks**, one optional skipped
and 37 optional excluded, seed0/four concurrent cases, in 198.5s
(`tempo-name-vocabulary-full-suite-final.log`). Its first run found two more
end-to-end expectations retaining the historical 20-name vocabulary; only that
portion now uses the independently frozen newer helper, with no stored-name or
value assertions removed. The final combined three-service/Tempo end-to-end/
default-name/intrinsic replay passes **409 checks**, seed41, in 80.0s
(`tempo-name-vocabulary-combined-final.log`). All **133 native codec tests**,
compile with warnings as errors, strict Credo, scoped Elixir/Rust formatting
and whitespace checks pass. This remains local protocol evidence, not deployed
client/provider/capacity acceptance. Changes are uncommitted and unpushed.

The ports exposed and fixed bounded HTTP compatibility gaps: Prometheus
`lookback_delta`; Loki selector-only discovery/stats and window-derived default
range resolution; Tempo bare v1 keys, quoted attribute targets and unescaped
slashes. Follow-ups fixed remote-write float/native-histogram timestamp
collisions, negotiated Loki label categories and Tempo unscoped/default-window
search. The next selected Loki detected-field/ordering cases passed unchanged.
Five original Tempo `TestParseIdentifier` mappings additionally expose mixed
quoted/ordinary discovery keys. Bounded normalization admits dot-separated
portions before existing scope/decoded-key validation. Authored public
native-Parquet/S3 consumers cover v1/v2, JSON/protobuf, filters/windows,
authorization and 256/257-byte boundaries. Whole quoted keys retain the
documented JSON escape profile; mixed portions decode only quote/backslash.
The first proposed implementation tightened whole-key escapes; review caught
that contract reversal, which is excluded from the final additive fix.
The source rows establish exact key mappings, not original HTTP result oracles;
complete lexer concatenation and predicate/search/metric syntax remain open.
Tempo V2 exact-ID filtering now validates the full stored trace before independent
ancestor/descendant expansion. Explicitly selected subsets carry PARTIAL; missing
reads, corrupt/legacy/conflicting nonmatches and exhausted budgets still fail
whole. This filter adds bounded BEAM conversion work, not a native/storage change.
Its oversized-URI control retains HTTP 414 rather than upstream's 400.
Mimir's next five scenarios normalize empty-valued labels before merging and
reject a nonempty reserved RW2 symbol before any sample/metadata publication.
Duplicate/empty names and invalid UTF-8 validate before removing empty values;
all raw labels/points still consume admission and rejected-point accounting.
Label-order scenarios already passed, so no ordering fix was invented.
Existing query budgets, feature gates and shared-object-store authority
remain unchanged. Tempo now requires search capability5, tuple `{2,1,3,5,12}`;
unscoped predicates use span-key precedence, not a resource/span OR. Omitted or
paired-zero HTTP bounds search all retained context, not Tempo's ingester-only
tier. Colliding or empty-valued-label remote-write requests change normalized
fingerprints and bytes: drain affected retries and replace all receiving
application/native pairs before resuming them. The native tuple is unchanged
and startup does not fence older receivers. Never evade keyed 409s;
[operator guidance](../docs/querying.md#native-histograms) applies.

Previous increment's whole-repository validation: `mix precommit --seed 0
--max-cases 4 --warnings-as-errors` passed **1760 tests, 1 existing skipped,
37 optional excluded**. A final three-service replay passed all 95 tests at
seed 41. Codec `cargo test --release` passed 133 tests; strict Credo, formatter,
Rustfmt and whitespace checks passed. Strict codec Clippy passed for debug and
release with Rust/Clippy **1.97.1**; an earlier Rust 1.94 run reported two unchanged
`nonminimal_bool` warnings in trace-segment pruning, not fixed by these ports.
The green suite still logged compaction timeouts/CAS warnings and the intentional
gRPC handler crash; it does not close those diagnostics or capacity acceptance.

The next increment ports six Mimir UTF8Validation rows, one Loki per-request
length case and fifteen Tempo metric-only rows. Baselines reproduced Mimir's
quoted-metric query returning 400 after successful ingestion and Loki's ignored
one-minute policy returning 200. Quoted UTF-8 selector names now reuse the
existing matcher AST; no receiver validation-mode knob or grammar expansion
outside selectors is introduced. Loki's `maxQueryLength` checks effective finite
bounds before storage across finite endpoints. Other policy fields, duplicate or
malformed policies and live-tail policies explicitly reject rather than silently
run unrestricted; this stricter policy is not exact malformed-header parity.
Existing server ceilings cannot be increased by the request. Upgrade all query
applications before relying on either feature; no native/storage/keyed-byte
change or retry drain is required.

Tempo's selected metric tables passed on unchanged runtime. The timed/random
producer is frozen to sixty single spans; no exemplar request/assertion, gRPC
transport or metrics expression arithmetic is claimed. All 3/4/122 interval
counts, six ranking cardinalities, five range/instant reductions and the average
comparison are preserved. Independent asymmetric controls verify actual ranking
identities and span-weighted durations, not just agreement between two Pulse
outputs. Fixture READMEs preserve pinned source hashes, licenses, baseline
evidence and exact harness adaptations.

Validation before the span-ID continuation:

- `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix precommit
  --seed 69 --max-cases 4 --warnings-as-errors`: **1800 passed, 1 existing
  optional promtool skip, 37 optional exclusions**, including compile/dependency/
  formatter checks. Runtime: 225.3 seconds.
- All three service replay files together at seed 70: **130 passed**.
  The targeted Tempo metric/HTTP set also passed all 46 tests at seed 68.
- Strict Credo checked 437 source files with no findings; `git diff --check`
  passed. No Rust sources changed; native Parquet/S3 execution was exercised by
  the Elixir suites, not a separate new Cargo unit-test run.
- The full green run still logged compaction timeouts/conflicts, manifest CAS
  warnings and an acceptor teardown error, alongside deliberate oversized-URI
  and gRPC-crash controls. Passing tests do not resolve those diagnostics or
  establish provider/capacity/deployed-client acceptance. No deployment or
  shared infrastructure changes were performed.

The subsequent continuation selects two Tempo span-ID metric-cardinality cases
and Loki's four-line tail plus standalone per-request-limits test. Both Tempo
source selections failed with HTTP 400 before runtime edits (34/37 wrappers
passed, seed 71). Native `by (span:id)` now groups validated core IDs as
fixed-width lowercase strings, distinct from ordinary `span.id` attributes.
Original string/int64 types, reused IDs across traces, leading zeros, high bits,
legacy core-only rows and instant/range responses have separate controls.
Exactly 10,000 ID series succeed; 10,001 fail whole while an ungrouped count
still sees all source spans. The upstream unlimited-series override, exemplar
request and streaming transport are explicitly not selected or implemented.
The metrics capability advances independently to **2**, fenced at startup;
the trace tuple, storage format and keyed bytes remain unchanged. Upgrade all
query-serving app/native pairs before relying on the syntax, without a data
migration or retry drain for this addition.

Both new Loki ports passed unchanged. A separate authenticated native-S3/socket
control covers explicit history bounds, matching live formatted lines, durable
finite-query visibility and monitored socket shutdown. These tests do not
establish cross-instance continuity, full tail completeness or Loki's topology.
All additions preserve pinned source/license provenance and distinguish harness
adaptations and local controls from source expectations.

Final validation for this continuation:

- `mix precommit --seed 75 --max-cases 4 --warnings-as-errors`: **1807 passed,
  1 existing optional promtool skip, 37 optional exclusions**, 196.7 seconds.
  Compile/dependency/formatter checks passed too.
- All three service files plus the trace metrics unit and HTTP files:
  **149 passed**, seed 76. The service files contain 60 Mimir, 39 Loki and
  37 Tempo wrappers, with source ports and local controls counted separately.
- Codec `cargo test --release`: **133 passed**. Release Clippy with all targets
  and warnings denied passed on Rust 1.97.1. Direct native validation admitted
  ID grouping and rejected numeric ID operations and six-key grouping.
- Strict Credo checked 437 source files without findings. Elixir formatter,
  Rustfmt and whitespace checks passed. The green full suite still logged
  compaction timeouts/conflicts and manifest CAS warnings, alongside intentional
  oversized-URI/gRPC-crash controls; none is claimed resolved by these ports.
- All changes remain local and uncommitted. No upstream multi-service suite,
  deployed provider/client, infrastructure change or data migration was run.

The next continuation selects five more Tempo metric/HTTP-validation rows and
Mimir's `TestHashCollisionHandling` public result. Both empty-result Tempo
assertions failed before the native fix (seed 78); zero-step cases already
rejected, but the six-minute `35ms` request incorrectly succeeded (seed 80).
Ungrouped counts/rates now return zero series values after a successful scan,
without fabricating grouped/numeric observations or masking scan failures.
Range admission checks the original interval quotient against 10,000 before
alignment adds boundary intervals. Separate public-query controls distinguish
10,000 requested intervals, a sub-step remainder and 10,001 intervals, and
exercise empty tenants, filtered/absent spans, instant results and all aligned
zero timestamps. No safety ceiling is increased. The later diagnostic continuation
preserves the original `TestQueryRangeExemplars` ErrorContains assertion:
`step of 35ms is too small, minimum step for given range is 36ms` for the
six-minute request, with no provider reads. The numeric minimum uses the original
unaligned range and integer division; it is not a new query ceiling.
The complete four-row `TestParseQueryRangeNegativeStep`
(`pkg/api/http_test.go:1276–1287`, same Tempo revision) also preserves the
original `step must be positive` rejection substring for `-1h`, `-30m`,
`-1.5` and `-0.001`. Authored controls prove no provider work even with visible
Parquet, positive execution and instant step ignoring. Malformed/zero/negative
`since` policies remain distinct; no negative range step becomes executable.
This application-only diagnostic fix leaves metrics capability 5 unchanged.
The complete `TestParseQueryRequestInvalidBounds` (`http_test.go:1241–1274`)
adds two original requests through both instant/range endpoints, retaining
their start/end parameter-error substrings. The metric-only timestamp parser
returns parameter context directly, without another parsing layer. Authored
visible-Parquet and authorization controls preserve no-provider rejections,
end/since/start precedence, admitted-invalid-window generic errors and generic
discovery errors. Accepted grammar, numeric/nanosecond semantics and defaults
are unchanged; full Go error detail/precedence parity remains open.
The same pin's complete `Test_determineBounds / invalid since` row
(`http_test.go:1400–1413`) adds its unchanged bounds, `HI!` input and required
`could not parse 'since' parameter:` substring. Only malformed parsing gains
this diagnostic; parsed zero/negative `since` values keep the existing policy
rejection. Query, step and numerical span consumers are authored HTTP adapters,
not an upstream numerical oracle or a full bounds-table replay. Visible Parquet
and no-provider rejection controls preserve existing admission and precedence.
Exemplar production/request and gRPC remain outside
this selection. Serving app/native pairs must all upgrade for consistent results;
storage, keyed bytes and the native ABI are unchanged in this continuation.

Four original `TestQuerierParseSearchRequest` rows at the same Tempo pin
(`http_test.go:83–97,195–199`) retain `limit=0`, `-5`, `five` and `4294967298`
with exact helper errors. HTTP previously rejected them generically; it now
preserves the positive-number or ParseUint syntax/range diagnostic without
altering accepted grammar, default 100, cap 1000, `spss` or auth/window
precedence. Rejected context stays within the existing ten-byte admission bound;
over-cap and longer-input policy failures stay generic. Five new public tests
issue 33 GETs: 11 successful native-S3 searches, 17 rejected and five unauthorized,
plus five authored OTLP publications. Original helper messages and authored
HTTP consumers are distinguished; no upstream Go/server execution is claimed.
Source test/implementation SHA-256 values are
`6dd0951e0e691bdef2260ce2cb973d90d3a55297cbd2faf1e17acdb5e3880540` /
`328380983c1476278b89e1ee94e6609b00dcac1ee7dbe13111ab449310d83c8c`.
No native, storage or resource-ceiling change is needed.

Three complete further rows (`http_test.go:200–204,233–242`) keep original
`/api/search?spss=-2`, `four` and `4294967296` requests and exact helper errors.
They previously rejected generically; shared bounded search-parameter handling
now retains their syntax/range context without changing admission, default 3,
sampling cap 100 or ten-byte bounds. Parsed zero/over-cap and longer input
policy failures stay generic; auth/window/limit precedence remains.
Four new tests issue 33 GETs (nine successes, twenty policy/parse rejections,
four unauthorized) and four OTLP publications against native-Parquet/owned S3.
All 24 rejection/auth attempts avoid provider work. Authored four-span controls
check default/1/2/100 sampling, plus and ten-byte leading-zero admission, quoting,
size boundaries and precedence; they are not original Tempo numerical oracles.
Original helper errors retain the test/implementation hashes above. Limit,
empty-Accept and existing quoted/search/window selections pass unchanged.
No upstream Go execution, native/storage or resource-ceiling change.

Three further complete Tempo search-request rows (`http_test.go:180–194`)
preserve the exact URLs `start=-1&end=20`,
`start=4294967296&end=4294967297` and `start=10&end=-1`, with their original
parameter-specific ParseUint syntax/range errors. Existing bounded search
parsing now carries start/end context; no shared seconds parser, discovery or
metrics behavior changes. Partial/mixed-zero/reversed windows, plus-prefixed
numeric bounds and eleven-byte inputs retain generic policy errors. Auth,
unknown-parameter, start-before-end and window-before-limit precedence remain.
Four new actual-listener/native-Parquet/S3 tests make 32 search GETs (eight
200, twenty 400 and four 401) plus four OTLP publications. All 24 rejection/
auth attempts preserve provider history. Original helper error oracles are
distinguished from authored one-span producers, numerical results and HTTP
consumers. Test/implementation SHA-256 values are unchanged from above.
Focused bound/limit/spss selections pass thirteen tests and three adjacent
retained-search/window/quoted-key tests pass. No upstream Go execution, native/
storage/keyed-byte or resource-ceiling change.

The same Tempo pin's original `TestMarshalingFormatFromAcceptHeader` row
(`http_test.go:24–43`) explicitly supplies an empty header and selects JSON.
Both public lookup versions previously returned 406 for that value, despite
successful no-header/JSON/protobuf controls. A single empty header now follows
the no-header JSON default. Four authored HTTP tests issue 36 lookup GETs and
four OTLP publications through owned actual listeners/native-Parquet/S3.
Body/MIME equivalence and auth/parameter/no-provider rejection checks are
adaptations of the helper oracle, not original upstream HTTP cases.
Existing multiple-empty, empty-plus-protobuf, unsupported-media and general
quality/list negotiation policies remain unchanged. Source hashes remain those
of the search-limit test/implementation above; frontend handler SHA-256:
`d1f786689f6928a7b4e9609a83361acca149672abb3c3ec1552b588afb853b05`.
No upstream Go execution, native/storage-format or resource-ceiling change.

Loki's complete `TestNestedJSONFieldDetection` (`detected_fields_test.go:1471–1648`)
retains four original line binaries and both subtests: seven valid path/type
oracles and ten difficult-key paths. The difficult pair's trailing object commas
previously produced HTTP 200 `{}` through both GET and form POST; only strict
decoder admission prevented its fields from appearing. Detection now applies a
string/escape-aware terminal-object-comma pass only after strict decoding fails,
then strictly decodes the whole smaller result. Existing ordered/partial JSON
helpers cannot supply the complete detector paths and were not reused blindly.
Candidate offsets/disjoint chunks grow linearly, with no growing-prefix copies,
after newest-line selection inside existing heap/deadline/scan bounds. Array
commas, leading/doubled commas, missing values, unclosed strings and trailing
garbage remain invalid; valid string contents are unchanged. Public controls
preserve logfmt fallback, authentication/admission rejection and scan limits;
ordinary LogQL `| json` still reports `JSONParserErr` for the same input.
Complete function SHA-256:
`d90a731058af10163cdebda0c882ebafc7acb4f7c66c99ab75c50e34d6bfcbed`.
Producer/request/envelope controls are explicit adaptations, not upstream
Go/server execution or general malformed-JSON/duplicate-key/hint parity.
Transport/OTLP grammar, native/storage/keyed bytes and ceilings remain unchanged.

The complete numeric-boolean `TestQuerier_DetectedLabels` subtest at pinned
`querier_test.go:1783–1821` preserves all five input names/nine values and both
three-name assertions. GET/form POST previously omitted `boolean-ints` while
`/series` proved its values survived native-Parquet/S3 publication. Suggestions
now retain nonempty one/two-value sets consisting solely of literal `0`/`1`,
as in `shouldRejectLabel` (`querier.go:966–1009`). Other numeric/UUID rejection,
static labels and integer-first field typing remain unchanged. The ingester
mock becomes singleton-label streams with authored carrier text and a positive
window; those inputs are explicitly distinguished from original source logs.
Separate controls cover literal/decimal/signed/mixed/static/UUID sets, field
typing, empty windows, auth/admission rejection and fail-whole scan limits.
Exact frozen subtest SHA-256:
`0240f47cc9e9678602ff7701aa5b69866222c6570af45c4626124f5335aefff0`;
whole test `630560c5f11c336bf7eb547e728b6eafebc7627a0483bc6bfa63177c9b9b3022`;
production source `61bd4bc33e6bf897daf06eae0e844b4080653d01f251b6e8906192caa4b10ad0`.
No upstream Go/server execution, HLL-estimation or deployed-client acceptance
is claimed. Upgrade query applications; native/storage/keyed bytes, tuples and
resource ceilings are unchanged.

The existing frozen Loki JSON parser row `utf8 error rune`
(`parser_test.go:137–152`) also exposes a separate detector mismatch: field-value
GET/form POST retained U+FFFD while ordinary `| json` already returned the
original three-field oracle, including `foo=" "`. Upstream detector
`detected_fields.go:407–419` uses the same `NewJSONParser(true)` and
`parser.go:281–293` cleans decoded replacement runes. The detector-local string
conversion now does likewise, leaving raw lines, keys/paths and metadata alone.
The original row is reused, not counted as a newly imported upstream case;
HTTP carriers, windows and boundary/auth/resource assertions are adaptations.
Whole parser-test SHA-256:
`346b91ced2d38e51d8cf7fd8acb3335ea5796e9286fd901b45dd625c0b3634ff`;
complete selected row:
`96a487acc7f5b19984a56930f414bd3ffb1eeac186754d0dcd5a7e5aae0d2d7f`;
parser implementation:
`e844f4036afcb11d8e84235a77b837a82f21d6c3819a05d3c150eb7812786bfd`;
detector implementation:
`391608fcc1aa68902f097a8cac47c94b68fce187161f52f112b313c1f561d06f`.
Upgrade query-serving applications; no native/storage-format or ceiling change,
upstream Go execution or full detector/parser parity claim.

Combined UUID-correlation/detected-value validation uses normal persisted modules:
complete Mimir/Tempo HTTP files pass 511 tests, and complete Sentry/Loki HTTP
files pass 371, for 882 public HTTP-file tests. Another 420 selected shared
errors/projection, PromQL, LogQL, trace-metrics and Loki-query-controller tests
pass after final compilation: 1302 tests across the final selections, not the
whole repository. All runs use warnings-as-errors, serial execution and
`ERL_FLAGS='+S 2:2 +SDcpu 1'`. Normal compilation, strict Credo over 464 files,
changed-Elixir formatting and whitespace checks pass. Logs:
`.amp/in/artifacts/four-surfaces-thirteenth-*`. No upstream-server, deployed-client
or production-provider acceptance, commit, push or historical repair is implied.

The existing Loki `duplicate from line property` row
(`parser_test.go:1301–1311`) exposes detector-only last-write logfmt ownership.
With exact original `foo="bar"` stream labels and
`foobar="foo bar" foobar=10ms`, GET/form POST return `10ms`; with explicit
`| logfmt`, they return both values. Ordinary non-strict and strict parsing already
retain the complete original oracle. Upstream detector `detected_fields.go:407–429`
uses that same parser, whose first-retained extraction check is at
`parser.go:415–445`. Ordered first-write ownership of the final sanitized,
stream-suffixed name corrects the detector, including empty-first, normalized-key
and suffix-collision controls. Raw bytes, metadata and query resource policies
stay unchanged. This reuses the frozen `logfmt.json` row, not a new source import;
HTTP carriers/windows/controls are explicit adaptations. Original-row SHA-256:
`907c9c52ee3423bf82f5b9c32259e25d5bf66952d702a5c465e8a9f6d564c289`.
Whole parser-test/parser/detector hashes remain as recorded above. No upstream
Go execution, native/storage-format/ABI or resource-ceiling change is claimed.

Combined legacy-stacktrace/detected-logfmt verification passes 511 complete
Mimir/Tempo HTTP-file tests and 375 complete Sentry/Loki HTTP-file tests,
plus 420 selected shared regressions after final persisted compilation:
1306 tests across the final selections, not the whole repository. Normal
warnings-as-errors compilation, full strict Credo over 464 files, changed-Elixir
formatting and whitespace checks pass. All test runs use serial execution,
warnings-as-errors and `ERL_FLAGS='+S 2:2 +SDcpu 1'`. Logs:
`.amp/in/artifacts/four-surfaces-fourteenth-*`. Earlier overlapping Sentry/shared
runs are not additive coverage. Changes remain local, uncommitted and unpushed;
no historical repair, upstream execution or provider/client acceptance follows.

In the earlier hash-collision continuation, Mimir's exact tenant, two label sets,
same-time values and full ordered vector passed before runtime changes.
Native diagnostics confirmed distinct Pulse IDs:
the upstream labels collide under its fingerprints, not Pulse's StableHash.
That port is not evidence for Pulse hash-collision handling. No new Loki behavior
was claimed in that continuation; its existing public ports remain in combined
regression validation. Source hashes, licenses and adaptations are retained in
each fixture README.

Validation for the empty-selection/interval continuation:

- `mix precommit --seed 82 --max-cases 4 --warnings-as-errors`: **1815 passed,
  1 existing optional promtool skip, 37 optional exclusions**, 238.4 seconds.
- All three service files plus trace metrics unit/HTTP tests: **157 passed**,
  seed 83. Service totals are 61 Mimir, 39 Loki and 42 Tempo wrappers.
- Codec release tests: **133 passed**. Release Clippy with all targets and
  warnings denied passed using Rust 1.97.1. Strict Credo checked 437 files with
  no findings; formatter, Rustfmt and whitespace checks passed.
- The full green run still logged compaction timeouts/conflicts and manifest
  CAS warnings, plus intentional oversized-URI and gRPC-crash controls. These
  ports do not resolve those diagnostics or establish provider/client capacity.
  Changes remain local and uncommitted; no deployment or data migration ran.

The next continuation ports eight Mimir invalid-range requests and Loki's
`TestProbabilisticQuery`. All eight Mimir HTTP/status/errorType assertions
already passed; diagnostics deliberately retain Pulse's generic wording.
The omitted-resolution subquery initially rejected as unsupported syntax;
the grammar batch below adds it while still rejecting range-valued range-query
results. An initial Mimir baseline had two existing writes
return 503 without captured bodies; its same-seed expanded replay passed all
69 tests. No cause or runtime fix for those write failures is claimed.

The Loki instant query failed with HTTP 400 before the syntax/evaluator change
(seed 84). `approx_topk` now uses exact ranking with unchanged scan, log-sample,
work, intermediate-point, deadline and heap budgets. It requires a positive
signed-int64 integer literal, rejects all outer grouping and rejects range mode
across the whole expression before provider work. Three local controls cover
full values, windows, inner aggregation, arithmetic, GET/form POST, invalid
ranks/grouping, nested mode rejection and fail-whole budgets with `k=1`.
This does not implement probabilistic sketches, distributed merging or
high-cardinality acceleration. Only serving application upgrades are needed
for this operator; no native/storage/keyed-byte change or retry drain.

Validation for the bounded ranking/invalid-request continuation:

- Loki HTTP/WebSocket, module, LogQL and mixed-query-batch tests: **386 passed**,
  seed 87. All three service files plus trace metrics unit/HTTP tests:
  **169 passed**, seed 89; service totals are 69 Mimir, 43 Loki and 42 Tempo.
- `mix precommit --seed 88 --max-cases 4 --warnings-as-errors`: **1824/1827
  passed, 3 failed, 1 optional promtool skip, 37 optional exclusions**, 400s.
  Failures were the 60s filtered-intrinsic discovery test timeout, gRPC admission
  reply timing, and the 150k-span trace query deadline. All three passed unchanged
  under `mix test --failed --max-cases 1 --seed 88 --warnings-as-errors` in 8.9s.
  No timeout/budget was raised or assertion skipped. Runner load averages were
  approximately 193/201/138 during the failed run, but causation is unproven;
  the full suite is not claimed green or the underlying timing issue fixed.
- Strict Credo: **437 files, no issues**. Precommit compile, unused-dependency
  and formatter stages passed. No native code changed in this increment.
  Source pins, attribution, adaptations and baseline failures are recorded in
  each selected fixture README. Changes remain local and uncommitted.
- Repeated combined runs at seed 90 each passed **168/169**: the four-case
  concurrent run hit HTTP 500 in an existing Loki category-control push; the
  serial run hit HTTP 503 ingesting an existing Tempo legacy-filter control.
  Both passed alone unchanged in 1.9s and 4.9s respectively. Original response
  bodies were not captured; the Loki push helper now includes the body in its
  failure diagnostic. These failures remain unexplained, even with serial
  tests; neither lower concurrency nor this increment is claimed to fix them.
- Final selection of all twelve additions, including exact result lengths:
  **12 passed, 100 excluded**, seed 91, serial execution, 7.9s. This covers
  nine selected upstream cases and three Pulse controls on the final runtime.

### Bounded distinct-count continuation

The two public queries in Loki's `TestApproxCountDistinctQuery` failed with
HTTP 400 before the change (seed 101). Their four original logfmt writes,
overlapping `shared` values across devices, relative timestamps, full labels,
exact queries and one-series value `3` expectations now replay in Elixir.
The upstream `Shards > 1` assertions are excluded: Pulse counts exactly under
existing bounds, not with HyperLogLog or distributed sketch merging.

Four local HTTP/S3 controls cover raw string identity, missing/empty fields,
default/explicit/empty grouping, labels and parser values, arithmetic, instant/
range windows, nanosecond boundaries, offsets, GET/form POST, pre-storage invalid
queries and fail-whole budgets. Detached observations, including duplicates,
spend both selected-log and existing materialized-sample limits before window
deduplication; repeated window visits spend work. No new memory-byte ceiling,
high-cardinality acceleration, native/storage/keyed-byte change or retry drain.
Upgrade every query-serving application before relying on the syntax.

Combined Loki HTTP/WebSocket/module/LogQL/batch and Mimir/Tempo service regression:
**503 passed**, seed 104. The Loki service file contains 28 upstream-derived
checks and 21 local controls. Source pin, hashes, adaptations and baseline
failures are in its fixture README; no upstream cluster or deployed provider
was executed. This continuation remains local and uncommitted.

### Tempo default metric-step continuation

The fifteen original `TestDefaultQueryRangeStep` engine rows now run through
authenticated HTTP and persisted native Parquet with fresh manifest state.
Their window/expected-step table stays exact; an explicitly adapted one-span
fixture makes the chosen step visible in every response timestamp. These are
public engine-table ports, not additional upstream service-integration cases.

The unchanged-runtime baseline failed seven source rows plus the local minimum-
step control (seed 105). Omitted steps now use Tempo's 50 ms floor below one
minute and coarser window-dependent rounding otherwise. Explicit steps, instant
queries, interval admission and native/storage/keyed-byte contracts are unchanged.
Two local controls cover shifted-epoch and nanosecond/minute boundaries, explicit
700 ms spacing, instant ignored-step behavior and fail-whole interval admission.
Upgrade all query-serving applications for consistent defaults; no migration or
native ABI change. The targeted Tempo unit/HTTP/service replay passed **74**,
seed 106, including all **59 service-file wrappers**.

Broader Loki/Mimir/Tempo regression passed **510**, seed 107; the separate
batch suite passed **9**, seed 108. The seventeen additions passed eleven
consecutive fixed-seed runs (**187 executions**, seed 109). Strict compile,
Credo across 437 source files, scoped formatting and whitespace checks passed.
No native source changed or native unit tests reran. These are offline loopback
regressions, not upstream-server, provider or deployed-client acceptance.
Changes remain local and uncommitted.

### Mimir query-formatting continuation

The exact `TestFormatQueryAPIEndpoint` expression/result is now an offline
service regression. It failed before runtime changes (seed 111), echoing
`count(up)by(foo)` instead of `count by (foo) (up)`. The endpoint now formats
all supported PromQL AST nodes without executing queries or reading storage.
The Mimir service plus compatibility-controller replay passed **84 tests**,
seed 113. Source pin, source/selection hashes, attribution and adaptations are
recorded in the Mimir fixture README.

Local HTTP controls cover exact outputs, GET/form POST, idempotence, all 450
two-operator parenthesization combinations, UTF-8/control quoting, special metric
names versus scalar literals, finite float extremes/subnormals, offsets,
subqueries, vector matching and authentication. Input and output both retain
the 16 KiB ceiling; expansion beyond it fails whole instead of emitting a query
the parser cannot accept. Selector order is retained; comments/redundant
parentheses are not. This closes validation-only echo behavior, not upstream
multiline/matcher-sorting/redundant-syntax parity or unsupported PromQL grammar.
Upgrade query-serving applications; no native ABI, storage/keyed-byte change,
migration or retry drain is needed.

Validation: `mix precommit --max-cases 4 --seed 114 --warnings-as-errors`
passed **1854 tests**, with one existing optional skip and 37 opt-in exclusions
(268.0 seconds), including strict compile, unused-dependency and formatter
checks. A final three-service plus compatibility-controller replay passed
**192 tests**, seed 115. Strict Credo checked 438 files without findings. The green full run
still logged compaction timeouts/conflicts and manifest-CAS warnings; this
query-formatting change does not resolve those diagnostics or establish
provider/capacity acceptance. No native source changed or native unit tests
reran. The subsequent clean rebase onto `origin/main` passed the full precommit
suite again (**1854 passed**, seed 116), then the formatter increment was pushed
to `origin/main`. No deployment or migration ran.

### Loki counter-rate continuation

`rate_counter` is removed from the explicitly unsupported operator list. All
23 evaluations in the pinned Loki execution script's counter section are ported
into seven HTTP/S3 checks, retaining all six fixtures, noise lines, original
queries and complete expected results or rejection. The six successful-result
groups failed with `unsupported_rate_counter` before runtime edits (seed 117);
all seven groups passed after implementation (seed 118). Source pins, selection
hash, license and time-anchor adaptation are recorded in the Loki fixture README.

The evaluator compensates every chronological decrease, extrapolates using
sample-spacing and zero-point caps in the upstream order, supports offsets,
returns zero for one observation and no point for an empty window. Missing/empty
counter fields supply no sample; present malformed values fail evaluated windows.
Range grouping and missing unwrap still reject. Equal-time observations use
ascending canonical record keys, independent of arrival/numeric-value ordering;
Loki tie-order parity is unproven. The bounded Elixir fold preserves those keys;
the packed native metric path is deliberately not enabled for counters.

Two HTTP/S3 controls cover missing/empty versus malformed values, sparse-window
errors, pipeline errors and fail-whole scan/log-sample/work/result budgets.
Three controls run on both memory and native-capable adapters for exact
nanosecond and 1.1-spacing thresholds, equal-time ordering and IEEE/zero-elapsed
behavior. No native ABI, storage/keyed-byte, configuration, migration or
ingestion behavior changes. Upgrade query-serving applications before relying
on this operator. Other unwrap operators' missing-field behavior is addressed
in the continuation below; general Loki post-unwrap error filtering remains open.

Final `mix precommit --max-cases 4 --seed 121 --warnings-as-errors` passed
**1869 tests**, with one existing skip and 37 opt-in exclusions (301.5 seconds),
including Mimir/Loki/Tempo service replay. Strict Credo checked 438 files without
findings; formatting and whitespace checks passed. The first full run exposed
an alert-rule test's obsolete rejection of valid counters; it now verifies
acceptance with the disabled default and rejection without unwrap. No failing
check was ignored. Compaction/CAS warnings remain unresolved. The counter-rate
increment is local and uncommitted; no deployment or migration ran.

### Loki missing/empty unwrap-field continuation

Removed missing/empty-field skipping from the open-gap list for all supported
unwrap aggregations. Seventy-one real engine-script evaluations are ported into
four HTTP/S3 checks, preserving all source inputs/results: first/last windows,
offsets, gaps and NaN, plus grouped averages over logfmt, JSON and metadata.
All four groups failed before runtime changes (`sample_extraction_error`, seed
122), then passed after the fix (seed 123). Provenance and exact selections are
recorded in the Loki fixture README; upstream's Go suite was not launched.

Elixir and native scans omit missing/empty fields before series creation and
retained-sample admission, while scanning/pipeline work still charges. Present
malformed values and the existing conservative pipeline-error guard still fail.
Four local memory/native controls cover every ordinary unwrap operator,
all-missing/empty windows, malformed observations and sample/work boundaries;
conversion controls also include missing/empty fields. The independent reference
and randomized valid-query generators exercise the corrected contract. The
targeted LogQL/Loki HTTP replay passed 267 tests (seed 124).

Native log metric capability **4**, tuple `{1,1,4}`, fences old query semantics.
Upgrade all serving app/native pairs; no storage/keyed bytes, ingestion behavior,
resource ceilings or migration change. Full parser-error generation and
post-unwrap filtering remain unsupported, not silently treated as solved.

Full precommit passed **1877 tests**, one existing skip and 37 opt-in exclusions
(seed 125, 156.9 seconds), including all three service replays. All 133 native
codec tests, strict Clippy/Credo and formatter/whitespace checks passed; no
failure was ignored. Existing compaction/CAS warnings remain. This increment
and the counter-rate increment remain local and uncommitted; no deployment ran.

### Mimir three-argument clamp continuation

Removed `clamp(vector, min, max)` from the remaining PromQL function gaps.
Thirty-six verbatim public Mimir query-engine evaluations cover both clamp
families, changing/missing scalar bounds, NaN, infinities, equal/inverted bounds
and mixed float/histogram lifetimes. They add 114 HTTP checks on memory and
native S3/Parquet storage; the original 30 math evaluations remain unchanged.
Exact source ranges, extraction commands, hashes and licenses are recorded in
the fixture README. The upstream Go engine/service suite was not launched.

Scalar bounds evaluate at each step. Inverted intervals omit samples without
bypassing input admission; histograms are ignored, metric names removed and
duplicate-label errors preserved. Upper-bound-first evaluation retains signed
zeros. NaN semantics follow the pinned Mimir operator's built-in Go min/max,
including NaN/infinity combinations that differ from older Prometheus math
helpers. This does not claim cross-version equivalence on those edge cases.
There is no native ABI, stored/keyed byte, state, limit or configuration change;
upgrade every query-serving application before relying on the function.

Before implementation, four imported HTTP checks and three local checks failed
with unsupported-function errors (seed 126). All 48 focused tests then passed
(seed 127), including explicit signatures, exact special values, zero signs,
duplicate-label rejection and sample/work bounds even with inverted intervals.
A separate 729-combination Go 1.25.10 built-in oracle matched exactly, including
empty vectors and signed zeros. These are sampled local controls, not additional
upstream fixtures or deployed/provider/capacity proof.

Full precommit passed **1883 tests**, one existing skip and 37 opt-in exclusions
(seed 128, 128.5 seconds), including Mimir/Loki/Tempo ports. Strict Credo found no
issues across 438 files; fixture selections match upstream byte-for-byte.
No failing check was ignored. Existing compaction/CAS warnings remain. This
increment and the two preceding Loki increments remain local and uncommitted;
no push, deployment or migration ran.

### Mimir range-presence continuation

Removed `present_over_time(range)` from the remaining PromQL function gaps.
Twenty-two verbatim public Mimir query-engine evaluations cover absent/present
windows, NaN, explicit-resolution subqueries, mixed float/histogram lifetimes
and duplicate-label rejection. They add 84 HTTP checks on memory and native
S3/Parquet storage. Exact source ranges, extraction commands, hashes and licenses
are recorded in the fixture README. One upstream omitted-resolution subquery
was initially excluded and is now copied unchanged in the grammar batch below;
no selected input or expected output was adapted.

Presence returns one for any nonstale observation, including zero, nonfinite
floats and native histograms. Empty/stale-only windows omit output, not zero;
staleness does not erase prior valid samples inside the window. The existing
left-open/right-closed windowing, offsets, label-name removal/collision checks
and sample/work/result ceilings are preserved. No native ABI, stored/keyed
bytes, state, limits or configuration change; upgrade every query-serving
application before relying on the function.

The unchanged runtime failed seven added parser/HTTP wrappers with unsupported
syntax (seed 129). Final targeted replay passed **33 tests**, seed 131. Separate
Pulse memory/S3 controls cover scalar/custom-histogram staleness, a one-nanosecond
boundary distinction, offsets and histogram subqueries, zero/NaN/infinities,
mixed windows, aggregation, tenant isolation, form POST and independent
sample/work/result-budget rejection. These controls are not counted as imported
upstream cases or provider/client/capacity proof.

Full precommit passed **1890 tests**, one existing skip and 37 opt-in exclusions
(seed 132, 145.0 seconds), including the Mimir/Loki/Tempo ports. Strict Credo
checked 438 files without findings; formatting, whitespace and byte-for-byte
fixture provenance checks passed. No failing check was ignored. Existing
compaction/CAS warnings remain unresolved. This increment and the preceding
Loki/clamp changes remain local and uncommitted; no push, deployment or migration
ran.

### Mimir last-sample continuation

Removed `last_over_time(range)` from the remaining PromQL function gaps.
Four verbatim public Mimir query-engine evaluations add ten memory/S3 HTTP
checks. They preserve the full expected vectors/matrices, metric names,
float/histogram transitions, sparse/initially empty windows, bucket contents
and `expect no_info` assertion. Selected inputs/outputs are byte-for-byte
upstream; unused load rows are explicitly excluded. Source selections, hashes
and AGPL/Apache attribution are recorded in the fixture README.

The function returns the newest nonstale sample regardless of type, including
mixed float/native-histogram windows. It preserves metric names and other labels
and reports the evaluation timestamp. Stale markers do not hide earlier valid
observations still inside the range; empty/stale-only windows omit results.
Existing offsets, explicit-resolution subqueries, window bounds and query
ceilings apply. No new state, configuration, native ABI, stored format or keyed
bytes; upgrade every query-serving application before relying on the function.

The test adapter now checks typed histogram outputs, including independently
derived exponential bucket bounds, and merges float/histogram timestamp grids
without discarding either. Count/sum-only histogram sequences retain upstream
defaults; unsupported bucket-bearing histogram arithmetic fails explicitly.
Separate Pulse controls check exact custom-bucket outputs, descending values,
both mixed-type orders, name preservation across metrics, scalar/histogram
staleness, NaN/infinity/signed zero, nanosecond boundaries, offsets and histogram
subqueries, tenant isolation, GET/form POST and independent sample/work/result
budget rejection. They are not additional upstream cases or provider/client
capacity proof.

Before the runtime change, seven parser/HTTP wrappers failed on unsupported
syntax (seed 133). Targeted replay after the change passed **39 tests**, seed
134; all earlier imported math/clamp/presence cases remain in that run.

Full precommit passed **1896 tests**, with one existing skip and 37 opt-in
exclusions (seed 135, 110.7 seconds), including the Mimir/Loki/Tempo ports.
Strict Credo checked 438 files without findings; fixture byte identity,
formatting and whitespace checks passed. No failing check was ignored.
Existing compaction/CAS warnings remain unresolved. This increment and the
preceding local Loki/clamp/presence changes remain uncommitted; no push,
deployment or migration ran.

### Mimir first-sample continuation

Removed `first_over_time(range)` from the remaining PromQL function gaps.
One verbatim public Mimir query-engine evaluation adds four memory/S3 HTTP
checks with nine output series: floats, NaNs, native histograms, both mixed-type
orders and sparse/empty series. Metric names, full histogram outputs, split-load
ordering and `expect no_info` remain unchanged. The fixture README records the
exact source selection, extraction command, hash and original AGPL/Apache
attribution; replay requires no upstream executable or external service.

The function returns the earliest nonstale observation, preserving its type,
metric name and other labels. The evaluation step supplies the result timestamp.
Existing left-open/right-closed bounds, positive offsets, explicit-resolution
subqueries and sample/work/result ceilings apply. No new native artifact,
storage format, keyed bytes, state or configuration; upgrade every query-serving
application before relying on the function.

The unchanged runtime failed five parser/HTTP wrappers on unsupported syntax
(seed 136), without compiler warnings. Targeted replay after implementation
passed **43 tests**, seed 137, including the earlier math/clamp/presence/last
fixtures. Shared first/last controls distinguish chronological endpoints from
minimum/maximum, check moving-window expiry and stale scalar/histogram fallback,
and retain exact custom histogram outputs, nanosecond boundaries, subqueries,
tenant isolation, GET/form POST and independent query-budget rejection.
These are Pulse controls, not additional upstream cases or deployed-client,
provider or capacity proof.

Full precommit passed **1900 tests**, with one existing skip and 37 opt-in
exclusions (seed 138, 106.1 seconds), including the Mimir/Loki/Tempo ports.
Strict Credo checked 438 files without findings; fixture byte identity,
formatting and whitespace checks passed. No failing check was ignored.
Existing compaction/CAS warnings remain unresolved. This increment and the
preceding local Loki/clamp/presence/last-sample changes remain uncommitted;
no push, deployment or migration ran.

### Mimir source-timestamp continuation

Removed `ts_of_first_over_time(range)` and `ts_of_last_over_time(range)` from
the remaining PromQL function gaps. Fifteen verbatim public Mimir query-engine
evaluations add 60 memory/S3 HTTP requests, covering fractional-second load
intervals, empty ranges, pure histograms and both mixed-type endpoint orders.
Fixtures retain original inputs, expressions, expected values and licensing;
the fixture README records exact source ranges, extraction commands and hashes.

The functions select the earliest/newest nonstale observation and return its
source time as float seconds, dropping only the metric name. Epoch-zero source
times remain valid and output points use the evaluation step. Positive offsets
move the window, not the returned time; explicit-resolution subqueries return
their inner-grid timestamps. Existing window boundaries, staleness handling,
duplicate-label rejection and query ceilings remain in force. No new state,
configuration, native artifact, stored format or keyed bytes; upgrade every
query-serving application before using these functions.

Replay now parses compound millisecond load intervals into integer nanoseconds
before index multiplication, independently of the production duration parser.
Indented DSL comments, including `#empty`, become empty expectations that still
require an empty result. Unsupported commands/values remain failures rather
than skipped assertions. This does not claim timestamp precision parity beyond
upstream's millisecond storage or deployed-client/provider/capacity acceptance.

Before implementation, nine parser/HTTP wrappers failed on unsupported syntax
(seed 139). Final targeted replay passed **51 tests**, seed 141. Independent
Pulse controls verify exact fractional timestamp strings, epoch zero, scalar/
histogram staleness, nonfinite values, both mixed-type orders, metric-name
removal/collisions, moving-window expiry, nanosecond boundaries, offsets and
subquery grids, GET/form POST, tenant isolation and separate sample/work/result
budget rejection. Earlier imported math/clamp/presence/first/last cases remain
in that run.

Full precommit passed **1908 tests**, with one existing skip and 37 opt-in
exclusions (seed 142, 128.5 seconds), including the Mimir/Loki/Tempo ports.
Strict Credo checked 438 files without findings; exact-byte fixture provenance,
formatting and whitespace checks passed. No failing check was ignored.
Existing compaction/CAS warnings remain unresolved. This increment and the
preceding local protocol changes remain uncommitted; no push, deployment or
migration ran.

### Mimir transition-count continuation

Removed ordinary `changes(range)` and `resets(range)` from the remaining
PromQL function gaps. Twenty-one verbatim public Mimir query-engine evaluations
add 82 memory/S3 HTTP requests. This includes the complete sixteen-series
Mimir range case with exponential/custom histograms, bucket/count/schema resets,
sum-only changes, type transitions and nonfinite floats. The fixture README
records exact source ranges, extraction commands, hashes and licensing.

Both functions compare consecutive nonstale observations in timestamp order,
including mixed float/histogram windows. Float changes treat consecutive NaNs
and signed zeros as equal; float resets count decreases, never NaN comparisons.
Histogram changes reuse complete histogram equality, ignoring reset hints;
histogram resets reuse the existing count/bucket/schema/zero-threshold/custom-bound
and reset-hint detection. Every type transition counts for both. A single valid
sample returns zero; empty/stale-only windows omit output. Metric names drop,
other labels survive, and duplicate labels fail whole. Offsets, subquery grids
and existing sample/window-work/result ceilings remain; there is no new
per-histogram-bucket work meter or capacity claim.

The upstream parenthesized `changes((http_requests[50m]))` exposed a parser gap.
Range arguments now accept bounded parentheses through the generic-call path,
without enabling range arithmetic or top-level range results. The unitless
`[600]` evaluation at upstream lines 23–27 is explicitly excluded, not rewritten;
parser controls still require it and `anchored` modifiers to reject. Histogram
fixture parsing now faithfully maps zero threshold/count and custom bounds;
unknown fields continue to fail rather than disappear.

Before implementation, nine parser/HTTP wrappers failed on unsupported syntax
(seed 143). Targeted replay passed **59 tests**, seed 145, including the prior
math/clamp/presence/endpoint corpus. Separate Pulse controls check interleaved
types, NaN/infinity/signed zero, sum-only histogram changes, reset hints,
histogram signed-zero equality, stale bridges, single/empty windows, nanosecond
boundaries, offsets, explicit subquery grids, name removal/collisions,
GET/form POST, tenant isolation and separate sample/work/result-budget rejection.
No native artifact, storage format, keyed-ingest bytes, configuration or durable
state changed; upgrade every query-serving application before use.

Full precommit passed **1916 tests**, with one existing skip and 37 opt-in
exclusions (seed 146, 114.0 seconds), including the Mimir/Loki/Tempo ports.
Strict Credo checked 438 files without findings. Fixture byte identity, counts,
formatting and whitespace checks passed; no failing check was ignored.
Existing compaction/CAS warnings remain unresolved. This increment and the
preceding local protocol changes remain uncommitted; no push, deployment or
migration ran.

### Mimir least-squares gauge continuation

Removed ordinary `deriv(range)` from the remaining PromQL function gaps.
Twelve verbatim public Mimir evaluations add 46 memory/S3 HTTP requests:
seven direct derivative evaluations, three numeric-horizon predictions, one
rate control and one prediction/derivative identity. The complete sixteen-series
Mimir range case retains sparse/mixed float-histogram input, nonfinite values
and every info/no-warning assertion. Fixtures preserve load rows, expressions,
expected values and directives; source ranges, hashes and exclusions are recorded
in the fixture README. Duration-valued scalar horizons and `@` modifiers remain
unsupported and are excluded, never rewritten to produce a pass.

The new function returns the compensated least-squares gauge slope per second,
using source times relative to the first float sample, with no counter reset
correction or extrapolation. It needs two nonstale floats; finite constants
return positive zero, nonfinite observations return NaN, pure histogram windows
omit output, and mixed windows ignore histograms. Existing metric-name removal,
label collision rejection, window bounds, offsets, explicit subquery grids and
sample/work/result ceilings remain. No native artifact, storage format, keyed
bytes, configuration or durable state changed; upgrade every query-serving app.

Mixed windows now carry a query-local `infos` diagnostic for both `deriv` and
the existing `predict_linear`, including windows with insufficient floats for
a value. Notices are emitted only from evaluated nonstale windows, deduplicated
across steps/expressions and reset between batch sources. Their text omits
upstream metric names and source positions, so exact annotation text/counts and
the complete annotation taxonomy remain gaps. The replay checks all selected
leading info/no-info/no-warning directives instead of treating them as samples
or silently discarding them.

Before implementation, seven parser/HTTP wrappers failed on unsupported syntax
(seed 147). The shared regression calculation was first extracted without
changing prediction results: 9180 direct old/new prediction comparisons were
byte-identical across finite/nonfinite/constant/random inputs and large epochs,
and 29 existing oracle/semantic tests passed (seed 148). Final targeted replay,
parser, oracle and batch tests passed **81 tests** (seed 150). Separate Pulse
controls use asymmetric irregularly timed values to distinguish least-squares
slopes from endpoint/sample-index/reset-aware calculations, and cover huge
finite constants, zero sign, stale bridges, large epochs, nanosecond boundaries,
offsets, mixed subqueries, sparse-window notice absence, insufficient-float
notices, GET/form POST, name collisions, tenant isolation, independent budgets
and batch-source notice isolation. These are not extra upstream cases or
deployed-client/provider/capacity acceptance.

Final `mix precommit --max-cases 4 --seed 152 --warnings-as-errors` passed:
**1922 passed, 1 skipped, 37 excluded**. Strict Credo found no issues after
separating response annotation assembly, mixed-window diagnostics and fixture
annotation assertions into their owning helpers. Fixture selections remain
byte-identical to the pinned Mimir source. This increment and the preceding
local continuations remain uncommitted and unpushed; no deployment or migration
ran.

### Mimir median absolute deviation continuation

Removed ordinary `mad_over_time(range)` from the remaining PromQL function gaps.
Fourteen byte-identical Mimir query-engine evaluations add 56 memory/S3 HTTP
requests, covering sparse data, even/odd and constant windows, NaN propagation,
single samples, histogram-only omission and mixed-window info annotations. The
complete upstream block and seven Mimir-specific evaluations retain their input
rows, expressions and expected values. At this increment, Mimir lines 1529–1532
were excluded because their diagnostic regex required metric-name context;
the extremum-timestamp continuation below closes that exclusion without
weakening the assertion. Full annotation parity remains a gap.

The function computes median(abs(value - median(values))) over nonstale floats,
without a scale factor or mean-based substitution. Half-weighted even medians
avoid premature finite overflow; NaN inputs propagate, infinity subtraction and
NaN deviations retain IEEE semantics, and finite singletons yield positive zero.
It removes the metric name, preserves other labels, rejects resulting collisions
and applies existing window bounds, offsets, explicit subquery grids and
sample/result limits. Both sorts reserve conservative logarithmic work before
allocation, in addition to the scan, sharing the query ceiling across windows
and batch sources. Mixed windows reuse bounded query-local infos; histogram-only,
stale-only and unevaluated intermediate histograms do not create notices.
No native artifact, storage format, keyed bytes, configuration or durable state
changed. Upgrade every query-serving app; upstream experimental-function flags
and full protocol/deployed-client/provider/capacity acceptance are not claimed.

Before implementation, seven parser/HTTP wrappers failed on unsupported syntax
(seed 153). Targeted parser, HTTP replay, numerical oracle, semantics and batch
tests passed **100 tests** (seed 154). Separately labelled controls distinguish
median from mean/scaled deviations with asymmetric values, and cover infinities,
huge finite midpoints, overflowing individual differences, zero sign, stale
bridges, single-float mixed windows, nanosecond boundaries, offsets, float/mixed
subqueries, sparse evaluated windows, GET/form POST, collisions, tenant and batch
notice isolation. Sort-sensitive work rejection/admission and cumulative batch
work prevent a linear-only accounting regression. These are not extra upstream
evaluations.

Full `mix precommit --max-cases 4 --seed 155 --warnings-as-errors` passed:
**1928 passed, 1 skipped, 37 excluded** in 119.5 seconds, including the selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings. Fixture
byte identity, counts, formatting and whitespace checks passed; no failing check
was ignored. Compaction/CAS warnings remain unresolved. This increment and the
preceding local continuations remain uncommitted and unpushed; no deployment or
migration ran.

### Mimir extremum source timestamps continuation

Removed ordinary `ts_of_min_over_time(range)` and `ts_of_max_over_time(range)`
from the remaining PromQL function gaps. Ten byte-identical Mimir engine cases
add 40 memory/S3 instant/range HTTP requests, retaining every input, query,
expected value and leading/trailing annotation directive. The odd scrape
interval checks fractional source times; mixed rows distinguish float selection
and newest equal extrema from histogram or earliest-tie selection.

Both functions select nonstale floats in chronological order, replacing on
equal extrema. A NaN best is replaceable, but later NaNs cannot displace a
non-NaN observation; all-NaN windows therefore select the latest float. Equal
signed zeros tie. Histograms are ignored with mixed-window infos; histogram-only,
empty and stale-only windows silently omit output. Returned values are source
seconds; result timestamps remain evaluation times. Metric names are removed,
remaining labels survive, and collisions reject. Existing window bounds,
offsets, explicit subquery grids and sample/work/result ceilings apply.

Mixed-window diagnostics now include the original metric name, JSON-quoted,
and deduplicate by name within each query. Name-removing subqueries use the
effective empty name. This also restores the previously excluded MAD case
unchanged, adding four more HTTP requests. Regex directives are validated in
both directions, including directives after sample rows. Expression-position,
arbitrary-name Go quoting and complete annotation-taxonomy parity remain open.
No native artifact, storage format, keyed bytes, configuration or durable state
changed; upgrade every query-serving app.

Before implementation, eleven parser/HTTP wrappers failed on unsupported syntax
or the upstream diagnostic regex (seed 157). Final parser, HTTP replay, numerical
oracle, semantics and batch checks passed **117 tests** (seed 159). Separate
Pulse controls cover finite/nonfinite/tied extrema, single-float mixed windows,
staleness, epoch zero, exact nanosecond results, moving-window expiry, one-nanosecond
bounds, offsets, subquery source grids, per-metric/nameless infos, sparse-window
notice absence, GET/form POST, name collisions, tenant isolation and independent
sample/work/result-budget rejection. These are not extra upstream cases or
deployed-client/provider/capacity acceptance.

Full `mix precommit --max-cases 4 --seed 160 --warnings-as-errors` passed:
**1936 passed, 1 skipped, 37 excluded** in 220.5 seconds, including the selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings. All three
new/expanded fixture selections match the pinned source byte for byte; the corpus
contains 166 evaluations and 614 memory/S3 HTTP requests. No failing check was
ignored. Compaction/CAS warnings remain unresolved. This increment and preceding
local continuations remain uncommitted and unpushed; no deployment or migration
ran.

### Mimir label joining continuation

Removed `label_join(vector, destination, separator, source...)` from the remaining
PromQL function gaps. Twenty-two byte-identical public Mimir engine evaluations
add 78 memory/S3 instant/range HTTP requests. The full Mimir-specific block and
selected upstream basic/disjoint/overlapping-series cases preserve their input
labels, floats, complete histograms, queries and assertions. The adapter accepts
quoted expected label keys rather than rewriting UTF-8 fixtures. Four invalid-name
diagnostics explicitly map to Pulse's parse-time HTTP 400, and duplicate-label
errors to its exact HTTP 422; upstream error-message/status parity is not claimed.

Joining uses source values in argument order, including repeats and missing
values as empty strings. All reads precede the destination update, even when it
is a source. Empty joined values and zero-source calls remove the destination.
Nonempty UTF-8 names accept punctuation and Unicode; empty/invalid-UTF-8 names
reject before storage. Samples, timestamps and names otherwise survive unchanged;
`__name__` destinations can create, replace or remove the name. Disjoint evaluation
times can coalesce under one result identity; coincident label collisions reject
whole. Delayed name removal remains unsupported, including the two unchanged
Mimir deliberate-failure cases.

Each source lookup and joined UTF-8 byte, including repeated values/separators,
spends the existing work budget before binary construction. No separate limit,
native artifact, storage format, keyed bytes, configuration or durable state
was introduced. Query and batch work remain cumulative; existing sample/result
and heap ceilings apply. Upgrade every query-serving app.

Before implementation, nine parser/HTTP wrappers failed on unsupported syntax
(seed 161). Final parser, HTTP replay, oracle, semantics and batch checks passed
**126 tests** (seed 162). Separate Pulse controls distinguish original from
incrementally overwritten sources, preserve complete histograms/NaN/zero sign,
exercise actual Unicode names/values/separators, name deletion, staleness,
GET/form POST and tenant isolation. Sample/work/result rejection, repeated-source
and separator byte accounting, empty-valued lookup cost and cumulative batch
work have admission/rejection controls. These are not extra upstream cases or
deployed-client/provider/capacity acceptance.

Full `mix precommit --max-cases 4 --seed 163 --warnings-as-errors` passed:
**1945 passed, 1 skipped, 37 excluded** in 325.3 seconds, including the selected
Mimir/Loki/Tempo ports. After flattening fixture-reader nesting for lint, all
**70 HTTP conformance tests** passed again (seed 164). Strict Credo checked 438
files without findings; formatting and diff checks passed. Both new fixtures
match the pinned source byte for byte; the corpus contains 188 evaluations and
692 memory/S3 HTTP requests. No failing check was ignored. Compaction/CAS warnings
remain unresolved. This increment and preceding local continuations remain
uncommitted and unpushed; no deployment or migration ran.

### Mimir range quantile continuation

Removed PromQL `quantile_over_time(q, range)` from the remaining function gaps.
Fifteen byte-identical public Mimir/Prometheus engine evaluations add 58 memory/S3
instant/range HTTP requests. Both contiguous quantile sections preserve all load
blocks, expected values and annotation directives, including invalid-quantile
warnings and changing scalar parameters. `expect warn` is now asserted rather
than dropped; the runtime is independently implemented, not copied from Mimir.

The function weights every nonstale float equally, sorts NaNs before other
values and interpolates at rank `q * (n - 1)`. Exact ranks read one observation
without contaminating it through zero-weight adjacent NaN/infinity arithmetic.
Weighted endpoint terms avoid the overflowing endpoint-difference formula.
NaN, below-zero and above-one quantiles yield NaN/-Inf/+Inf plus query-local
warnings only when floats are present. Warnings survive nested expressions,
deduplicate within each source and reset across batch sources. Mixed histograms
are ignored with the existing metric-named info; histogram-only and empty/stale
windows omit output. Names drop and coincident result identities fail whole.

Quantiles evaluate at outer query steps even when positive range/subquery offsets
shift the observations. Existing left-open/right-closed windows, epoch-aligned
explicit subquery grids and sample/work/result/heap ceilings remain. Each
nonempty float window reserves conservative logarithmic sorting work before
value-list allocation, including invalid quantiles; batch work is cumulative.
No new native artifact, storage format, keyed bytes, durable state or configurable
ceiling was introduced. Upgrade every query-serving app. Exact expression-position
and arbitrary-number diagnostic formatting parity remain open.

Before implementation, nine parser/HTTP wrappers failed on unsupported syntax
(seed 165). Parser, HTTP replay, numerical oracle, semantics and batch checks
passed **135 tests** (seed 167). Separate controls cover NaN ordering versus
unconditional propagation, finite exact ranks next to infinities, weighted huge
endpoints, negative zero, unsorted input, mixed/stale histograms, nanosecond
boundaries, moving-window expiry, scalar/offset/subquery alignment, form POST,
tenant isolation, name collisions, annotation isolation and independent budget
rejection. Sorting-specific and cumulative-batch controls include admitted
queries as well as rejected ones. These are not extra upstream evaluations or
deployed-client/provider/capacity acceptance.

Full `mix precommit --max-cases 4 --seed 168 --warnings-as-errors` passed:
**1954 passed, 1 skipped, 37 excluded** in 290.9 seconds, including the selected
Mimir/Loki/Tempo ports and the additional offset-subquery control. Strict Credo
checked 438 files without findings; formatting and whitespace checks passed.
Both new fixture selections match the pinned upstream bytes and recorded hashes;
the complete corpus contains 203 evaluations and 750 memory/S3 HTTP requests.
No failing check was ignored. Compaction timeout/conflict and manifest CAS
warnings remain unresolved. This increment and preceding local continuations
remain uncommitted and unpushed; no deployment or migration ran.

### Mimir double exponential smoothing continuation

Removed `double_exponential_smoothing(range, sf, tf)` and the legacy
`holt_winters` alias from the remaining PromQL function gaps. Ten unchanged
public Mimir/Prometheus engine evaluations add 32 memory/S3 instant/range HTTP
requests. Complete contiguous source sections retain positive/negative trends,
moving windows, changing scalar factors, IEEE values, histogram annotations and
both invalid-factor diagnostics. The runtime recurrence is independently written;
no Mimir implementation is copied.

Initial level is the first float and initial trend is the second minus the first.
Subsequent level/trend updates preserve upstream operation order and IEEE
arithmetic, including overflow instead of algebraic simplification. Two nonstale
floats are required. Factors evaluate at outer query steps, not offset observation
times; strict zero/one bounds and infinities fail whole on any nonempty window,
including single-float and histogram-only windows. Empty/stale windows omit
before validation. NaN factors pass IEEE comparisons; a NaN trend factor does
not poison a two-float result because the initialized trend is used directly.
Mixed histograms produce metric-named infos even with insufficient floats.
Names drop, collisions fail and existing sample/work/result/heap limits apply
across selectors, windows and batches. No native/storage/keyed-byte change or
new configuration ceiling is introduced. Upgrade every query-serving app;
experimental feature flags and expression-position annotations remain unmatched.

The fixture adapter now supports negative scalar ramps and repeated addition,
matching the pinned Prometheus producer grammar. Index multiplication would
incorrectly round the final `0.1+0.1x9` factor to exactly one. Existing fixture
inputs and expectations remain verbatim. Both imported invalid-factor messages
are asserted exactly as HTTP 422 execution errors; these engine fixtures do
not establish upstream HTTP status parity.

Before implementation, five parser/HTTP wrappers failed on unsupported syntax
(seed 169). All imported fixtures then passed (102 parser/HTTP tests, seed 170).
Parser, HTTP replay, numerical oracle, semantics and batch checks passed
**144 tests** (seed 171). A large finite-factor HTTP control then exposed a
fixed-decimal formatter buffer limit on both storage paths; it failed before
the formatting correction (seed 173) and passed after it (seed 174). Arbitrary
finite diagnostic formatting still does not claim byte parity with Go.
Additional controls distinguish asymmetric recurrence from last-sample/average/
regression substitutions and check nonfinite/overflow/zero behavior, staleness,
histogram-only factor validation, nanosecond boundaries, moving expiry,
outer-time factors with range/subquery offsets, form POST, tenant isolation,
collisions and independent/cumulative budget rejection.

Final `mix precommit --max-cases 4 --seed 175 --warnings-as-errors` passed:
**1963 passed, 1 skipped, 37 excluded** in 355.2 seconds, including the large-factor
regression and selected Mimir/Loki/Tempo ports. Strict Credo checked 438 files
without findings; formatting and whitespace checks passed. Both new fixtures
match the pinned upstream bytes, all documented local fixture hashes match,
and the corpus contains 213 evaluations/782 memory/S3 HTTP requests. No failing
check was ignored. Compaction timeout/conflict, manifest CAS and loopback
acceptor-teardown diagnostics remain unresolved; this is not provider, deployed
client or capacity acceptance. This increment and previous local continuations
remain uncommitted and unpushed; no deployment or migration ran.

### Mimir angular conversion and scalar pi continuation

Removed `deg(vector)`, `rad(vector)` and scalar `pi()` from the remaining
PromQL function gaps. Twelve verbatim public Mimir/Prometheus engine evaluations
add 46 memory/S3 instant/range HTTP requests. The selected complete angular
sections preserve positive/negative/NaN conversions, nested arithmetic, large
finite values, constant scalar/matrix results and metric-name collisions.
The fixture adapter now asserts scalar instant envelopes without rewriting
upstream expected values, then replays them as empty-label one-step matrices.
Source selections, license/provenance and SHA-256 hashes are recorded beside
the fixtures. No upstream runtime implementation is copied.

Both converters use one multiplication by a pre-rounded constant, matching
the pinned engines rather than multiplying and dividing at runtime. This avoids
intermediate overflow for `rad(vector(1e308))` and `deg(vector(1e306))`, while
actual overflow returns signed infinity. Float signed zero, subnormal results,
underflow and NaN/infinity survive; native histograms are silently omitted and
stale markers hide earlier values. Metric names drop, other labels survive and
duplicate result identities reject whole. `pi()` has zero-argument scalar typing
and emits the same value at each outer step. Scalar/vector composition, positive
selector/subquery offsets and existing sample/work/result limits remain.
Constant-only queries read no stored samples but still spend result points,
including cumulative batch results. No native/storage/keyed-byte change or new
configuration/state is introduced; upgrade every query-serving application.
Other trigonometric functions and full language/annotation parity remain open.

Before implementation, six parser/HTTP wrappers failed on unsupported syntax
(seed 176). All imported cases then passed with parser, numerical oracle,
semantics and batch checks (**149 tests**, seed 177). Exact local IEEE controls
and scalar/composition/budget checks passed with the same suites (**155 tests**,
seed 178). Finite expected bits were independently checked using Go 1.25.10
standard-library constant expressions on arm64; permanent Elixir replays need
no Go executable or network. These are scoped semantic checks, not full upstream
service-suite, provider, deployed-client or capacity acceptance.

Final `mix precommit --max-cases 4 --seed 180 --warnings-as-errors` passed:
**1974 passed, 1 skipped, 37 excluded** in 113.6 seconds, including selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings after
the scalar-envelope assertions were separated from error/annotation handling.
Formatting and whitespace checks passed. Both angular fixtures exactly match
the pinned source selections, all 25 recorded local fixture hashes match, and
the corpus contains 225 evaluations/828 memory/S3 HTTP requests. Compaction/CAS
diagnostics still appear; no failing check was ignored. This increment and
previous local continuations remain uncommitted and unpushed; no deployment or
migration ran.

### Mimir inverse trigonometric continuation

Removed `asin(vector)`, `acos(vector)` and `atan(vector)` from the remaining
PromQL function gaps. Eight verbatim public Mimir/Prometheus engine evaluations
add 28 memory/S3 HTTP requests: the complete upstream inverse-circular section,
both Mimir inverse-circular range sections and all three corresponding
metric-name collision cases. Sources, extraction ranges, licenses and hashes
are recorded beside the fixtures; no upstream runtime implementation or test
runner is copied.

`asin`/`acos` accept the closed interval [-1, 1], with out-of-domain and
infinite samples returning NaN rather than aborting the response. `atan`
accepts every finite value and maps infinities to signed pi/2. All three
propagate NaN, omit native histograms, remove metric names and preserve other
labels; duplicate output identities reject whole. Signed zero and subnormal
`asin`/`atan` results survive. Finite math uses the platform library, not a
ported Go polynomial; cross-platform bit identity is not promised. Existing
selector/subquery offsets and sample/work/result/batch ceilings remain.
No native artifact, storage/keyed bytes, configuration, migration or durable
state change is needed; upgrade every query-serving application. Direct
trigonometric and hyperbolic functions remain open.

Before implementation, five parser/HTTP wrappers failed on unsupported syntax
(seed 181). With the implementation, parser, HTTP replay, numerical oracle,
semantics and batch checks passed **159 tests** (seed 182). Added boundary/IEEE
controls and extended composition/budget checks passed **161 tests** (seed 183).
Independent Go 1.25.10 math results cover both endpoints and their immediate
binary64 neighbors, asymmetric inputs, signed zero, smallest subnormals,
NaN/infinities and huge finite saturation. NaN classifications and tiny signed
values are exact; other selected finite values allow one ULP. Memory/S3 checks
also assert histogram/stale omission, labels/types/timestamps, tenant isolation,
form POST, angular/scalar composition, positive selector/subquery offsets and
independent/cumulative limits. Permanent tests need no Go or network. These
are scoped semantic checks, not full upstream service-suite, provider,
deployed-client or capacity acceptance.

Final `mix precommit --max-cases 4 --seed 184 --warnings-as-errors` passed:
**1980 passed, 1 skipped, 37 excluded** in 101.9 seconds, including selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings;
formatting and whitespace checks passed. Both new fixtures exactly match the
pinned source selections, all 27 recorded local hashes match, and the corpus
contains 233 evaluations/856 memory/S3 HTTP requests. Compaction/CAS diagnostics
still appear; no failing check was ignored. This increment and earlier local
continuations remain uncommitted and unpushed; no deployment or migration ran.

### Mimir circular trigonometric continuation

Removed `sin(vector)`, `cos(vector)` and `tan(vector)` from the remaining
PromQL function gaps. Six verbatim public Mimir/Prometheus engine evaluations
add 24 memory/S3 HTTP requests: the complete upstream circular section and all
three corresponding metric-name collisions. Extraction ranges, source pin,
licenses and SHA-256 hashes are recorded beside the fixtures. No upstream
runtime implementation or runner is copied.

All three consume radian inputs, propagate NaN and map either infinity to a
per-sample NaN instead of failing whole. Native histograms are silently omitted,
metric names removed, other labels preserved, and duplicate output identities
reject whole. Finite values use platform math without modulo reduction or pole/
near-zero clamping. Signed zero and smallest subnormals survive `sin`/`tan`.
No native artifact, storage/keyed bytes, configuration, migration or durable
state change is needed; upgrade all query-serving applications. Hyperbolic
functions and full language/annotation/bit-identical precision parity remain open.

Before implementation, five parser/HTTP wrappers failed on unsupported syntax
(seed 185). Parser, HTTP replay, numerical oracle and semantics checks then
passed **158 tests** (seed 186). Independent Go 1.25.10 standard-library probes
cover signed zero, smallest subnormals, asymmetric quadrants, π, the binary64
value nearest π/2 and both immediate neighbors, large angles and the largest
finite input. These selected platform results differ by up to 26 ULP; local
controls require `1e-14` relative accuracy, tighter than the upstream replay's
`1e-6`, with exact tiny values/zero signs and NaN classifications. This is not
a global precision guarantee or cross-platform bit identity. Memory/S3 controls
also cover histogram/stale omission, labels/types/timestamps, form POST, tenant
isolation, changing range inputs, angular composition, selector/subquery offsets
and independent/cumulative budgets. Permanent tests require no Go or downloads;
these are scoped semantic checks, not provider/deployed-client/capacity acceptance.

Final `mix precommit --max-cases 4 --seed 188 --warnings-as-errors` passed:
**1986 passed, 1 skipped, 37 excluded** in 108.2 seconds, including selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings; formatting
and whitespace checks passed. Both new fixtures exactly match pinned selections,
all 29 recorded local hashes match, and the corpus contains 239 evaluations/
880 memory/S3 HTTP requests. Compaction/CAS fault-path diagnostics still appear;
no failing check was ignored. This increment and earlier local continuations
remain uncommitted and unpushed; no deployment or migration ran.

### Mimir hyperbolic continuation

Removed `sinh(vector)`, `cosh(vector)` and `tanh(vector)` from the remaining
PromQL function gaps. Six verbatim public Mimir/Prometheus evaluations add
24 memory/S3 HTTP requests: the complete upstream hyperbolic section and all
three corresponding metric-name collision cases. Extraction ranges, source pin,
licenses and SHA-256 hashes are recorded beside the fixtures. The approximate
upstream `sinh(10)` expectation stays unchanged; stricter local controls use an
independent Go result. No upstream runtime or test runner is copied.

All three propagate NaN, silently omit native histograms, remove metric names
and preserve other labels; duplicate output identities reject whole. `sinh`
preserves infinity signs, `cosh` maps either infinity to positive infinity,
and `tanh` maps them to ±1. Signed zeros and smallest subnormals survive `sinh`
and `tanh`; `cosh(±0)` is one. For magnitudes above 21, `sinh`/`cosh` reuse the
existing Go-compatible exponential path before halving, preserving its earlier
overflow at magnitudes above 709.782712893384, not platform finite values at
710. Overflow returns the appropriate infinity instead of query failure.
Other finite math uses the platform library, without a global bit-identity
guarantee. No native artifact, storage/keyed bytes, configuration, migration or
durable state change is needed; upgrade all query-serving applications. Full
language/annotation parity remains open; inverse hyperbolic functions are covered below.

Before implementation, five parser/HTTP wrappers failed on unsupported syntax
(seed 189). Parser, HTTP replay, numerical oracle, semantics and batch checks
then passed **173 tests** (seed 190). Independent Go 1.25.10 arm64 probes cover
signed zero, smallest subnormals, asymmetric inputs, immediate neighbors around
21 and the exponential overflow boundary, signed overflow, largest finite
inputs, NaN/infinities and tangent saturation. Classes, tiny signed values and
saturation are exact; other selected finite values allow one ULP. Memory/S3
checks also cover histogram/stale omission, labels/types/timestamps, form POST,
tenant isolation, changing range inputs, scalar composition, selector/subquery
offsets and independent/cumulative budgets. Permanent tests need no Go or
downloads; these are not provider, deployed-client, capacity or global precision
acceptance.

Final `mix precommit --max-cases 4 --seed 191 --warnings-as-errors` passed:
**1992 passed, 1 skipped, 37 excluded** in 271.2 seconds, including selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings;
formatting and whitespace checks passed. Both new fixtures match pinned source
selections byte-for-byte, all 31 recorded local hashes match, and the corpus
contains 245 evaluations/904 memory/S3 HTTP requests. Existing compaction
fault-path diagnostics still appear; no failing check was ignored. This
increment and earlier local continuations remain uncommitted and unpushed;
no deployment or migration ran.

### Mimir inverse hyperbolic continuation

Removed `asinh(vector)`, `acosh(vector)` and `atanh(vector)` from the remaining
PromQL function gaps. Seven verbatim public Mimir/Prometheus evaluations add
26 memory/S3 HTTP requests: the complete upstream inverse-hyperbolic section,
Mimir's changing-range `atanh` case and all three metric-name collisions.
Extraction ranges, source pin, licenses and SHA-256 hashes are recorded beside
the fixtures. No upstream runtime implementation or runner is copied.

All three propagate NaN, silently omit native histograms, remove metric names
and preserve other labels; duplicate output identities reject whole. `asinh`
preserves signed infinities. `acosh` accepts inputs at least 1, with positive
zero at 1 and positive infinity at `+Inf`. `atanh` returns signed infinities at
±1 and NaN beyond them; other invalid `acosh` inputs also yield per-sample NaN,
not query failure. Signed zeros and smallest subnormals survive `asinh`/`atanh`;
largest finite inputs remain finite for `asinh` and valid `acosh`. Runtime uses
platform inverse-hyperbolic math with explicit domain/nonfinite handling,
without a global or cross-platform bit-identity guarantee. No native artifact,
storage/keyed bytes, configuration, migration or durable state changes; upgrade
all query-serving applications. Full language/annotation parity remains open.

Before implementation, five parser/HTTP wrappers failed on unsupported syntax
(seed 192); 134 other tests passed. Targeted parser, HTTP, semantics and batch
checks passed **172 tests**, and the independent numerical oracle passed
**7 tests** (seed 193). Independent Go 1.25.10 arm64 expectations distinguish
both sides of ±1, signed zero, smallest subnormals, asymmetric signed inputs,
immediate neighbors of 2**28, ±1e308, largest finite values and NaN/infinities.
Classes and tiny signed values are exact; other selected finite values allow
one ULP. Memory/S3 controls also check histogram/stale omission, labels/types/
timestamps, form POST, tenant isolation, changing range inputs, nested
composition, selector/subquery offsets and independent/cumulative budgets.
Permanent tests require no Go or downloads. These are not provider, capacity,
deployed-client or global precision acceptance.

Final `mix precommit --max-cases 4 --seed 194 --warnings-as-errors` passed:
**1998 passed, 1 skipped, 37 excluded** in 210.3 seconds, including the selected
Mimir/Loki/Tempo ports. Strict Credo checked 438 files without findings;
formatting and whitespace checks passed. Both new fixtures match their pinned
source selections byte-for-byte, all 33 recorded local hashes match, and the
corpus contains 252 evaluations/930 memory/S3 HTTP requests. Test-store teardown
and compaction fault-path diagnostics still appear; no failing check was
ignored. This increment and earlier local continuations remain uncommitted and
unpushed; no deployment or migration ran.

### Batched calendar, label sorting and quadrant arithmetic

Removed eleven features from the remaining PromQL function/operator gaps in
one batch: `year`, `month`, `day_of_month`, `day_of_week`, `day_of_year`,
`days_in_month`, `hour`, `minute`, `sort_by_label`, `sort_by_label_desc` and
binary `atan2`. Seven verbatim fixture selections add **126 evaluations**
(70 instant, 56 range), replayed as **392 HTTP requests** across isolated memory
and S3/Parquet adapters. Existing arithmetic controls remain in the selected
blocks rather than stripping expectations unrelated to the new operator.
The complete math corpus now has 43 files, 378 evaluations and 1322 requests
across 86 fixture wrappers; this is selected engine coverage, not Mimir's
Docker/service suite. Exact ranges, licenses and hashes live in the
[fixture provenance](../test/fixtures/promql/mimir/README.md).

Calendar fields use the value's truncated Unix seconds and default to each
evaluation step, retaining UTC leap-century semantics beyond DateTime's year
bounds. Exceptional inputs deliberately freeze Go 1.25 arm64 float-to-int64
conversion and its unsigned absolute-time wrap, not cross-architecture Go
behavior. Histograms omit silently and name-removal collisions still reject.
Label sorts retain complete float/histogram samples and names, compare requested
ASCII numeric chunks with int64 overflow fallback, then use full lexical labels
for identical requested strings; descending reverses that tie-break too.
The pinned comparator's unequal leading-zero/empty-value ambiguities do not
establish a portable total order. Comparisons charge lookup/label bytes against
the existing work limit. Range sorts bypass sorting, with deduplicated warnings
when start/end differ, even on empty inputs. Experimental flags and expression
positions remain unimplemented.

`atan2` shares multiplication precedence, left associativity and ordinary vector
matching. Scalar/vector and group-right paths preserve authored ordinate/abscissa
order. Signed-zero quadrants, NaNs and infinities remain values; finite platform
rounding is not Go bit identity. Invalid histogram pairs omit only matched
elements and report original-order operand types. The complete arithmetic
fixture also exposed missing infos for previously unsupported histogram binary
pairs; those now use the same diagnostic. Float arithmetic removes the many-side
name before explicitly including one-side labels, so grouped `__name__` inclusion
works. Annotations remain query-local and omit upstream source positions.

The fixture runner now enforces `eval_ordered`/`expect ordered` instant order
without incorrectly ordering range matrices, parses stale markers, and checks
exact warning messages with an explicit position-only mapping. Additional local
controls check calendar defaults/leap/pre-epoch/int64 boundaries, Unicode and
overflow sorting, full-label ties, unchanged signed-zero/histogram observations,
the 49-case `atan2` special-value table, grouped operand order, type notices,
tenant separation, shared sample/work/result admission and query-batch isolation.
The query formatter round-trips the new operator at every binary precedence.
Tests require no Go, Docker, reference service or download; no storage/native
tuple/keyed-byte change or new coordination state is introduced.

Validation: targeted parser/oracle/batch/HTTP/formatter tests passed **198/198**
with seed 198. Final `mix precommit --max-cases 4 --seed 200 --warnings-as-errors`
passed **2025 tests**, with 1 skipped and 37 excluded, in 388.0 seconds,
including the existing selected Loki and Tempo ports. Strict Credo checked
438 files without findings; formatting and whitespace checks passed. All 43
fixtures match their pinned source selections and all 46 recorded README hashes
match. Independent Go UTC checks covered negative fractions, year zero,
leap-century boundaries, exceptional conversions and int64 edges; the temporary
producer was removed. No failing check was ignored. This batch and earlier
local continuations remain uncommitted and unpushed; no migration or deployment
ran. Provider/capacity/deployed-client and full cross-platform numerical parity
remain separate acceptance work.

### Batched scalar query context and extrema

Removed six scalar functions from the remaining PromQL gaps: `start`, `end`,
`step`, `range`, `min_of` and `max_of`. Three verbatim Mimir fixture selections
add **51 evaluations** (21 instant, 30 range), replayed as **144 HTTP requests**
across memory and native S3/Parquet adapters. The complete corpus now has
46 files, 429 evaluations and 1466 requests across 92 fixture wrappers.
These are selected query-engine cases, not the upstream service/Docker suite.
Source ranges, licenses and hashes remain in the fixture provenance README.

Query-context functions use requested outer boundaries and interval, not the
last grid point, a shifted subquery window or its resolution. Equal boundaries
make `step()` zero, but different bounds with only one grid point still return
the requested step. Each source resets context without resetting shared work
or result budgets. `range()` retains Go's int64 duration saturation; Pulse
deliberately retains its existing nanosecond timestamp precision rather than
upstream millisecond quantization. The separate selector `@ start/end()` cases
are excluded explicitly and parser controls require rejection. No temporal-AST
or modifier coverage is claimed by adding scalar functions.

Scalar extrema evaluate both arguments at every step, preserving Go
`math.Min`/`math.Max` infinity-over-NaN precedence and zero signs rather than
using the existing NaN-ignoring aggregation helpers unchanged. Independent
HTTP controls cover all 98 special-value pairs, composed time-varying scalars,
fractional/non-grid-aligned boundaries, nested/offset subqueries, duration
saturation, default evaluation time, reverse-order batch isolation and
cumulative work/result rejection. Formatter and parser contracts cover all
six functions. Ordinary replay needs no Go, network or upstream runtime;
native/storage formats and keyed bytes remain unchanged.

Validation: all six new fixture wrappers failed with unsupported-query HTTP400
before implementation. Targeted parser/batch/HTTP/formatter coverage passed
203 tests with seed 203. Final `mix precommit --max-cases 4 --seed 205
--warnings-as-errors` passed **2037 tests**, with 1 skipped and 37 excluded,
in 123.0 seconds, including the existing selected Loki/Tempo regression ports.
Strict Credo checked 438 files without findings; formatting and whitespace
checks passed. All 46 fixtures match their source selections and all 49 README
hashes match. An independent offline Go 1.25.10 arm64 run confirmed every one
of the 98 scalar-extrema expectations; the temporary producer was removed.
No failing check was ignored. Compaction timeout/fault and test-store CAS
diagnostics remain in the full log, not evidence of provider/load acceptance.
This batch and earlier local continuations remain uncommitted and unpushed;
no deployment or migration ran. Full modifier, client and capacity parity
remain separate gaps.

### Batched population dispersion, quantiles and value counts

Removed four aggregation names from the remaining PromQL gaps: `stddev`,
`stdvar`, `quantile` and `count_values`. Five verbatim Mimir fixture selections
add **88 evaluations** (59 instant, 29 range), replayed as **294 HTTP requests**
across memory and native S3/Parquet. The complete corpus now has 51 files,
517 evaluations and 1760 requests across 102 fixture wrappers. The source
selection includes all relevant negative-histogram value-count expectations,
not just float-only cases, and preserves the initial sum/avg grouping controls.
Unsupported mixed-type sum/avg annotation blocks remain explicitly outside
this selection. These are selected public engine tests, not a full service suite.

Dispersion uses ordinary per-group Welford updates, matching Mimir's aggregate
implementation rather than the compensated range-vector algorithm. Histograms
omit with infos even in histogram-only groups; nonfinite singletons yield NaN.
Quantiles reuse the existing NaN-first interpolation with exact-rank infinity
handling, evaluating scalar parameters and warnings at every step, even with
empty input. Sort work is reserved per group and notices remain source-local.

Value counts preserve complete exponential/custom histogram text, negative
buckets and the distinction between original bucket bounds and zero-clipped
HTTP bounds. Float values use shortest fixed decimals, histogram fields use
Go general format, and signed-zero label values stay distinct. Nonempty UTF-8
destinations can overwrite grouping labels or explicitly set metric names.
Labels are projected before setting the destination, matching Mimir; a
generated label named by `without` therefore survives, unlike its vendored
Prometheus engine. This deliberate boundary is documented and directly tested.
Generated label bytes and histogram bucket work share existing query budgets;
there is no format/native/keyed-byte change or new shared state.

Extra controls exercise changing nonstale populations, sparse-step histogram
omission, nested aggregations, custom/overlapping-zero text, subnormal/extreme
fixed decimals, Unicode/name destinations, form POST, tenant separation,
source-local warnings and shared scan/work/result/batch rejection. The DSL
runner recognizes histogram text inside quoted labels, negative histogram
inputs and the exact invalid-UTF8/position-only warning mappings without
rewriting source expectations. Parser/formatter controls include parenthesized
string parameters, invalid types and bounded malformed nesting.

Validation: all ten new fixture wrappers failed with unsupported-query HTTP400
before implementation. `mix precommit --max-cases 4 --seed 212
--warnings-as-errors` passed **2054 tests**, with 1 skipped and 37 excluded,
in 557.8 seconds, including the existing Loki/Tempo ports. After the final
test-helper refactor, targeted parser/semantics/HTTP replay passed **218 tests**
with seed 213, and strict Credo checked 438 files without findings. Formatting
and whitespace checks passed. Independent reconstruction verified all 51
fixture selections and 56 README hashes; an offline Go oracle matched 4126
finite float bit patterns in both fixed/general modes. Temporary producers
were removed. No failing check was ignored. Full-suite logs still contain
compaction timeout/conflict, test-store CAS and teardown diagnostics, alongside
intentional URI-limit/gRPC-crash controls; these are not provider/load evidence.
This batch and earlier local continuations remain uncommitted and unpushed;
no deployment, migration or native/storage format change ran.

### Batched signed offsets, unitless durations and fixed evaluation times

Removed five temporal feature gaps: negative offsets, unitless duration literals,
numeric `@` anchors, `@ start()` and `@ end()`. Selectors, range selectors and
explicit-resolution subqueries accept one offset and one anchor in either order;
duplicates and anchors on arbitrary expressions reject. Four unchanged Mimir
fixture selections add **95 evaluations** (73 instant, 22 range), replayed as
**336 HTTP requests** across memory and native S3/Parquet. They include the
complete upstream `at_modifier.test`, selector/reset controls and nested fixed
subqueries with varying scalar arguments. Source bytes, hashes, ranges and
licenses are independently recorded; no selected expression is rewritten.

The existing AST keeps integer offsets for unanchored queries and a tagged
anchor/offset pair for fixed source times. The evaluator resolves both through
the same storage-window and epoch-aligned subquery paths. Only data is pinned:
quantiles, smoothing factors and prediction reference time follow each outer
step. Query-boundary anchors use the requested outer start/end, not an inner
subquery grid or the last output point. Every batch source resets its clocks
while retaining shared budgets. Fixed data does not bypass per-step work or add
upstream's step-invariant operator cache.

Decimal/exponent seconds normalize exactly into admitted nanoseconds; formatting
does not round-trip anchor integers through floats. Existing one-year windows/
absolute offsets and int64 anchor bounds remain. Shifted selector intervals
intersect int64 storage time without wrapping or clamping observations; disjoint
windows are empty and generated out-of-domain subquery grids reject. S3's
existing nonnegative source-time object-key contract is unchanged. The later
grammar batch closes hexadecimal/separator literals and omitted subquery
resolutions; `anchored`/`smoothed` remain gaps. No native ABI,
stored format, keyed bytes, configuration or shared state changes; upgrade every
query-serving application before relying on the new syntax.

Local controls distinguish source times from output/parameter times, check
nanosecond left-open windows, stale/native-histogram selection, future offsets,
negative query anchors, contemporary outer timestamps differing by nanoseconds,
unaligned ends, nested clocks, changing scalar parameters, GET/form POST and
tenant isolation. Independent sample/work/result limits, S3 physical footer-row
admission, cumulative batch costs and int64 edges fail whole. Memory additionally
stores a negative-time edge sample; the S3 control does not pretend that existing
storage limitation is closed. These are not extra upstream or capacity cases.

All eight imported fixture wrappers failed HTTP400 before implementation. The
targeted parser/batch/formatter/HTTP replay passed **238 tests**, seed 217.
Independent reconstruction verified all **55 fixture selections**, **63 README
hashes** and three license/notice files against the pinned Mimir Git objects.
The complete selected corpus has 612 evaluations and 2096 two-adapter requests.

Final `mix precommit --max-cases 4 --seed 218 --warnings-as-errors` passed
**2072 tests**, with 1 existing skip and 37 opt-in exclusions, in 265.7 seconds.
This includes the retained Mimir/Loki/Tempo regression ports and compile,
dependency and formatter checks. Strict Credo checked 438 files without
findings; final formatting and whitespace checks passed. No failing check was
ignored. Full-suite logs still contain compaction timeout/conflict, test-store
CAS and intentional oversized-URI/gRPC-crash diagnostics; these do not establish
provider/load acceptance. Temporary verification tooling was removed. This
batch and earlier local continuations remain uncommitted and unpushed; no
deployment or migration ran.

### Completed sampling batch: limitk and limit_ratio

Closed two more aggregation gaps together. The complete pinned upstream and
Mimir `limit.test` files add **130 unchanged evaluations** (71 instant, 59 range)
and **402 memory/native-S3 HTTP requests**, including instant cases replayed as
one-step ranges. Full labels, names, float values and complete native histograms
survive sampling; missing/stale observations remain absent. Grouped cardinality,
mixed lifetimes, ordinary NaNs, changing scalar k/ratios, negative complements
and cap warnings come from the original fixtures, not generated Pulse answers.

`limit_ratio` uses the default pinned Prometheus length-prefixed full-label
XXH64 hash, which differs from storage StableHash. Query-local hashing follows
label rewrites and includes the metric name; grouping never projects output
labels or changes ratio membership. `limitk` deliberately orders by full-label
hash to provide stable value-independent subsets, not exact identity parity
with Mimir's input iteration order. No cross-version/alternative-label-build
hash guarantee or high-cardinality acceleration is implied.

Parameters validate every step, even for empty vectors. k truncates finite
fractions toward zero, maps negative values to zero and rejects NaN/infinities/
out-of-int64 values; NaN ratios reject and outside-range ratios cap with the
first warning per direction per operator. Warning sets reset between batch
sources; shared work/sample/result budgets do not. Label bytes, sorting and
grouping spend bounded work before allocation. No native ABI, storage, keyed
bytes, configuration or shared authority changes; upgrade every serving app.

Independent Go 1.25.10 / cespare XXH64 validation matched **1031 label sets**,
including all payload lengths 0–1027, Unicode, a 255-byte name and empty labels.
Fourteen permanent HTTP identity controls distinguish the exact hash threshold
from its adjacent float, including 254/255/256-byte prefixes. Other local
controls cover deterministic grouped identities, sample/type preservation,
rewritten labels, complement unions/intersections, GET/form POST, tenant and
batch-warning isolation, empty-input failures and independent/cumulative query
budgets. No Go/network dependency enters ordinary Elixir tests. These are local
controls, not extra imported, provider, capacity or deployed-client acceptance.

All four imported wrappers failed HTTP400 before implementation. The complete
sampling replay and controls passed **8 tests**, seed 222. Reconstruction from
the pinned Git objects verified **57 selections**, **67 hashes** and three
license/notice files. The selected corpus now has 742 evaluations and 2498
two-adapter HTTP requests. Strict Credo checked 439 files without findings.

The first full `mix precommit --max-cases 4 --seed 223 --warnings-as-errors`
run passed **2078/2081 tests**, with 1 skip and 37 opt-in exclusions, in 920.2s.
It failed the 60s randomized LogQL parity test, the 120s Tempo root-budget test
and the 60s Tempo special-character integration test on timeouts. No assertion
or timeout was changed and none of these failures is waived as baseline-only.

The full rerun with the same seed and `--max-cases 2` passed **2081 tests**,
with 1 skip and 37 opt-in exclusions, in 492.4s, including all three timed-out
tests. No application/test files changed between runs, and no limits or
timeouts were raised. Compile, dependency and formatter checks also passed.
Logs retain self-metrics/compaction timeouts and test-store CAS diagnostics;
this is not their root-cause, provider or capacity acceptance. Temporary oracle
and verification tooling was removed. This batch and earlier local
continuations remain uncommitted and unpushed; no deployment or migration ran.

### Batched duration expressions and duration-valued scalars

Closed arithmetic in range windows, subquery windows/resolutions and signed
offsets, outer-context `step()`/`range()` and nested `min_of`/`max_of` durations,
and unit-bearing scalar arguments. The complete pinned Mimir upstream
`duration_expression.test` is copied byte-for-byte: 256 lines, 59 evaluations
(30 instant/29 range) and 178 memory/S3 HTTP requests. The existing Apache/AGPL
notices, source ranges and SHA-256 provenance remain explicit in the fixture
README. The separate instant control translates Mimir's
`TestInstantQueryDurationExpression` without requiring Go or a running Mimir.

Durations resolve once before storage reads using the requested outer context,
including under nested subqueries and per-source query batches. Unparenthesized
offsets bind before arithmetic, while parentheses explicitly move arithmetic
inside the offset. Invalid division/modulo, nonfinite final results, nonpositive
windows/resolutions and out-of-budget expressions fail whole even on empty
selectors. Duration syntax is restricted to literals, arithmetic, parentheses
and those four context/extremum functions; request step/lookback values remain
literal-only. Query AST/work and scan/sample/intermediate/result/step limits
remain shared. Existing exact bare timestamps and literal windows are unchanged.

Pulse deliberately keeps its one-year literal/result ceiling and nearest-nanosecond
rounding, ties away from zero, instead of the pinned engine's wider range and
millisecond truncation. Expression operands retain subnanosecond fractions until
final conversion. Separate controls distinguish early operand rounding, outer
ends from last grid points, inner from outer clocks, zero-step instant queries,
histograms, GET/form POST, tenant/batch isolation and independent/cumulative
budgets. Formatting retains duration ASTs and rejects unsupported data-dependent
syntax; deep/incomplete expressions are bounded. Native ABI, storage formats,
keyed bytes, configuration and shared authority are unchanged.

Validation: the imported file first failed HTTP 400 on both unchanged adapters.
The focused replay and controls passed **8 tests**, seed 225. All **58** selected
fixture files were independently reconstructed from the pinned commit; **69**
README hashes and all three license/notice files matched. Strict Credo passed
over **440** source files. Full `mix precommit --max-cases 2 --seed 226
--warnings-as-errors` passed **2091 tests**, with 1 skip and 37 opt-in exclusions,
in 389.4s; compile, formatter and unused-dependency checks passed too. No failing
check was waived. Logs retain test-store CAS/acceptor and compaction diagnostics;
this is not their root-cause or operational/capacity acceptance. Temporary
verification tooling was removed. This and the earlier continuations remain
local, uncommitted and unpushed.

### Batched post-unwrap filters and explicit extraction-error selection

Closed label filtering after unwrap, conversion-error removal and explicit
error selection, retaining error identities through range grouping and correct
outer aggregation. Twenty-nine pinned Loki script scenarios extend the exact
logfmt/JSON/metadata fixtures and add failed-conversion absence/extrema/rate
checks through real GET/form-POST HTTP, native Parquet and an owned S3 store.
Two scenarios deliberately reject. Existing limits remain: rejected values
spend scan/pipeline work but not retained-sample quota; input preservation
labels cannot bypass the error guard. The eight evaluator controls distinguish
pre/post conversion, selected failures, incoming errors, grouping, unit
conversions and budgets. All six initial controls failed before the fix;
the expanded 14 tagged evaluator/HTTP checks pass (seed 233).

Post-filter/error-preserving queries fall back to bounded Elixir evaluation;
ordinary queries keep native execution. No ABI/storage/keyed-byte change.
Complete parser/numeric-filter error generation, parser hints, conversion
overflow/diagnostic parity and Go string escaping remain open. Missing unwrap
targets retain their conservative incoming-error guard. These tests establish
neither deployed client acceptance nor provider/capacity/cutover readiness.

### Batched default subquery grids, numeric time spellings and UTF-8 label lists

Closed omitted subquery resolutions, hexadecimal/separator query time literals,
quoted UTF-8 grouping/matching/include names and UTF-8 `label_replace`
destinations. Omitted resolutions use Mimir's fixed one-minute epoch grid,
independent of outer step, window and nesting. Decimal anchors retain exact
nanoseconds; hexadecimal integers and separators work in windows, resolutions,
offsets, anchors and duration arithmetic. HTTP time parameter grammar is unchanged.
Formatting quotes non-identifier labels and preserves omitted resolutions;
empty/invalid/duplicate/overlapping decoded names still reject.

Two unchanged pinned Mimir selections add 14 evaluations and 56 memory/S3 HTTP
requests, retaining licenses, source ranges and hashes. The name-removal block
and empty absent/present subqueries are copied, not regenerated; the remaining
new syntax controls are explicitly Pulse-authored against the pinned grammar.
Controls distinguish independent minute grids from outer-step/window defaults,
nested clocks, fixed/future anchors, sparse/histogram windows, exact nanosecond
boundaries, both grouped operand orders, form POST and tenant isolation.
Parser/formatter controls cover decoded identity, malformed strings/numbers and
round-trip stability. Existing AST/time/scan/sample/work/result/step bounds apply;
one-year durations, int64 nanoseconds and top-level range-result rejection remain.
No configuration, native ABI, storage, keyed bytes or shared authority changes.

Validation: all ten new HTTP fixture/control checks failed before runtime
changes and passed after implementation (seed 228). Full `mix precommit
--max-cases 2 --seed 230 --warnings-as-errors` passed **2102 tests**, with one
skip and 37 opt-in exclusions, in 138.9s of test execution. Compile, formatter,
unused-dependency and whitespace checks passed. Strict Credo checked 440 source
files without findings after flattening numeric validation. Independent
reconstruction matched all 60 selections, 72 README hashes and three original
license/notice files; temporary verification tooling was removed. No failing
check was waived. Logs retain compaction timeout/conflict and test-store CAS
diagnostics; this does not close their cause or establish production readiness.
This and earlier local continuations remain uncommitted and unpushed.

### Batched top-level PromQL result types

Closed instant-query strings, raw range selectors and top-level subqueries.
Strings retain decoded content and evaluation time; matrices retain original
sample/inner-grid timestamps, names, stale omission and complete native
histograms. Anchors and offsets reuse existing selection semantics. The range
endpoint still rejects string/range expressions before storage, even at equal
bounds. Binary arithmetic/comparisons reject string/range operands rather than
mistaking them for instant vectors. Existing sample/work/intermediate/output
limits remain shared, including mixed-source query batches. No configuration,
native ABI, storage or keyed-byte change is needed.

Ten verbatim pinned Mimir engine cases and two source frontend scenarios add
permanent HTTP regressions with complete value/type/timestamp expectations.
The frontend random float is frozen to 0.5; deployment permutations are omitted.
Two exact fixture selections retain source ranges, licenses and hashes. Public
histogram JSON cannot expose reset hints, so loading the source hints is not
wire reset-hint proof. The corpus now has 825 evaluations in 62 files and
2772 Memory/S3 HTTP requests, including 20 new deliberate range-endpoint
rejections. Separate controls cover clocks, mixed samples, stale markers, zero
signs, form POST, tenant isolation, fail-whole quota boundaries and no-I/O
invalid range requests. Targeted result wrappers/controls pass (seed 241), as
do 74 parser, batch and HTTP checks (seed 242). Full `mix precommit --max-cases 2
--seed 243 --warnings-as-errors` passed 2124 tests, with one skip and 37 opt-in
exclusions. Strict Credo is clean; later result-finalization/assertion extraction
also passed the combined seed-249 validation below.
Earlier notes describing top-level instant ranges as unsupported are superseded
by this increment; range-query rejection remains intentional. No provider,
deployed-client or capacity acceptance, commit or push is implied.

### Batched Loki scalar types, arithmetic and number grammar

Closed scalar instant envelopes across HTTP/MCP/batches/previews, scalar
comparisons without mandatory `bool`, hexadecimal-float and separator/decimal
literal syntax, zero-divisor NaNs in both scalar/vector orientations, and
incorrect vector/general-expression unary negation. `vector(n)` remains a
vector; all range requests remain matrices. Existing quotas, authorization and
encoding flags still apply, and invalid literals fail before storage. Division
adapts only LogQL operands; PromQL signed infinities are unchanged. Native
thresholds still require vectors; scalar-only sources keep their type rather
than silently becoming threshold instances. No native ABI/storage/keyed-byte
or configuration change is introduced; upgrade all query-serving applications.

Three engine wrappers port all 33 scalar-section and five vector-literal cases
from pinned Loki. Inputs/expectations retain source values/times; failure
diagnostic text is explicitly adapted. Additional range replays and four
HTTP/MCP/quota/preview controls are separately identified. All 28 successful
scalar pairs were independently checked against source, in order, and all
62 Mimir selections matched exact pinned bytes and evaluation counts. Two
scalar/grammar checks failed before the fix and the vector control passed
(seed 245); seven tagged checks pass after (seed 247), and 385 broader
LogQL/HTTP/MCP/batch/preview tests pass (seed 248). Strict Credo is clean.
Combined `mix precommit --max-cases 2 --seed 249 --warnings-as-errors` passed
2131 tests in 238.3s, with one skip and 37 opt-in exclusions. No check was
waived. Local work remains uncommitted/unpushed;
this is not a complete replacement, provider/capacity or deployed-client proof.

### Batched typed LogQL filters and error propagation

Closed numeric/duration/byte filters silently discarding malformed or empty
present values: they now retain `LabelFilterErr` for later filters, preserving
the first nonempty error; missing labels remain nonmatches. Numeric filtering
uses float64 semantics (NaN/infinity, hexadecimal floats, separators and rounded
large integers), and typed equality accepts both =/== without widening string,
selector or drop/keep grammar. AND evaluates both operands and threads labels;
OR short-circuits. Unpreserved errors still fail metrics before grouping can
discard them. Native ordinary-decimal comparisons stay native; conversion/error
handling falls back to the bounded Elixir evaluator, never a silent nonmatch.
Require log codec tuple `{1,1,5}` on every query-serving app/native pair. No
storage/keyed bytes, cluster state or resource ceilings change.

Three HTTP/S3 wrappers port all 28 rows of pinned Loki `TestBinary_Filter`,
`TestBytes_Filter` and `TestErrorFiltering`. Constructor-to-query conversion,
an isolated job label/constant payload and three Pulse-specific error-detail
strings are explicit adaptations. Canonical ns/B literals preserve independent
upstream integer expectations rather than comparing the unit converter with
itself. No Go runtime implementation was copied.
Eight local checks cover memory/native adapters, absent/empty values, float
rounding/nonfinites, eager/lazy boolean paths, error-category provenance,
HTTP/form agreement, first errors and retained-sample/work budgets. The source
binary-filter wrapper failed on its duration-error row before the fix while
the byte-unit wrapper passed (seed 250); control failures also exposed error
propagation and unsupported typed == syntax (seed 251). The first ten tagged
checks pass after (seed 252). Broader Loki/LogQL/MCP/batch/preview validation
passes 500 tests (seed 253), including the final parser control. All 133 release
codec tests, Rust formatting, strict Clippy and strict Credo pass. Combined
`mix precommit --max-cases 2 --seed 254 --warnings-as-errors` passed 2142 tests
in 207.7s, with one skip and 37 opt-in exclusions; no check was waived. The later
independent canonical-unit test strengthening passed all eleven tagged checks
(seed 255).
No provider/client/capacity, commit or push acceptance is implied.

### Batched Tempo metric arithmetic and scalar filters

Closed bounded scalar/vector `+ - * /`, constant integer-versus-float folding,
value-preserving scalar comparisons and chained filters. Ordered typed group
labels match exactly; only ungrouped operands broadcast. Names, operand order,
NaN propagation and runtime zero-division match the pinned engine tables.
Signed int64 literal/folding overflow deliberately rejects rather than wrapping;
duration operands, scalar-only queries and unsupported operators reject before
storage. Query-serving app/native pairs now require trace metrics capability **5**
(including directional string-group ties and a single scalar filter before ranking);
trace tuples, storage formats and keyed bytes are unchanged.

One native batch feeds all unique leaves from one storage scan and one GET per
admitted object; each leaf still decodes that source separately. Native budgets
are shared across leaves (10,000 series, 2M interval points, 20M selector work,
64 MiB retained group-value payload). Arithmetic runs in the existing BEAM
query worker with shared deadline/heap isolation, 128 AST nodes, depth 32,
16 unique leaves, 2M intermediate points and 20M arithmetic point operations.
Packed results and JSON each cap at 64 MiB. Missing-source errors fail whole for
expressions rather than restarting scan budgets; ordinary pipeline retry is
unchanged. These are payload/work ceilings, not total-memory or capacity proof.

Pinned Tempo `1a7373ee774b2ee5a40957c2310179b0ef7ff843` supplies all 87
`TestScalarMath` rows, all 23 `math_` storage-engine rows, and all 18 positive/six
negative metric-expression grammar rows. The AGPL fixtures retain source hashes,
inputs and expected transforms; ordinary replay needs no external runtimes.
All scalar rows replay through Memory/native and authenticated HTTP/Parquet.
Storage rows preserve all 100 traces, the original 50s scan end versus 60s final
bucket, and simulated duplicate additive-source observations, asserting exact
final L3 expectations. They are engine oracles, not misrepresented HTTP ports;
L1/L2 expectations are retained but not separately asserted. JSON infinity
strings are an explicit Pulse transport adaptation. No Tempo runtime code is
copied or executed by fixture generation.

Three asymmetric arithmetic controls failed before implementation (seed 256).
After implementation all 18 metrics units pass (seed 263), including shared
series-limit boundaries, typed/order/missing labels and signed-int64 constants.
The original HTTP quota-control failure was an immutable test-context snapshot,
not a production quota bypass; using an owned shared context makes it pass
(seed 260). Additional HTTP controls prove unique provider reads, instant
span-weighted arithmetic and rejection before storage. All 133 release codec
tests, Rust formatting, strict Clippy under the repository's mise environment
and strict Credo (442 files) pass. Combined
`mix precommit --max-cases 2 --seed 264 --warnings-as-errors` passed **2154 tests**
in 203.5s, with one skip and 37 opt-in exclusions. No check was waived.

The first combined run exposed an outdated LogQL reference error check, not a
Tempo or native production failure. Pinned Loki `streamLabelSampleExtractor.Process`
and `LabelsBuilder.SetErr` explicitly replace an earlier filter error when
unwrap conversion fails. The frozen materializing reference checked before
conversion; it now models this replacement before metric validation, retaining
deferred window errors and the existing strict missing-target guard. A literal
single-row/OR regression failed before this reference correction, then all 53
related checks passed with the failing seed 264. Three additional randomized
replays passed (seeds 266–268). No production LogQL behavior or error assertion
was weakened to make the reference agree.

Full TraceQL, exemplars, streaming and provider/deployed-client/capacity
acceptance remain open. Work is local, uncommitted and unpushed.

### Loki runtime duration and byte conversion continuation

Closed runtime producer-value duration/byte grammar, precision and overflow
gaps in typed label filters and unwrap. Durations use Go's signed-int64 profile,
including Greek-mu microseconds and bounded fractional float64 accumulation;
unwrap converts whole seconds and remainders separately. Bytes use the pinned
go-humanize unsigned-uint64 profile: case-insensitive suffixes through exabytes,
optional B, suffix whitespace, numeric commas, exact integer multiplication
and float64 fractional scaling/truncation. Negative/explicitly signed bytes
and runtime days now error rather than retaining Pulse extensions. Query-serving
applications must upgrade together; exact shared/query-literal quantities,
native tuple `{1,1,5}`, storage/keyed bytes and resource ceilings are unchanged.
No Go runtime implementation is shipped or required for normal tests.

Four authenticated HTTP/Parquet/loopback-S3 wrappers port 109 source cases:
six pinned Loki successful extractor rows, all 43 Go 1.27.3 duration successes,
18 UTF-8 duration errors, all 37 go-humanize v1.1.0 byte successes and five byte
errors. Three invalid-UTF-8 Go error inputs are explicitly not HTTP ports.
Source licenses, hashes and constructor-to-one-observation grouped-average
adaptations are retained in the fixture README. Filter thresholds use canonical
ns/B integers; large unsigned values use positive filters/unwrap plus exact
utility controls rather than invalid query literals. Error rows preserve
Pulse-specific diagnostic text, empty unwrap skipping and fail-whole metrics.

Both successful-table wrappers failed before converter wiring, on Greek `μs`
and lowercase byte suffixes (seed 269), then passed after. All 80 success rows
were independently matched against original Go AST input/constant expectations.
A temporary executable using actual Go 1.27.3 and the pinned vendor byte
converter matched 12,079 duration/byte inputs, including rounding, Unicode
whitespace, integer boundaries and long malformed values. Separate local
controls check literal isolation, exact uint64 versus fractional rounding,
form/range behavior and fail-whole retained-sample/work/result budgets.

Final `mix precommit --max-cases 2 --seed 272 --warnings-as-errors` passed
**2160 tests**, with one existing skip and 37 opt-in exclusions, in 403.3s.
Strict Credo (442 files), formatting and diff checks pass. The final converter
also reverses all 1047 checked-in canonical Go duration strings exactly. Initial
broad validation caught an invalid-UTF-8 utility crash and an unsupported
grouped-sum test adaptation; input validation and a one-observation grouped
average resolved them without weakening the source expectations. No check was
waived. Logs retain the existing compaction timeout/conflict and test-store CAS
diagnostics; this batch does not establish their closure.

Go diagnostic wording/escaping, complete parser errors and query-literal
quantity parity remain open. These portable engine/dependency tables do not
establish full Loki, deployed clients, provider capacity or replacement
acceptance. Work remains local, uncommitted and unpushed.

### Loki query quantity literal continuation

Closed signed/fractional duration thresholds and offsets, fractional byte
rounding, the uint64 byte-threshold range and restricted optional byte suffixes.
Duration tokens try the ordered integer model profile first, then Go duration
conversion; fractional d/w/y reject. Public bracket windows now use ordered,
unrepeated integer y/w/d/h/m/s/ms without internal whitespace. Former fractional,
ns/us windows reject; source/evaluation timestamps and open-lower/closed-upper
nanosecond boundary comparisons stay unchanged. Existing synthetic sub-ms
evaluator regressions retain all expected values through AST windows. Exact
shared quantities, native log tuple `{1,1,5}`, storage/keyed bytes and resource
ceilings stay unchanged; upgrade query-serving applications together.

Three authenticated HTTP/native-Parquet/loopback-S3 wrappers add 41 pinned
source inputs: all 11 Loki lexer duration-conversion rows, all 13
prometheus/common v0.72.1 base durations and nine bad-duration inputs, plus
eight byte-token examples. Three zero durations parse but retain Pulse's
existing metric-evaluation rejection. Byte examples adapt token-only assertions
into numeric HTTP thresholds, rather than claiming the enclosing source query
was transplanted unchanged. Licensing, hashes and adaptations are recorded in
the fixture README. Two additional local wrappers distinguish adjacent
quantities, signed/unsigned ceilings, optional suffixes, threshold versus runtime
versus range grammars, signed fractional offsets, form/range replay and
fail-whole work limits. Invalid syntax proves no provider reads occurred.

The pre-change quantity regression failed on fractional-hour rounding (seed
273). A temporary Go 1.27.3 executable using the original pinned scanner,
lexer conversion functions and dependency converters checked 5832 token/range
decisions: 5831 exact matches and one explicit difference. The pinned lexer
test expects `0B` to be BYTES while its scanner also reports `literal has no
digits`; Pulse retains valid zero-byte thresholds instead of that error.
This is not an omitted mismatch or full upstream parser/engine acceptance.

Final `mix precommit --max-cases 2 --seed 279 --warnings-as-errors` passed
2165 tests with one existing skip and 37 opt-in exclusions, including the
83-check Loki HTTP/S3 module. Strict Credo checked 442 source files without
findings; scoped formatting and `git diff --check` passed. The initial full
run timed out in the older 43-row runtime-duration wrapper. Publishing that
table and the 37-row byte table as one multistream fixture each removed their
growing-catalog scan overhead without changing inputs, expected values,
timeouts or budgets; the final full run passed with this harness adaptation.

Complete parser errors and Go conversion diagnostic text/escaping remain open.
The general quantity-converter feature gaps are removed from the remaining
list, not the documented scanner contradiction or broader Loki/client/provider
acceptance.
Work remains local, uncommitted and unpushed.

### Loki duration diagnostic continuation

Closed invalid/missing/unknown-unit duration diagnostic wording and Go's
byte-oriented quoting for typed filters and both duration unwrap spellings.
The original signed input survives; numeric overflow takes precedence over
unknown-unit reporting as in Go. Duration conversion produces one result/error
shared by the filter and metric paths, without reparsing failures. Valid
quantities, first-error filter semantics, explicit metric-error preservation,
fail-whole guards, resource ceilings and native/storage/keyed formats remain
unchanged. Upgrade query-serving applications together and replace selectors
matching Pulse's former generic duration diagnostics.

The existing Loki binary-filter error row now preserves its exact source
diagnostic. One additional extractor-table wrapper keeps the original
`foo=not_a_number` line, `bar=foo` stream, `bar,buzz` grouping, zero result and
error details; HTTP adds explicit error selection to expose the kept failed
sample instead of claiming an unmodified extractor call. Independent Go 1.27.3
goldens cover all 18 UTF-8 error-table inputs, those two Loki inputs and 14
local escape/precedence controls. Three invalid-UTF-8 Go rows are tested only
through the converter, never falsely counted as JSON HTTP. A checked-in
standard-library producer reproduces the goldens, but normal tests need no Go
or downloads. Existing licenses, source ranges, hashes and adaptations are
recorded in the fixture README. The HTTP/S3 module now contains 85 checks:
55 source-derived wrappers and 30 separately identified local controls.

All three new/strengthened diagnostic wrappers failed before production edits
(seed 280). The LogQL/Loki controller subset passed 342 tests (seed 281).
A temporary differential probe checked 14733 real Go duration decisions
(364 valid, 14369 errors) with zero mismatches, including full diagnostic text
and invalid bytes; replaying the frozen inputs after the final code changes
also had zero mismatches. The checked-in producer reproduced all fixture bytes.
Final `mix precommit --max-cases 2 --seed 282 --warnings-as-errors` passed
2167 tests with one existing skip and 37 opt-in exclusions in 330.4 seconds.
Strict Credo checked 442 source files without findings; scoped formatting and
`git diff --check` passed. An earlier full attempt lost its runner connection
before a result and is not counted as a completed run.

This is not execution of Loki's engine/HTTP suite or provider/deployed-client/
capacity acceptance. Numeric/byte diagnostics and complete parser errors remain
open. Work remains local, uncommitted and unpushed.

### Loki byte diagnostic continuation

Closed byte numeric-prefix, unknown-suffix and uint64-overflow diagnostics for
typed filters and `unwrap bytes(...)`, using the pinned go-humanize v1.1.0
converter rather than generic Pulse messages. Float parsing precedes unit
lookup; an unknown unit precedes scaling overflow. Error text preserves the
original input for overflow and the comma-normalized numeric prefix for parse
failures. Preserve the dependency's rune-count/byte-slice behavior, including
truncated UTF-8 prefix quoting. Go 1.27's Unicode 17 decimal digits and simple
suffix lowercasing now agree, including accepted `1KİB` and `2Mİ` values.
First-error filtering, missing/empty unwrap skipping, explicit metric-error
preservation, native fallback, shared budgets and storage/keyed/native formats
remain unchanged. Upgrade query-serving applications together and replace
selectors matching former generic byte diagnostics.

The existing five-input dependency error table and original Loki `bytes=2qb`
binary-filter row now assert complete source diagnostics. One additional
HTTP/native-Parquet/loopback-S3 wrapper checks 28 separately identified local
diagnostic controls plus the two valid Unicode suffix cases, exact-detail
GET/form selection, kept failed zero samples, first-error preservation and
work-budget rejection. Independent checked-in goldens contain all six source
inputs and the 28 local diagnostic controls. The producer reads the original
Go AST and calls the dependency; ordinary Elixir replay requires no Go or
downloads. Existing licenses, source ranges and hashes are recorded in the
fixture README. The annotated dependency tag now resolves to its source commit
in links; selected source bytes are unchanged. The HTTP/S3 module contains
86 checks: 55 source-derived wrappers and 31 local controls.

All three new/strengthened wrappers failed before production edits (seed 283).
A temporary independent probe checked 21510 real Go/dependency decisions
(4292 valid, 17218 errors) with zero mismatches, including exact error text,
Unicode prefix boundaries, suffix casing/spacing, precision and overflow.
All 1112064 Unicode scalars were compared for the relevant lowercase/digit/
whitespace semantics. Producer regeneration matched the checked-in bytes.

The first LogQL/Loki subset had 342/343 passing tests (seed 284): the remaining
failure exposed undecoded `\u0000` in a quoted exact-detail selector. The
strengthened existing selector check failed before its lexer fix (seed 285).
That initial fix decoded fixed-width Unicode scalars and rejected malformed,
surrogate or out-of-range escapes; raw backticks remain literal. Six selected
Go unquote rows and local boundary controls protect this through `Parser.parse`.
A separate 6036-case comparison with actual Go `strconv.Unquote` matched all
5788 decoded values and 248 rejections. All four focused parser/HTTP wrappers
passed (seed 286), retaining the original NUL selector and expected error.
The later string-literal batch below corrects the surrogate policy: Go Unquote
was not the actual pinned Loki scanner/decoder contract.

Full `mix precommit --max-cases 2 --seed 287 --warnings-as-errors` was not clean:
2163 passed, five failed, one skipped and 37 excluded in 1508.3 seconds. All
new Loki/parser regressions passed. The failures were timeout-related in
unchanged test paths: Tempo root owner-work admission, nested discovery owner
work, the 150k-span S3 top-k query, Sentry's 5000-occurrence S3 query, and
connected metrics-compactor peer startup. These are not closed reliability or
capacity findings, and no deadlines/limits were relaxed. All five passed in a
sequential rerun with their original deadlines (seed 288, 248.9 seconds, 88 other
tests excluded). That isolated result does not erase the full-suite failures or
establish concurrent reliability. Strict Credo checked 442 files without
findings; producer regeneration, final frozen converter replay and whitespace
checks passed. Temporary probe sources were removed; verification logs remain
under `.amp/in/artifacts/loki-byte-diagnostics-*`.

These are converter and Pulse HTTP/storage checks, not upstream Loki engine or
provider/deployed-client/capacity acceptance. Numeric conversion diagnostics
and complete parser errors remain open. Work remains local and unpushed.

### Timeout investigation before further compatibility work

Paused compatibility changes to investigate the five failures above without
raising query deadlines, ExUnit timeouts, peer RPC timeouts or resource limits.
Before any edits, the same five cases passed concurrently (seed 287,
max-cases 2, 67.4 seconds), and their five complete modules passed all 93 tests
(465.2 seconds). Those runs do not invalidate the original full-suite failures.

An ordinary five-way concurrent rerun reproduced the nested discovery test's
60-second timeout (seed 289; four passed, one failed). The alarm caught the
Elixir metadata decoder, but separate phase measurements showed the native
replay dominated: four native phases totaled 98.277 seconds, versus 7.525
seconds for the reference checks. A timeout stack alone was not a cost profile.
The test reopened one-row Parquet inputs 3000 times across four permutations.

Batching ten identical parents per source reduces those opens to 300 while
preserving every parent, event and attribute, both name/value queries and both
empty/one-attribute owner shapes. Every permutation still admits exactly two
million owner/attribute work units, rejects one extra parent in a separate
source, invalidates the native accumulator and checks the complete independent
Elixir reference. Cross-source work accumulation remains necessary to pass.
Measured native phases totaled 28.055 seconds after batching; reference phases
totaled 5.356 seconds. These are variable-host observations of test overhead,
not a production-query speedup or a guaranteed performance ratio.

After that test-only change, all five original failing cases passed in three
successive five-way concurrent runs with their original deadlines (seed 289;
82.6, 23.8 and 34.9 seconds; 88 unrelated tests excluded per run).

Before the full-suite control, the other four original timeouts had not
reproduced. In the complete-module diagnostic run, the 150k-span public queries
took 593, 2139 and 2797 ms; Sentry's 5000-occurrence query took 1712 ms, each
below its unchanged 10-second deadline. Separate peer lifecycle tracing
measured boot at 6040/5214 ms, application startup at 8153/5222 ms and maintenance
at 805 ms; the original 30-second application-start RPC failure is not evidence
of a compaction lock. The root-work test passed in both concurrent controls
without changes.

The full-suite control with only nested batching then passed 2166/2168 tests,
with one skipped and 37 excluded (seed 287, max-cases 2, 772.8 seconds). It
reproduced the root-work test's 120-second timeout and additionally timed out
Loki's quantity-threshold HTTP wrapper at 60 seconds. The other three original
failures did not recur. The root test now reuses one encoded fixture for its
1025-source control instead of encoding it 1025 times; every source admission
remains. An independent probe proved identical 5220-byte encodings, 1024 admitted
sources and rejection of source 1025, measuring 382 ms before reuse and 61 ms
after. That observation alone does not explain a 120-second whole-test timeout.

Host snapshots showed roughly 1900–2200 processes, hundreds runnable, over
12000 threads and substantial compressed memory. They also showed idle CPU;
these observations suggest environmental timing pressure but do not prove the
cause of the original failures. Sampled BEAM queues did not establish a
persistent scheduler backlog. The codec was release optimized.

A native sample during the full suite established a production scheduler
defect: one normal BEAM scheduler was inside S3 client construction and macOS
TLS trust-store reads/Security calls; another was waiting on the same global
client-cache mutex. Provider I/O was asynchronous, but cold client setup was
not. All request families now resolve clients inside the common asynchronous
dispatcher. Cache hits use a nonblocking lookup; cold construction and lock
waits use Tokio's blocking pool, not BEAM schedulers or Tokio event-loop workers.
Existing cache identity, single-client construction, conditional writes,
zero-copy binary ownership, native delete admission and mailbox replies remain.
There is no storage/keyed-byte/native-ABI change or deadline increase.

A real loopback-store probe checked 20 cold and 40 warm requests before and
after, validating every returned body. Cold NIF return times changed from
305546–821190 microseconds (median 512503) to 10–909 (median 15); warm medians
were 23 and 17 microseconds. These measure time before the NIF returns, not
end-to-end request/query latency. All nine focused cases (the original five,
the additional Loki timeout and three asynchronous object-store controls)
passed twice at max-cases 5 (seed 291, 21.4/15.5 seconds). Release compilation
with warnings-as-errors and all five native object-store tests passed.

The final full `mix test --max-cases 2 --seed 287 --warnings-as-errors` passed
all 2168 tests, with one skipped and 37 excluded, in 198.9 seconds. This includes
both modified discovery tests and the original public query/peer regressions.

No unrelated processes, query deadlines or admission limits changed. The host
became less loaded between full-suite controls, so a faster/green later run
cannot attribute every historical timeout to this scheduler defect. The three
unreproduced original query/peer timeouts retain that uncertainty; passing
reruns do not establish deployment capacity. Temporary probe sources were
removed; logs remain under `.amp/in/artifacts/timeout-investigation-*`.
Changes remain local, uncommitted and unpushed. No further compatibility gaps
were closed during this investigation.

### Loki numeric diagnostic continuation

Closed the remaining runtime numeric conversion-diagnostic gap after the timeout
investigation. Numeric filters and plain unwrap now expose complete original
values and Go `strconv.ParseFloat` syntax/range reasons. Syntax takes precedence
over an overflowing prefix. Quoting follows Go Unicode 17 printable characters,
named controls and lowercase fixed-width escapes, independently from duration's
byte-oriented quoting. The existing float/literal parsing API and values remain
unchanged. No storage/keyed-byte/native-ABI or resource-ceiling change.

The existing upstream typed-filter numeric row now asserts its original exact
diagnostic. One new HTTP/S3 wrapper transcribes both invalid numeric extractor
rows, retaining source ownership, grouping and errors; both already passed
before implementation. Two local wrappers replay all nine Go float64 error
rows, Loki's `not_a_number`, and 38 separately marked local controls. The frozen
48-row fixture is produced by the actual Go converter using AST-extracted
upstream inputs, not Pulse. Normal replay requires no Go or network. Selected
source links, hashes, licenses and adaptations are in the
[fixture continuation](../test/fixtures/logs/loki-upstream/README.md#numeric-diagnostic-continuation).

The strengthened typed-filter wrapper and both new diagnostic wrappers failed
before production edits (seed 288). All four then passed (seed 290), through
authenticated GET/form POST, native Parquet and real S3 HTTP against owned
stores. They cover exact-detail selection, syntax/range and malformed-overflow
precedence, Unicode/control escaping, missing/empty unwrap behavior, explicitly
preserved zero-valued errors, unpreserved fail-whole metrics, first-error policy
and work rejection. Existing memory/native-capable controls now require exact
numeric errors. The focused LogQL/float-parser/controller run passed 260 tests
(seed 289).

A temporary differential comparison matched 1,177,600 complete error strings
against Go 1.27.3: all Unicode scalars prefixed with `x` and all two-byte strings
prefixed with `x`, including invalid UTF-8 outside the HTTP JSON claim. Both
hashes were `aae8e85270e175bc1eddb1f6e6636fd0b63ad19eabd07e5ab4d52dd4350aec11`.
Another 2,200 numeric cases matched 159 valid float64 bit patterns and 2,041
complete errors. Full-scalar classification exposed 4,803 Unicode 17 printable
additions missing from PCRE2's Unicode 16 categories; the diagnostic formatter
includes them. Fixture regeneration matched byte-for-byte. Strict Credo checked
442 files without findings. This is not general numerical, upstream engine,
provider/client or capacity acceptance. Complete parser errors and other
quoted/raw string escapes remained open at this stage. Upgrade query-serving
applications and replace selectors matching former Pulse-specific numeric errors.

Full `mix precommit --seed 292 --max-cases 2` passed **2171 tests, 1 skipped,
37 excluded** in 216.2 seconds, including Mimir/Loki/Tempo ports. Formatting and
whitespace checks passed. Logs still contain three metrics-compaction timeout
warnings; this batch does not close those reliability findings. Review logs are
under `.amp/in/artifacts/loki-number-diagnostics-*`; temporary producer/probe
sources were removed. Changes remain local, uncommitted and unpushed.

### Loki string-literal compatibility

Closed quoted/raw literal decoding against Loki
`5aa4b9212d64d723f63b2770452054aa23df114d`, using its copied Scanner and vendored
Prometheus strutil decoder rather than installed Go Unquote. Named escapes,
exact hex/octal bytes and fixed-width Unicode now retain the original decoded
bytes. Single quotes, unknown/short escapes, octal >255, literal NUL, invalid
UTF-8 source and quoted LF reject. Quoted CR and raw CR/LF/backslashes survive.
Each escaped surrogate becomes one U+FFFD; a surrogate pair produces two.
Positive out-of-range Unicode rejects, while the pinned decoder's signed-int32
overflow in eight-digit U escapes yields its low byte. This deliberately
corrects the earlier Go-only surrogate-rejection assumption, not just its docs.
Query-serving applications must upgrade for the changed literals; former
single-quoted/permissive-regex queries need double quotes/doubled backslashes or
raw backticks. Storage/keyed bytes, native ABI and resource ceilings are unchanged.

One HTTP/S3 wrapper adapts three actual Loki lexer queries (token expectations
become selected lines/labels). Two more wrappers and parser replay cover all
35 Go `unquotetests` inputs, all 28 `misquoted` inputs and 41 marked local
controls. The expected bytes/rejections come from the actual Loki scanner and
decoder, not the Go table's different outcomes or Pulse. The frozen 104 rows
include 46 accepted literals and 58 rejections; invalid decoded byte strings
cannot alias UTF-8 `ÿ`. Both HTTP transports reject all 56 valid-source rejected
rows before provider reads; two invalid-UTF-8 sources are parser-only. The two
old permissive-regex corpus examples use raw quotes with unchanged regex values.
The fixture producer, source hashes, licenses, exact selections and adaptations
are in the [fixture continuation](../test/fixtures/logs/loki-upstream/README.md#string-literal-continuation).

Four of the five focused wrappers failed before runtime changes (seed293);
all five passed afterward (seed295). A separate temporary comparison matched
68,895 actual Loki scanner/decoder decisions: 66,846 accepted, 2,049 rejected,
including all 65,536 four-digit Unicode escapes plus byte/octal, eight-digit
Unicode boundary/overflow, source-byte, quote and malformed-suffix controls.
The full 454-test LogQL/Loki subset passed (seed294). Fixture regeneration was
byte-identical. This closes literal decoding, not exact parser-error wording/
positions, formatter parity, general LogQL, upstream service execution or
provider/deployed-client/capacity acceptance.

Full `mix precommit --seed 296 --max-cases 2` passed **2175 tests, 1 skipped,
37 excluded** in 313.5 seconds, including the Mimir/Loki/Tempo ports. Strict Credo
checked 442 files without findings. Formatting/whitespace checks passed.
Three metrics-compaction timeout warnings remain in the full-suite log; this
batch does not close those reliability findings. Review logs are under
`.amp/in/artifacts/loki-string-literals-*`. Work remains local, uncommitted and
unpushed.

### Loki IP-filter compatibility

Closed `ip(...)` line and label predicates against Loki
`5aa4b9212d64d723f63b2770452054aa23df114d`. Line `|=`/`!=` and label `=`/`!=`
accept strict IPv4/IPv6 addresses, host-bearing CIDRs and inclusive ascending
same-family ranges. Both scan embedded addresses with Loki's maximal-candidate
and delimiter-resume rules; mapped IPv6 remains distinct from IPv4. Missing
labels fail either operator; present empty values match negation. Prior errors
pass IP label predicates unchanged, without bypassing ordinary metric error
handling. Invalid patterns/operators fail before provider access. This replaces
the prior blanket IP rejection, not full LogQL or exact parser-error parity.

Two authenticated HTTP/Parquet/S3 wrappers retain all 15 original unit-table rows
from `pkg/logql/log/ip_test.go`: eight core cases (seven successful patterns and
all 43 input lines, one invalid range), three label-operator cases and four
line-operator cases. Both GET and form POST are exercised. Negative complements,
label equivalents and instant counts reuse the original inputs/expectations;
they are not counted as extra upstream rows. A separate local wrapper covers
line-format ordering, range counts, post-unwrap filters, compound predicates,
case-insensitive IP spelling and whitespace, family/scanner/zone boundaries,
absent/empty labels, prior errors and fail-whole work/log-sample/result limits.
The memory evaluator's existing rejection test
now checks actual selection and malformed-prefix rejection. Fixture provenance,
source/range hashes, attribution and reproducible AST extraction are recorded
in the [IP continuation](../test/fixtures/logs/loki-upstream/README.md#ip-filter-continuation).

All three new HTTP wrappers failed before runtime changes (seed297). After the
fix, the complete Loki/LogQL subset passed **457 tests** (seed300). A temporary
probe compared 745,807 actual pinned Loki matcher decisions, including 326
invalid patterns and 43,352 positive matches, with zero mismatches after fixing
CIDR-to-range fallback for IPv6 zone text containing `/`. It includes malformed
tokens, family/prefix boundaries, zones, long runs and generated addresses.
One local invalid-input assumption was corrected: `/` can be part of a valid
IPv6 zone, so such a single-address pattern is accepted but matches no zone-free
candidate. These are semantic tests/probes, not upstream service, real-provider,
deployed-client or representative-capacity acceptance.

IP predicates run in the bounded Elixir pipeline; the head-filter split stops
before them, preserving subsequent stage order rather than sending unsupported
values to native decoding. No upstream runtime is vendored into production.
Existing resource ceilings, native ABI, storage/keyed bytes and acknowledgement
semantics are unchanged. Upgrade query-serving applications; no native migration
or keyed-retry drain is required. Work remains local, uncommitted and unpushed.

Final `mix precommit --seed 304 --max-cases 2` passed **2178 tests, 1 skipped,
37 excluded** in 310.3 seconds, including Mimir/Loki/Tempo ports. Strict Credo
checked 443 files without findings; formatting and whitespace checks passed.
The final suite still emitted three metrics-compaction timeout warnings, one
withdrawn-worker warning and six Bandit acceptor `:noproc` errors. These remain
reliability diagnostics, not failures hidden by a compatibility claim or fixed
by this batch. Review logs are under `.amp/in/artifacts/loki-ip-filters-*`;
temporary upstream/probe sources and generated scratch data were removed.

### Loki line-filter OR compatibility

Closed `or` alternatives for substring, regex and pattern line filters against
Loki `5aa4b9212d64d723f63b2770452054aa23df114d`. Each operand inherits the primary
operator; string and IP operands can mix under `|=`/`!=`. Positive groups keep
any match, while negative groups reject any match. Adjacent filter groups remain
AND stages in authored order, including after line formatting. Every alternative
validates before storage, so unreachable malformed regex/IP/pattern operands
still fail. The keyword is case-insensitive with an identifier boundary.

Two authenticated HTTP/Parquet/S3 wrappers replay all 27 selected original
`Test_FilterMatcher` queries with 121 original line decisions and all 29 engine
evaluations from `line_filters.logqltest:178–280` (18 instant, 11 range;
26 successful, three rejected). Original queries, numeric results, sparse
samples, load/repeat geometry and source ranges are frozen. Matcher rows use
disjoint timestamp slices and order-independent equal-time multiplicities,
without changing existing order-sensitive helpers. A separate local wrapper
covers empty alternatives, adjacent groups, stage ordering, invalid later
branches, malformed tokens, expression admission and work/log-sample/result
ceilings. Invalid requests assert no provider access. These are upstream
unit/engine ports, not additional microservice suites or client/capacity proof.
Fixture regeneration is byte-identical; an independent Elixir source check
verified all queries, loads, decisions, expected labels/values and request
geometry. See [fixture provenance](../test/fixtures/logs/loki-upstream/README.md#line-filter-or-continuation).

All three wrappers failed before implementation (seed305), then passed
(seed307). The full Loki/LogQL subset passed **460 tests** (seed308).
`mix precommit --seed 309 --max-cases 2` passed **2181 tests, 1 skipped,
37 excluded** in 252.1 seconds, including the Mimir/Loki/Tempo ports. Strict
Credo checked 443 files without findings. Three metrics-compaction timeout
warnings and one withdrawn-worker warning remain; this batch does not close
those reliability diagnostics. Logs are under `.amp/in/artifacts/loki-line-or-*`.

Alternative groups run in the bounded Elixir pipeline without native pushdown;
no upstream runtime is vendored into production. Resource limits, storage/keyed
bytes and native ABI are unchanged. Upgrade query-serving applications; no
migration or keyed-retry drain is needed. Work remains local, uncommitted and
unpushed.

### Loki label-filter conjunction compatibility

Closed comma-separated and implicit label-filter conjunctions against Loki
`5aa4b9212d64d723f63b2770452054aa23df114d`, including case-insensitive `AND`/`OR`.
Explicit AND retains precedence over OR; comma/implicit conjunctions follow the
pinned yacc parser's right attachment (`a,b or c` means `a AND (b OR c)`).
Parentheses and pipe boundaries remain explicit. Existing AST evaluation keeps
eager conjunctions, short-circuit OR, first-error ownership and native fallback
rules; no new runtime evaluator, format, ABI or resource allowance is added.

One authenticated GET/form-POST HTTP/Parquet/S3 wrapper preserves all 36
evaluations from `label_filters.logqltest:902–1039,1181–1196`: five original
fixtures, 15 loads, 28 instant/eight range queries, 27 successful/nine rejected.
Original queries, metadata, repeat geometry, expected labels/numeric strings
and sparse samples remain frozen. Fixture anchors 300 seconds apart prevent
cross-fixture selector contamination without changing upstream queries.
Metric failures retain Pulse's generic error envelope; supplementary raw-log
queries inspect upstream error categories and diagnostic substrings, normalizing
only script-escaped quotes. This does not close exact metric-error text parity.

A separate local HTTP wrapper checks all three-predicate truth assignments for
mixed conjunction forms/OR, uppercase keywords, parentheses, no-whitespace
adjacency and pipe boundaries; eager error propagation, invalid regex/IP
branches, malformed commas, AST admission and work/log-sample/result limits.
Invalid queries require no provider access. Both wrappers failed before the
parser change (seed310), then passed (seed313); the Loki/LogQL subset passed
462 tests (seed314). Strict Credo checked 443 files without findings.

Full `mix precommit --seed 315 --max-cases 2` passed **2183 tests, 1 skipped,
37 excluded** in 172.5 seconds, including Mimir/Loki/Tempo ports. Formatting
and whitespace checks passed. Three metrics-compaction timeout warnings and
one withdrawn-worker warning remain; this parser batch does not fix them.
Validation logs are retained under `.amp/in/artifacts/loki-label-boolean-*`.

Fixture regeneration is byte-identical. A separate Elixir check verified every
source query, range, load, metadata field, expected label/sample and rejection
substring. A temporary interpreter of the pinned generated yacc tables compared
256 four-predicate mixed-operator/parenthesis expressions and all 4096 Boolean
decisions with Pulse. That is parser-table validation, not execution of Loki's
engine. The attributed standard-library Elixir extractor is retained; runtime
sources are not vendored. See [fixture provenance](../test/fixtures/logs/loki-upstream/README.md#label-filter-conjunction-continuation).
These are upstream engine-script ports and local controls, not additional
microservice suites or deployed-client/provider/capacity acceptance. Upgrade
query-serving apps; native/storage/keyed bytes and budgets are unchanged.
Work remains local, uncommitted and unpushed.

### Loki logfmt decoding compatibility

Closed ignored `--strict`, malformed-token recovery, empty-value retention,
normalized extract-all keys/first retained duplicates, quoted escapes and
Unicode/surrogate log-line decoding. Strict mode keeps preceding fields and
publishes `LogfmtParserErr` with exact one-based byte positions. Non-strict mode
discards malformed pairs and resumes; bare keys/empty values need `--keep-empty`
outside explicit field extraction. Quoted values accept JSON-style escapes plus
escaped apostrophes; replacement runes become spaces. Existing stream/structured
metadata collision ownership and explicit-field lookup/duplicate policy remain
unchanged, not claimed as full Loki expression-extractor parity.

Two authenticated HTTP/native-Parquet/loopback-S3 wrappers preserve **60 selected
upstream evaluations** at Loki `5aa4b9212d64d723f63b2770452054aa23df114d`:
the first 19 parser table rows in both strict modes, all four keep-empty rows in
both modes, and all 14 instant/range/rejected/empty evaluations from four complete
engine fixtures. Original lines, labels, byte-position details, eight loads/28
entries, noise, metadata, relative times and sparse slots remain. Unit rows gain
only a local selector label; nil becomes an empty binary. Metrics keep Pulse's
generic failure envelope and separately prove the original error type via log
reads. See [fixture provenance](../test/fixtures/logs/loki-upstream/README.md#logfmt-decoding-continuation).

The attributed AGPL standard-library Go extractor preserves exact source
selections, hashes and explicit omissions. Byte-identical regeneration and an
independent Elixir source reader checked the artifact. Normal replay needs no
Go, downloads or Loki process; no upstream runtime is shipped. A separate
temporary executable of the actual pinned Loki decoder matched **10,578**
strict/non-strict evaluations against Pulse, including controls, malformed UTF-8,
Unicode escapes/surrogates, quote adjacency and recovery. All **879** ASCII
inputs without Unicode escapes also answered natively with exact expected
labels and packed samples. A separate check preserved existing explicit-field
lookup/duplicate behavior. This is decoder validation, not full Loki engine
or deployed-client acceptance.

A local HTTP regression failed before the implementation (seed316), then the
three tagged HTTP checks passed (seed318); the broader Loki/LogQL suite passed
**466 tests** (seed319). One native/reference regression checks independently
derived sums/counts and asserts native execution; Unicode falls back rather
than diverging. A separate HTTP control exercises Unicode, errors, recovery and
unchanged work/retained-sample/result limits.

Combined `mix precommit --max-cases 2 --seed 321 --warnings-as-errors` passed
**2187 tests**, with one existing skip and 37 opt-in exclusions, in 360.7s.
Strict compilation, dependency/format checks, strict Credo (443 files), all
133 release codec tests, all-target Clippy and Rust formatting pass. A Credo
complexity finding was resolved by a fixed escape table; strict compilation
then caught an insufficiently narrowed optional lookup, corrected with an
explicit successful lookup match. No diagnostic was suppressed or ceiling
raised. Final decoder/native probes passed again after these corrections.
Final HTTP replay passed all three tagged checks (seed322), including exact
unterminated/invalid-quote byte positions; all 52 native/pipeline checks passed
(seed323), and strict Credo remained clean. Temporary runtime/probe sources were
removed; validation logs remain under `.amp/in/artifacts/loki-logfmt-*`.
The full-suite log retains three compaction timeouts, withdrawn-worker and
loopback acceptor teardown diagnostics; this batch does not establish their
cause, closure or capacity acceptance.

Require log tuple **`{1,1,6}`** on every query-serving app/native pair. Older
artifacts fail startup; storage formats, keyed bytes and resource ceilings are
unchanged. Structured-metadata/drop/re-added-label collision fixtures and hint
optimizations are explicitly excluded, not passing-by-omission claims. Full
LogQL/parser errors, expression-extractor parity and provider/client/capacity
acceptance remain open. Work remains local, uncommitted and unpushed.

### Loki explicit logfmt source expressions

Closed field-source grammar/admission, normalized lookup and absent-source
defaults. Invalid field expressions reject before storage, including after a
nonmatching line filter. Source names address normalized keys: a line key `a.b`
is selected as `a_b`. Inner quoted components follow the pinned separate field
lexer, not JSON paths or a second escape decoder. Missing values no longer
invent empty suffixed labels when the destination is an original stream name.
Explicit stages remain in the bounded Elixir path, without native pushdown.

One new authenticated HTTP/native-Parquet/S3 wrapper preserves **15 frozen
unit-table rows** at the existing Loki pin: nine extraction rows, the constructor
failure and all five field-grammar rows. One original input gains Pulse's
ingest-promoted `detected_level`; it is separately asserted before comparing the
untouched source oracle, not silently discarded. The empty grammar row asserts
a nil path, not a nil error; rejection follows the actual pinned generated
parser. The metadata-conflict row remains an explicit omission. All three
original expression engine evaluations remain in the prior 60-case replay,
not counted again. See [provenance](../test/fixtures/logs/loki-upstream/README.md#logfmt-source-expression-continuation).

The retained Elixir-only producer verifies complete source hashes and stores
exact rows/ranges, labels, lines, fields, locations and omissions. Regeneration
is byte-identical. An independent Go AST reader verified every extraction
oracle; all 15 row hashes and the full-source/selection hashes matched. Ordinary
Elixir replay requires no Go, network or upstream process. No upstream runtime
implementation is shipped.

A temporary executable of the actual pinned lexer/generated parser matched
**1,536** composed expressions on acceptance and compiled source names, with
zero mismatches. This establishes the exercised grammar, not full extractor
execution or engine parity. A separate retained HTTP control discriminates
normalized collisions, digit/Unicode keys, missing stream fields, inner quoted
names, whitespace, EOF/NUL/bracket termination, literal backslashes and non-path
extra components. Invalid-source controls prove no provider reads through log
and metric GET/form endpoints, even after a nonmatching filter. Existing work,
retained-sample and result limits still fail whole.

Before the change, the local HTTP regression returned empty normalized-key
values and an invented empty suffix (seed324). The initial upstream-table replay
also exposed the `detected_level` ingest adaptation (seed325), which is now
explicitly asserted rather than changing the oracle. The combined current and
previous logfmt HTTP checks passed **5 tests** (seed328), and the broader
LogQL/Loki/controller replay passed **420 tests** (seed329). Strict Credo checked
443 files with no issues. Combined `mix precommit --max-cases 2 --seed 330
--warnings-as-errors` passed **2189 tests**, with one skip and 37 opt-in
exclusions, in 433.4 seconds. Final tagged HTTP replay passed both new checks
(seed331) after preserving the constructor case's original destination name.
The three compaction timeout warnings correspond to deliberately stalled
100/200/1000ms deadline tests in the metrics controller and metrics compactor
suites; the withdrawn-owner warning exercises the same explicit ownership
scenario. They are expected fault-injection diagnostics in this run, not failed
tests or evidence of a production timeout fix. Temporary source/probe files
were removed; validation logs remain under `.amp/in/artifacts/loki-expression-*`.

Shared structured-metadata/drop/repeated-parser ownership, explicit-field
duplicates/shared-source aliases/destination-key capture/replacement-rune values
and hint-driven early exits remain open. This does not establish full Loki,
provider-capacity or deployed-client acceptance. Upgrade query-serving
applications; codec tuples, native/storage/keyed formats and resource ceilings
are unchanged. Work remains local, uncommitted and unpushed.

### Loki explicit logfmt destinations and replacement values

Closed duplicate destination definitions, destination-key capture, ordered
source/destination overwrites and replacement-character value handling. Every
source expression validates before last-definition deduplication. Source remaps
take precedence over direct destination capture; line order decides the last
retained value. Explicit values containing a replacement character become empty
in full, while extract-all parsing still replaces individual characters with spaces.
These close the corresponding value/ordering gaps from the preceding continuation.

Two retained authenticated HTTP/native-Parquet/S3 checks add 19 source-derived
label controls in both strict modes and GET/form POST (**38 evaluations / 76
requests**), plus independently derived metric/error/admission controls. They
do not add or recount copied upstream table rows. A missing destination-only
value failed the new regression before the change (seed332). All 19 oracles
also matched actual pinned Loki `NewLogfmtExpressionParser` execution with its
real unhinted label builder. Both original expression-parser Go tests passed.
An additional **13,104** temporary actual-parser comparisons matched on ordered
values, swapped sources, duplicate destinations, normalized keys, malformed
input, recovery and strictness. No reference runtime is shipped or needed by
ordinary Elixir replay. See [provenance](../test/fixtures/logs/loki-upstream/README.md#logfmt-explicit-destinationvalue-continuation).

The broader Loki/LogQL/controller replay passed **470 tests** (seed334).
Combined `mix precommit --max-cases 2 --seed 335 --warnings-as-errors` passed
**2191 tests**, with one existing skip and 37 opt-in exclusions, in 191.2s.
Strict Credo checked 443 files without issues after flattening one nested
reduction; no check was suppressed. Final combined logfmt HTTP replay passed
all **seven tests** (seed336). The three compaction timeout warnings still
correspond to deliberate 100/200/1000ms deadline/ownership tests, not failed
tests or a production timeout fix. Temporary probes were removed; validation
logs remain under `.amp/in/artifacts/loki-destination-*`.

At this continuation, shared-source aliases retained Pulse's all-aliases behavior
and shared collision ownership remained open. The following ownership increment
supersedes those exclusions. No tuple, native,
storage/keyed-format or ceiling changes; upgrade query-serving applications.
This does not establish full Loki, provider capacity or deployed-client
acceptance. Work remains local, uncommitted and unpushed.

### Loki parser label ownership

Closed stream/metadata collision ownership, release of dropped/renamed stream
names, first-extraction history across ordinary parsers and drops, and explicit
logfmt suffix-history halting before later strict errors. Explicit JSON retains
its overwrite behavior. Shared-source logfmt aliases now select one lexical
destination, a deterministic member of upstream's map-dependent possible outcomes,
not exact nondeterministic choice parity. Native logfmt/regexp share the same
ownership rules; no storage/keyed encoder bytes or resource ceilings change.
Every query-serving app/native pair requires the new log tuple `{1,1,7}`.

Thirteen previously omitted upstream evaluations preserve all table/engine
expectations through authenticated GET/form POST, native Parquet and S3, including
categorized selects and noise. Additional retained controls distinguish repeated
parsers after line rewrites/drops, explicit JSON overwrites, alias choice and
strict-error halting. Native/reference controls check metadata-owner transfers.
An additional **1512** actual pinned pipeline comparisons matched labels,
categories and output lines; selected upstream Go parser/label tests passed.
The attributed producer regenerated the fixture byte-identically. See
[provenance](../test/fixtures/logs/loki-upstream/README.md#logfmt-ownership-continuation).

The broader Loki/LogQL replay passed **476 tests** (seed339). Combined
`mix precommit --max-cases 2 --seed 340 --warnings-as-errors` passed **2197 tests**,
with one existing skip and 37 opt-in exclusions, in 195.8s. Strict Credo checked
443 source files cleanly. Compaction timeout warnings remain deliberate deadline
tests, not a production timeout diagnosis. Evidence is retained under
`.amp/in/artifacts/loki-ownership-*`. Broader JSON grammar/source-order/flattening,
hint-driven early exits and full client/provider/capacity acceptance remain open.

### Loki plain JSON parsing

Closed ordered nested-object scalar flattening, first duplicate/sanitized-target
ownership, null/array omission, original exponent/large-integer/signed-zero text
and replacement-character string values. Plain parsing now reports JSON errors
to the existing bounded pipeline/error-preservation machinery. Missing explicit
sources preserve existing destinations; present nulls still extract empty values.
This does not establish complete malformed-input partial extraction/diagnostics,
explicit JSON path grammar or hint-driven early exits. Native pushdown, the log
tuple, stored/keyed bytes and existing resource ceilings remain unchanged.

The complete 16-row upstream parser table plus seven engine fixtures preserve
all 42 evaluations, 20 load rows/38 entries, noise, metadata, sparse samples,
eight failures and one categorized select through authenticated GET/form POST
and native Parquet/S3: **58 evaluations / 116 requests**. Hint/path bookkeeping
is inert provenance; the hinted row checks its public output without hints.
The stream-level fixture separately asserts the receiver's promoted
`detected_level`; original result labels are unchanged. The attributed producer
regenerated byte-identically. Another **1216** actual pinned pipeline comparisons
agree; retained controls distinguish numeric spellings, collisions, unwrap and
absent versus null explicit sources.

The regression failed before implementation (seed341) and again when OTP's
number callbacks normalized numeric spelling; token-preserving decoding fixed
the mismatch without changing its oracle. All tagged checks pass (seed346);
the broader Loki/LogQL replay passes **479 tests** (seed347). Full
`mix precommit --max-cases 2 --seed 348 --warnings-as-errors` passes **2200 tests**,
with one existing skip and 37 opt-in exclusions, in 308.8s. Artifacts are under
`.amp/in/artifacts/loki-json-*`. Compaction timeout warnings are deliberate
deadline controls, not failed tests or a production-readiness claim.

### Loki explicit JSON paths

Closed dot/bracket/UTF-8 field keys, root/nested nonnegative int64 array indices,
pre-storage path admission, source-order duplicate destinations and missing/null
destination ownership. Selected objects preserve raw source bytes and arrays
unescape once; numbers retain their original lexemes. Expressions compile once
in the existing bounded Elixir path. This supersedes the plain-JSON checkpoint's
open explicit-path item, not general malformed-input diagnostics or hint parity.
No additional native tuple, stored/keyed-byte or resource-ceiling change applies.

The complete pinned tables preserve 29 expression rows, five constructor
failures, 18 grammar rows and five engine evaluations: **57 source
rows/evaluations, 56 executable oracles**. The empty grammar row has no upstream
error assertion and remains provenance. Engine queries replay through
authenticated GET/form POST and native Parquet/S3 without changing sparse
samples. Constructor failures use Pulse's existing admission envelope rather
than copying upstream text. The attributed producer regenerated byte-identically.
Another **3072 actual pinned Loki pipeline comparisons** agree, including
ownership, duplicates, numeric text, arrays, escapes and source ordering.

All three new upstream wrappers failed before implementation (seed350).
The broader Loki/LogQL replay now passes **483 tests** (seed353). Full precommit
passes **2204 tests**, with one existing skip and 37 opt-in exclusions, in 248.0s
(seed354). Evidence is in `.amp/in/artifacts/loki-json-expressions-*`.

### Loki interval, entry and selector request policies

Closed request-local `maxQueryInterval`, `maxEntriesLimitPerQuery`,
`requiredLabels` and `minimumLabelsNumber`. Interval checks visit every metric
range leaf; entry ceilings reject excessive log `limit` or field `line_limit`
rather than truncating results. Selector requirements visit each branch
independently and include detected fields/values and patterns. Required names
are deduplicated; counts include repeated matcher names, not pipeline/group
labels. Parenthesized log pipelines before range brackets now parse too.
Existing header bounds, fail-closed parsing and server budgets remain unchanged.
No new native tuple, storage/keyed bytes or configuration applies; upgrade
query-serving applications before relying on these additional client policies.

All 25 selected pinned engine/middleware admission cases retain their queries
and decisions through **64 HTTP GET/form-POST requests**. Downstream topology,
synthetic engine input logs and canned middleware sample responses are not
sample-value or provider-layout oracles. Three separate controls exercise actual
nonempty Parquet/S3 values, boundaries, defaults, duplicates, offsets, invalid
headers, request isolation and provider counters unchanged on rejection.
Upstream engine and middleware tests were also executed successfully offline.
Exact interval error units use nanoseconds, not upstream duration formatting.

The baseline reproduced unsupported-header failures and a parenthesized-source
parse error (seed355); all three selector-policy checks also failed before their
implementation (seed359). All eight tagged checks now pass (seed360), and the
broader Loki/LogQL/WebSocket suite passes **491 tests** (seed361). Evidence is in
`.amp/in/artifacts/loki-query-policies-*` and `loki-selector-policies-before.log`.
Full precommit passes **2212 tests**, with one skip and 37 opt-in exclusions,
in 175.7s (seed362).

### Loki request execution deadlines

Closed `maxQueryTime` for all finite Loki reads: positive client timeouts shorten
the existing worker deadline, while absent/zero/higher values preserve the
server cap. Discovery, metadata statistics, both volume paths, detected fields
and patterns carry the owned request option through to their admitted worker.
No mutable global policy, resource-ceiling increase, native tuple or stored/keyed
byte change is introduced. Already-dispatched native/provider work may finish
after timeout; HTTP parsing/encoding and provider cancellation are not covered.

The pinned Loki limiter's defaults, lower-limit and higher-limit tests pass
offline. Three local HTTP controls cover 30 blocked-adapter GET/form requests
across all 15 finite shapes, worker/admission recovery, absent/empty/zero/higher
limits, and an actual blocked native S3 GET followed by nonempty reads.
Shorter millisecond deadlines preserve the upstream minimum-positive rule,
not its exact 30s/29s/100s geometry; the unsupported zero-server-timeout mode is
not imported. The baseline reproduced unsupported-header rejection (seed363);
all three controls pass (seed365). Evidence is in
`.amp/in/artifacts/loki-query-deadline-*`.

### Loki range bracket and parenthesis placement

Closed pipeline-after-bracket/offset and recursive whole-range parentheses.
The parser preserves pipeline/unwrap order and rejects split pipelines, parser
stages after wrapped-selector brackets and invalid post-unwrap stages before
storage. Existing input/AST/depth limits remain, including the inclusive
64-parenthesis boundary. No native/storage/keyed-byte change is required.

Seventeen original first/last engine oracles replay in six equivalent placements
through **204 HTTP GET/form requests**, retaining original input geometry,
offsets, sparse windows and NaNs. Additional controls cover post-unwrap filters,
quantile/distinct parameters, grouping and depth/admission boundaries. Both
tagged checks failed before the parser change (seed367) and pass afterward
(seed370). All **336 actual pinned Loki parser comparisons** agree (90 accepted,
246 rejected), and upstream `TestParse` passes offline. The broader Loki suite
passes **495 tests** (seed369). Evidence is in
`.amp/in/artifacts/loki-range-placement-*`.

### Loki metric label replacement

Closed `label_replace` for instant and range metric expressions, using final
stream/metadata/parser labels, complete-value regex matching and Go-style capture
expansion. Missing sources read as empty; nonmatches leave labels unchanged;
empty replacements delete the destination. Loki's non-dot-all default and
nonaggregating rewrites remain distinct from PromQL. All nested selector/range
policies and instant-only `approx_topk` admission still apply before reads.
Existing query budgets, native tuples and storage/keyed bytes are unchanged.

All **19 evaluations** in the complete pinned `functions.logqltest:24–132` block
retain their 64 original entries, relative times, noise, labels and value oracles
through **38 HTTP GET/form requests** and actual Parquet/S3. Five retained tests
also cover newlines/flags, named/braced captures, nested replacements, instant
collisions and pre-storage policy rejection. The original four checks failed
before implementation (seed371); all five pass afterward (seed373). The actual
upstream `TestLogQLScripts/functions.logqltest` engine suite also passes offline.
Evidence is in `.amp/in/artifacts/loki-label-replace-*`. This closes the function,
not general parser-error wording, distributed or deployed-client acceptance.

### Regexp, pattern and unpack continuation

All 30 evaluations in the complete pinned `parsers.logqltest:304–446` block
retain their 66 original entries through 60 HTTP GET/form requests and actual
Parquet/S3. Regexp requires named captures; pattern validates duplicates and
adjacency and retains short-line captures; unpack requires string `_entry`,
publishes only string fields and preserves ordered duplicate/ownership behavior.
Six regexp and eleven pattern constructor rows, nine unhinted unpack rows and
separate controls extend the same HTTP suite without a Go replay dependency.

Four engine regressions failed before implementation (seed375); all 12 retained
tests pass afterward (seed377). The broad Loki/LogQL/WebSocket suite passes
512 tests with warnings-as-errors (seed378). Actual pinned engine/unit suites
pass offline, and 528 generated runtime comparisons agree on line, flat labels
and categories. Evidence is in `.amp/in/artifacts/loki-remaining-parsers-*`.
Full malformed-input diagnostics/partial extraction and internal hints remain
open; native/storage/keyed bytes and resource ceilings are unchanged.

### Label formatter assignment continuation

The complete three-row upstream formatter validation table and four basic
assignment rows replay through HTTP/Parquet/S3. Duplicate and `__error__`
destinations reject before reads; renames execute in order, self-renames delete
their source, and templates share the first-template snapshot within a stage.
The earlier local self-rename assertion was contradicted by the actual pinned
runtime and has been corrected. Missing-source, cross-owner, later-parser and
chained-stage controls cover the distinction between live renames and snapshots.

Both new retained tests fail before implementation (seed380) and pass afterward
(seed381); the broad Loki/LogQL/WebSocket suite passes 514 tests (seed382).
Actual pinned formatter validation/execution unit suites pass offline. A later
Unicode-prefix control reproduced byte/grapheme slicing errors in line/label
templates; byte slicing fixes them. Another 723 generated actual runtime
comparisons agree on line, labels and categories, including Unicode and empty
snapshot controls. Evidence is in
`.amp/in/artifacts/loki-label-format-*`. No native/storage/keyed bytes or resource
ceilings change. Full Go-template functions/control flow/error behavior and
pipeline-error ownership remain open, not implied by assignment coverage.

### Combined continuation validation checkpoint

`mix precommit --seed 385` passes **2,235 tests, one skipped and 37 excluded**
in 132.5 seconds, including strict compilation, unused-dependency and formatting
checks. Strict Credo reports no issues across 445 files. The earlier full runs
also pass: 2,233 tests before formatter assignments (seed379), and 2,235 before
the Unicode-prefix correction (seed383). An intermediate strict compile caught
a missing Elixir bitstring-size pin; it is corrected, not suppressed.

The deadline, range-placement, label-replacement, remaining-parser and formatter
increments share this final application suite. Their retained HTTP regressions
use owned loopback S3/Parquet stores, not deployed clients or a provider capacity
run. Logs retain compaction timeout/conflict and CAS diagnostics; passing test
assertions do not close operational or representative-capacity gates. This
checkpoint adds no native ABI/storage/keyed-encoding change and does not replace
earlier native-crate validation. Final evidence is in
`.amp/in/artifacts/compatibility-continuation-unicode-*`. Work remains local,
uncommitted and unpushed; no deployment or migration was performed.

### String template function continuation

The formatter gap now excludes the implemented deterministic string slice:
15 function names including legacy aliases, simple Go Unicode casing,
trim/prefix/suffix operations and predicates, defaulting and current-line access.
Function pipelines append the prior value as the last argument; parenthesized
expressions, UTF-8 string literals and booleans are supported. Unknown functions,
unclosed actions and unsupported syntax reject before storage instead of being
silently ignored. Argument failures publish TemplateFormatErr, preserve input
lines/destinations and honor existing metric error-selection policy.

Four retained HTTP tests port 18 pinned engine evaluations plus six original
formatter rows through GET/form-POST/Parquet/S3. Source ranges, hashes, explicit
ingress/tenant adaptations and remaining omissions are recorded in the Loki
fixture README. Ten extra string controls and runtime/admission controls are
separate from the original source count. A fifth test checks the 16 MiB output
boundary and one-byte overflow through materialized, top-k and metric evaluation;
overflow fails whole even when errors are explicitly selected. Nesting caps at
64 parentheses. These are application-only bounds, not provider-capacity proof.

Actual pinned formatter unit suites and the complete formatter engine script
pass offline. All 1,888 generated runtime comparisons agree, covering every
Unicode scalar value under upper/lower and stream/metadata/parsed ownership,
excluding exact diagnostic text. The broad application selection passes 425
tests (seed390). Full
`mix precommit --seed 391` passes **2,240 tests, one skipped and 37 excluded**
in 129.3 seconds, including warnings-as-errors compilation, dependency and format
checks. Strict Credo reports no issues across 445 files. Evidence lives in
`.amp/in/artifacts/loki-template-functions-*`; compaction timeout/conflict and CAS
diagnostics remain visible, not suppressed.

The `now()` engine rows are still omitted. Other functions, control flow,
variables, field chains, numeric/rune constants, trim markers/comments,
non-UTF-8 byte literals and exact diagnostics/error ownership remain open.
Non-UTF-8 template literals reject explicitly until downstream byte-string
semantics are implemented. Upgrade query-serving apps; no native/storage/keyed
byte change is required. Work remains local, uncommitted and unpushed.

### String transformation continuation

Nine more formatter function names are covered: `replace`, `title`, `trimAll`,
legacy `Trim`/`TrimLeft`/`TrimRight`, `urlencode`, `urldecode` and `b64enc`.
Trimming uses Unicode scalar cutsets; empty literal replacements split scalars,
not graphemes. Title casing follows Go's historical ASCII-punctuation and Unicode
space rules while preserving noninitial letters. URL operations use query-form
escaping, with malformed escapes producing preservable formatting errors.
Decoded non-UTF-8 values deliberately remain formatting errors until downstream
consumers support byte strings. Base64 encoding is standard and padded.

Eight original formatter rows from the pinned Loki unit tables now replay through
authenticated GET/form POST and native Parquet/S3, with explicit timestamp,
isolation and diagnostic adaptations. This brings the two string-template
continuations to 32 source evaluations, not full formatter acceptance. Nine
additional successful controls and seven extra failure templates are separate
from the source count. Three retained tests cover this increment, including
exact 16 MiB output and one-added-source-byte rejection for replacement and
both encoders. Expanding functions enforce intermediate limits before allocation;
a later trim or explicit error retention cannot hide amplification. Native,
storage, keyed bytes and configured resource ceilings remain unchanged.

Actual pinned line/label formatter unit suites pass offline. All 2,096 additional
runtime comparisons agree on lines and label categories, excluding exact error
details and non-UTF-8 decoded values. The 272 Unicode batches cover all 1,112,064
scalar values in initial, noninitial and word-boundary contexts. The broad Loki
selection passes 428 tests (seed395). Full `mix precommit --seed 396` passes
**2,243 tests, one skipped and 37 excluded** in 261.4 seconds, including
warnings-as-errors compilation, dependency and formatter checks. Strict Credo
finds no issues across 445 files. The final three targeted tests pass again
(seed397). Compaction timeout/conflict, CAS and oversized-URI fault diagnostics
remain visible, not suppressed. Fixture source ranges/hashes, adaptations and
remaining omissions are in the Loki fixture README; evidence is in
`.amp/in/artifacts/loki-template-transforms-*`.

Base64 decoding, legacy counted `Replace`, numeric/rune constants, regex/date/math
functions, control flow/variables, field chains, trim markers/comments, byte-string
semantics and exact diagnostics/error ownership remain open. This is not deployed
client, provider-capacity or full replacement acceptance. Upgrade query-serving
apps; work remains local, uncommitted and unpushed.

### Integer-argument template continuation

The formatter gap now excludes `repeat`, `indent`, `nindent`, `alignLeft`,
`alignRight` and legacy counted `Replace`, plus signed-int64 template literals.
Integer parsing accepts Go decimal/base-prefixed/legacy-octal/separator forms
with bounded accumulation, not an arbitrary bignum conversion. Float/complex/rune
constants still reject explicitly. String labels do not coerce to integer args;
zero is an empty value for `default`.

Six complete line-formatter rows at the pinned Loki revision replay through
authenticated GET/form POST and native Parquet/loopback S3. Line cases also run
as label-format controls, not additional source oracles. Source counts across
the three string-template continuations now total 38. Nine independent successful
controls distinguish Unicode scalars from bytes/graphemes, preserve empty/trailing
indentation lines, verify counted/empty-search replacement and cover signed-int64
boundaries and base/separator grammar. Eleven runtime-error templates retain
inputs and exercise metric error selection; malformed/out-of-bound constants
and deliberately unsupported constant types reject before provider reads.

A third retained test checks exact 16 MiB outputs and larger-output rejection
for all six function names through materialized/top-k/metric paths. Repetition,
indentation and alignment padding calculate full byte sizes before allocation;
counted replacement checks each added piece. Empty repeats with a maximum count
succeed; huge nonempty expansions fail whole rather than becoming preservable
formatting errors. Later trims and explicit error retention cannot hide them.
Native/storage/keyed bytes and configured resource ceilings are unchanged.

The replacement-helper refactor passed all eight existing string-template tests
before new functions were exposed (seed398). All three new tests failed on the
unsupported baseline (seed399). The broad Loki/LogQL selection then passed 525
tests (seed401). All 6,156 additional actual pinned pipeline comparisons match
lines, keep decisions, flattened labels and stream/metadata/parsed categories;
only exact error details are excluded. Both complete actual pinned formatter
unit suites pass offline. Source ranges/hashes, adaptations and remaining
omissions are in the Loki fixture README; evidence is in
`.amp/in/artifacts/loki-template-integers-*`.

Full `mix precommit` passed 2,246 tests with one skip and 37 opt-in exclusions
twice (seeds402/403, 120.8/150.8 seconds). The final run includes the small
structure changes requested by strict Credo; Credo then checked all 445 files
without findings. Final actual pinned runtime comparisons again matched all
6,156 cases. Compilation with warnings-as-errors, unused-dependency, formatting
and whitespace checks passed. Compaction timeout/conflict, CAS, deliberate
gRPC-handler crash and oversized-URI fault diagnostics remain visible; no
failing check was suppressed. Temporary comparison tooling was removed.

Base64 decoding, regex/date/math and other functions, control flow/variables,
field chains, float/complex/rune constants, trim markers/comments, byte-string
semantics and exact diagnostics/error ownership remain open. This does not close
provider/deployed-client/capacity acceptance. Upgrade query-serving apps; work
remains local, uncommitted and unpushed.

### Base64 decoding and public byte-slicing continuation

The formatter gap now excludes `b64dec`, `trunc` and `substr` for UTF-8 results.
The pinned public function map installs Sprig's byte-based slicing functions,
not Loki's unused rune-based helpers. Bounds, negative counts and oversized ends
follow that actual runtime; invalid bounds attach `TemplateFormatErr` rather than
being clamped. Base64 padding uses original byte length before Go ignores CR/LF.
Malformed Base64 returns ordinary diagnostic strings with Go byte offsets and
discards partially decoded data, instead of raising a template error.

Five complete upstream formatter rows replay through authenticated GET/form
POST and native Parquet/loopback S3, bringing the four string-template
continuations to 43 source evaluations. Independent controls cover byte/rune
boundaries, signed-int64 extremes, Unicode/NUL, noncanonical padding bits,
CR/LF and corrupt inputs. Runtime bounds/type/arity errors preserve inputs and
exercise metric error rejection/retention/exclusion. Decoded/sliced non-UTF-8
results deliberately attach formatting errors until byte-aware downstream
handling exists, even when a later encoding could restore UTF-8.

Both new retained tests fail before implementation (seed404) and pass after
(seed405). Both complete pinned formatter unit suites pass offline. Another
32,792 actual pinned pipeline comparisons match line/keep/flattened labels and
all three label categories, excluding only exact runtime template error details;
3,308 exercise errors. Separately, 1,364 non-UTF-8 cases validate Pulse's deliberate
stricter rejection, not parity. Scratch validation confirms an exact 16 MiB
decoded result, one-byte-over rejection and shrinking slices of oversized input.
Source mapping, hashes and adaptations are in the Loki fixture README; evidence
is under `.amp/in/artifacts/loki-template-decode-*`.

The broad Loki/LogQL selection passes 496 tests (seed406). Full `mix precommit`
passes **2,248 tests, one skipped and 37 opt-in exclusions** (seed407, 189.4s),
including Mimir/Loki/Tempo replay, warnings-as-errors compilation, unused-dependency
and formatter checks. Strict Credo checks 445 files without findings after
removing a redundant negative-end guard; all 32,792 comparisons and 1,364
deliberate UTF-8 fences pass again after that simplification. Existing compaction
timeout/conflict, CAS and oversized-URI fault diagnostics remain visible, not
suppressed. Whitespace checks pass and temporary comparison tooling is removed.

No native/storage/keyed bytes or resource ceilings change. Upgrade query-serving
applications. Other template functions, control flow/variables, field chains,
float/complex/rune constants, trim markers/comments, byte-string semantics and
exact template diagnostics/error ownership remain open. This is not upstream
service execution or provider/deployed-client/capacity acceptance; work remains
local, uncommitted and unpushed.

### Conditional and logical template continuation

The formatter gap now excludes bounded `if`/`else if`/`else`, lazy operand-valued
`and`/`or`, `not`, typed equality/ordering and byte `len`. Empty strings, false
and integer zero are false; nonempty `"0"` is true. Logical arguments short-circuit,
but earlier pipeline commands execute eagerly, as do equality argument
expressions. Variadic equality stops comparing after its first match. String
ordering and length use bytes. All branches compile before storage, while only
selected branches execute under the shared 16 MiB output cap and combined
64 conditional/parenthesis depth. Unknown functions cannot hide in dead branches;
output overflow still fails whole rather than becoming a preservable error.

Three complete pinned conditional-predicate rows replay through authenticated
GET/form POST and native Parquet/loopback S3, bringing the formatter total to 46
source evaluations. Seventeen independent success controls, thirteen runtime
failure templates and thirteen admission/depth rejections cover both formatting
stages. A public evaluator regression exercises exact-cap/overflow across nested
branches, skipped over-cap expressions and a condition that expands beyond the
cap, including top-k/metric/error-selection paths.

Another **32,298** actual pinned parser/pipeline comparisons agree across both
formatters and stream/metadata/parsed ownership: 32,148 admitted (10,260 runtime
errors) and 150 rejected. Only exact runtime diagnostic details are excluded.
These are real upstream runtime oracles, not values inferred from Pulse.
Both complete pinned formatter suites pass offline. The prior six formatter
tests pass after the behavior-preserving rendering/command extraction (seed408).
Both new HTTP tests fail before implementation (seed409), then all three
conditional/budget tests pass (seed410). Broader LogQL/Loki coverage passes
426 tests (seed411); strict Credo checks 445 files without findings.
Full `mix precommit` passes **2,251 tests, one skipped and 37 opt-in exclusions**
(seed412, 153.6s), including Mimir/Loki/Tempo replay, strict compilation,
unused-dependency and formatter checks. All three targeted tests pass again
after mixed-depth and long else-if boundary controls (seed413). Formatting and
whitespace checks pass; temporary comparison tooling is removed. Existing
deliberate compaction/CAS/URI fault diagnostics remain visible.
Fixture mapping, adaptations and hashes are in the Loki README; evidence is
under `.amp/in/artifacts/loki-template-conditionals-*`.

`with`/`range`, variables, field chains, float/complex/rune constants, other
functions, trim markers/comments, non-UTF-8 byte values and exact error
text/positions/ownership remain open. No native/storage/keyed bytes or ceilings
change; upgrade query-serving applications. This is not full formatter,
upstream-service, deployed-client, provider or capacity acceptance. Work remains
local, uncommitted and unpushed.

### Template whitespace and comment continuation

The formatter gap now excludes Go-style delimiter trimming and non-nesting
comments. Only adjacent literal ASCII space/tab/CR/LF trims, never Unicode
spaces or previously rendered values. Trim markers require their whitespace
byte and remain distinct from negative integers. Comments recognize the exact
opening/closing forms, ignore apparent actions and unknown functions, and end
at the first `*/`. Invalid comments and unsupported real actions still reject
before storage. Byte scans avoid unanchored regex backtracking; existing query
length/depth/output ceilings remain authoritative.

Fifteen original Go 1.27.3 lexer/parser rows replay through both HTTP formatters,
GET/form POST and native Parquet/loopback S3: thirteen successes and two invalid
comments. Go AST/token expectations adapt to rendered strings or admission
failures; these are underlying formatter oracles, not additional Loki source
rows. The prior Loki formatter total remains 46. Sixteen successful controls
and fourteen additional invalid inputs cover whitespace classes, negative
constants, lexical boundaries, comments/quoted delimiters and conditionals.
Runtime failures preserve line/destination and existing metric error policies.
A public evaluator regression preserves exact-cap 16 MiB rendered spaces and
rejects one extra byte across materialized/top-k/metric/error-selected paths;
commented expanding expressions never execute.

All **29,826** actual pinned Loki parser/pipeline comparisons agree across both
formatters and stream/metadata/parsed ownership, excluding exact runtime error
details: 12,120 admitted (1,260 runtime errors) and 17,706 rejected. The 15 Go
rows retain exact input strings with explicit AST/token-to-render adaptations
and BSD attribution. Both HTTP tests and the evaluator test fail before the
feature (seed414); all three pass after implementation and fixing one test's
outer LogQL newline escaping (seed417). Complete Go lexer/parser/error selections
and both complete pinned Loki formatter unit suites pass offline. Full
`mix precommit` passes **2,254 tests, one skipped and 37 opt-in exclusions**
(seed418, 177.8s), including Mimir/Loki/Tempo replay, strict compilation,
unused-dependency and formatter checks. Strict Credo checks 445 files without
findings. Formatting/whitespace checks pass; temporary comparison tooling is
removed. Existing deliberate compaction/CAS/URI fault diagnostics remain visible.
Fixture mapping/hashes and evidence are in the Loki README and
`.amp/in/artifacts/loki-template-whitespace-*`.

No native/storage/keyed bytes change; upgrade query-serving applications.
Variables, other control flow/functions, non-UTF-8 values and exact diagnostics
remain open. This does not establish full formatter, provider, deployed-client
or capacity acceptance. Work remains local, uncommitted and unpushed.

### Integer arithmetic template continuation

The formatter gap now excludes `int`, `add`, `sub`, `mul`, `div`, `mod`, `min`
and `max`. String/boolean conversion matches pinned Sprig/cast: exact decimal
truncation precedes base-zero parsing; invalid syntax and overflow return zero.
Arithmetic wraps signed64 after every operation, including variadic folds;
division truncates toward zero, remainder preserves numerator sign, and zero
divisors preserve inputs with `TemplateFormatErr`. Existing query/depth/output
limits remain unchanged, with no native/storage/keyed-byte change. Upgrade
query-serving applications.

Four complete pinned Loki formatter rows replay through authenticated GET/form
POST and native Parquet/loopback S3, bringing the function continuations to 50
source evaluations. Sixteen independent successful controls, twelve runtime
failures and five unsupported/admission cases exercise both formatting stages
and metric-error policies. A public evaluator regression checks arithmetic
expansion counts at exactly 16 MiB and one byte over, including top-k, metric
and explicit error selection. All three retained tests fail before arithmetic
(seed420) and pass afterward (seed421). The integer-parser grammar extraction
first passed nine existing conditional/whitespace/integer-function checks
unchanged (seed419).

All 20,826 additional actual pinned Loki parser/pipeline comparisons agree
across both formatters and stream/metadata/parsed owners, including 1,458
runtime formatting errors; exact error details are excluded. Both complete
actual pinned formatter unit suites pass offline. Source selections, hashes,
sentinel/label-replay adaptations and comparison coverage are recorded in the
Loki fixture README; evidence is under
`.amp/in/artifacts/loki-template-integer-math-*`.

Full `mix precommit` passes **2,257 tests, one skipped and 37 opt-in exclusions**
(seed422, 291.1s), including Mimir/Loki/Tempo replay, strict compilation,
unused-dependency and formatter checks. Strict Credo checks 445 files without
findings. Existing deliberate compaction/CAS/URI fault diagnostics remain
visible; no failing check was suppressed. Temporary comparison tooling is
removed; formatting and whitespace checks pass.

Floating-point math/constants, other control flow/functions, variables,
non-UTF-8 values and exact diagnostics remain open. This is not full formatter,
upstream-service, deployed-provider or capacity acceptance. Work remains local,
uncommitted and unpushed.

### Quantity template continuation

The formatter gap now excludes `bytes`, `duration` and `duration_seconds`.
They reuse the pinned runtime quantity converters and retain float64 results
through pipelines, rendering, truthiness, defaults and typed comparisons.
Duration conversion splits seconds/remainders before float conversion;
rendering uses Go's shortest-general float representation. Integer helpers
truncate in-range floats toward zero. Out-of-range float-to-integer casts
deliberately produce `TemplateFormatErr` instead of selecting Go's
implementation-dependent overflow value. Large byte quantities remain
renderable without integer conversion. Existing budgets and native/storage/
keyed bytes do not change; upgrade query-serving applications.

Four complete pinned Loki formatter rows retain their original templates,
fields, input and outputs through authenticated GET/form POST and native
Parquet/loopback S3. The seven function continuations now total 54 original
Loki evaluations. Twelve successful controls and eighteen runtime-failure
templates additionally exercise both stages, float type boundaries, lazy
branches, large/signed quantities and metric-error preservation. Two failure
templates enforce the deliberate stricter cast policy. Both retained tests
fail before implementation (seed423) and pass afterward (seed424).

Of 66,570 additional actual pinned Loki parser/pipeline comparisons, 66,438
agree exactly, excluding exact error-detail strings, including 4,254 upstream
runtime formatting errors. The other 132 deliberately reject nonportable
overflowing float-to-integer conversions; no unexpected differences remain.
Both complete pinned formatter unit suites pass offline. Source selections,
hashes, replay adaptations and comparison scope are recorded in the Loki
fixture README; evidence is under
`.amp/in/artifacts/loki-template-quantities-*`.

Final full `mix precommit` passes **2,259 tests, one skipped and 37 opt-in
exclusions** (seed426, 168.2s), including Mimir/Loki/Tempo replay, strict
compilation, unused-dependency and formatter checks. Strict Credo checks 445
files without findings. The final runtime comparison rerun has the same
totals. Existing deliberate compaction/CAS/URI fault diagnostics remain
visible; no failing check was suppressed. Temporary comparison tooling is
removed; formatting and whitespace checks pass.

General float math/constants, other functions/control flow, variables,
non-UTF-8 byte values and exact diagnostics remain open. This is not full
formatter, upstream-service, deployed-provider or capacity acceptance. Work
remains local, uncommitted and unpushed.

### Regex count template continuation

The formatter gap now excludes `count pattern text`. It returns typed integer
non-overlapping counts using the bounded native Go-style regex profile, with
Unicode-scalar empty-match progress, ASCII Perl classes/word boundaries,
strict end anchors and Unicode script properties. Invalid executed patterns
and argument failures preserve inputs with `TemplateFormatErr`; lazy branches
skip execution. No match/capture list is retained. Accepted matches plus one
final probe consume shared metric work or request-local log work across entries
and actions. Exhaustion fails whole with `query_work_limit`, including explicit
error selection. Query deadlines and existing resource ceilings still apply.
Upgrade query-serving app/native pairs to log tuple `{1,1,8}`; storage and
keyed encoder bytes are unchanged.

Four complete pinned Loki formatter rows retain original templates, inputs,
labels and count outputs through authenticated GET/form POST and native
Parquet/loopback S3. The eight function continuations total 58 original formatter
evaluations. The original invalid-count direct-function assertion adapts to a
template error separately. Fifteen successful controls and ten failure
templates cover both formatting stages, labels from all owners, typed integer
consumers, lazy branches and metric-error rejection/preservation. A public
evaluator regression checks work limits across actions, entries, materialized,
top-k, metric and error-selected paths. Another retained native/reference test
checks 1,380 randomized/control pairs and exact sufficient/insufficient work
boundaries. The reference corpus uses portable regex forms; separate actual
Loki controls cover multiline/script differences and adversarial backtracking.

All 29,952 actual pinned Loki parser/pipeline comparisons agree, including
3,120 runtime formatting errors, excluding exact error details. The matrix
checks line output and separate stream/metadata/parsed categories. Both
complete upstream formatter suites and `Test_InvalidRegex` pass offline.
Source selections, hashes and replay adaptations are recorded in the Loki
fixture README; evidence is under `.amp/in/artifacts/loki-template-count-*`.

All three initial regressions fail before implementation (seed427); all four
retained checks pass with native counting (seed430). Final full
`mix precommit --seed 432` passes **2,263 tests, one skipped and 37 opt-in
exclusions** in 170.7s, including Mimir/Loki/Tempo replay, strict compilation,
unused-dependency and formatting checks. Strict Credo checks 445 files without
findings. The final rebuilt native artifact repeats the same 29,952 comparisons
without differences. Rust formatting and whitespace checks pass. Existing
deliberate compaction/CAS/URI fault diagnostics remain visible; no failing check
was suppressed. Temporary comparison tooling is removed.

Regex replacement, other functions/control flow, float/complex/rune literals,
variables, field chains, non-UTF-8 values and exact diagnostics remain open.
This is not full Go regexp syntax, upstream-service, deployed-provider or
capacity acceptance. Work remains local, uncommitted and unpushed.

### Regex replacement template continuation

The formatter gap now excludes `regexReplaceAll` and `regexReplaceAllLiteral`
within the shared bounded regex profile. Expanded replacements preserve Go's
whole-match/numbered/named references, maximal Unicode letter/digit/underscore
names, leading-zero name handling, literal dollars and malformed/unknown
reference behavior. Literal replacement never expands dollar references.
Native matching preserves non-overlap and Unicode-scalar empty-match progress;
invalid executed patterns and argument failures preserve inputs with
`TemplateFormatErr`, while skipped branches do not execute them.

Two passes prove output size before allocation and then write directly into
an exactly sized Erlang binary, retaining no matches. Each pass charges match
probes, dollar-reference scanning and capture-name bytes, including references
that emit no bytes.
Both helpers share counting work across actions/entries; work/output exhaustion
fails whole, including explicit error selection and later truncation. Existing
configured ceilings remain authoritative. Upgrade every query-serving app/native
pair to log tuple `{1,1,9}`; storage and keyed encoder bytes are unchanged.

Two complete pinned Loki formatter rows retain their original templates,
labels and expected outputs through authenticated GET/form POST and native
Parquet/loopback S3. The nine function continuations total 60 original formatter
evaluations. Two original invalid-function assertions adapt to template errors
separately. Seventeen successful controls and nine failure templates exercise
both stages. All 87 Go replacement table rows remain frozen with original
oracles and provenance across 135 mode evaluations: 125 exact outputs and ten
explicit duplicate-named-group profile rejections at this checkpoint, not parity
successes; the named-capture continuation below closes those ten cases.
The actual pinned Loki pipeline independently agrees with every original Go
oracle, including the ten Pulse rejects. Ordinary replay needs neither Go nor
network access.

All 107,520 additional actual pinned Loki parser/pipeline comparisons agree,
including 15,360 runtime errors, excluding exact error details. The matrix
preserves 28 patterns × 16 texts × 20 replacements × both helpers × both
formatters × three label owners and checks output plus separate label categories.
An independent Elixir iterator adds 2,760 replacement comparisons, exact native
work boundaries and the existing 1,380 count comparisons. Public evaluator
controls prove work sharing across entries/actions/helpers, zero-output
reference-work exhaustion, exact long-name work boundaries and exact/oversized
intermediate output behavior.
Initial regressions fail without the feature (seed433); all five retained checks
pass afterward (seed435). Source hashes/adaptations are recorded in the fixture
README; evidence is under `.amp/in/artifacts/loki-template-regex-replace-*`.

Final rebuilt-artifact checks: all five targeted checks pass (seed439), and
all 107,520 actual pinned pipeline comparisons repeat without differences.
The long-name boundary fails before its additional byte charge (seed438) and
passes afterward. Full `mix precommit --seed 440` passes 2,267 tests with one
skipped and 37 opt-in exclusions in 433.7s. Strict compilation, unused-dependency
and formatter checks pass. Strict Credo checks 445 files without findings;
all 133 codec Rust tests pass, as do Rust formatting and strict all-target
Clippy under `mise exec` (Rust1.97.1). An earlier PATH-only Clippy probe used
Rust1.94.0 and reported two lints in unchanged trace pruning; no lint or test
was suppressed. Full-suite timeout/CAS/acceptor diagnostics remain visible and
do not close the separately listed reliability follow-ups.

Numeric/repeated names and literal quoting are covered by the later named-capture
continuation. Full Go regexp syntax/capacity parity remains open, alongside
other template functions/control flow, variables, field chains,
float/complex/rune literals, non-UTF-8 values and exact diagnostics. No full
upstream-service, deployed-provider or capacity acceptance is implied. Work
remains local, uncommitted and unpushed.

### Rune constant template continuation

Template character literals now retain integer Unicode code-point values,
including named/octal/hex/Unicode escapes. Byte escapes denote numbers, never
non-UTF-8 strings. Empty/multiple characters, raw line feeds, wrong-quote or
malformed escapes, surrogates and out-of-range Unicode reject before storage,
including inside skipped branches. Integer argument/arithmetic/comparison,
zero truthiness/default, pipeline and runtime-error preservation policies remain.

Both original regressions fail without the implementation (seed441), while
all three retained checks pass afterward (seed442), including the previous
integer-admission control. Eight complete original Go1.27.3 number oracles,
three original malformed-number inputs and all seven selected lexer character
tokens replay through authenticated GET/form POST, native Parquet and loopback
S3, separately from the 60 Loki formatter evaluations. The lexer row's tokens
are evaluated separately, not claimed as one executable multi-argument command.
An independent source AST audit confirms all eleven number rows, and the complete
upstream `TestNumberParse` and `TestLex` suites pass offline. All 25 retained
successful outputs independently agree with actual pinned Loki, as do all fifteen
malformed admissions. Four runtime-error templates preserve existing destinations
and metric-error selection. Invalid queries prove no object-store requests occur.

All 10,400 additional actual pinned Loki parser/pipeline comparisons agree,
including 2,600 runtime errors, excluding exact error details. They preserve
650 spellings over 285 distinct Unicode scalar values × eight typed/rendering/
conditional templates × both formatters, output and separate label categories.
Full `mix precommit --seed 443` passes 2,269 tests, one skipped and 37 opt-in
exclusions in 238.5s, including strict compilation, unused-dependency and formatting
checks; strict Credo checks 445 files without findings. Evidence and source hashes
are recorded under `.amp/in/artifacts/loki-template-runes-*` and the fixture README.
Full timeout/CAS/URI diagnostics remain visible; reliability follow-ups stay open.

Upgrade query-serving applications; rune support adds no native/storage/keyed-byte
change or resource ceiling. Float/complex constants, other functions/control flow,
field chains, non-UTF-8 values and exact diagnostics remain open. This is not full
formatter, upstream-service, deployed-provider or capacity acceptance. Work remains
local, uncommitted and unpushed.

### Floating-point constant template continuation

Finite decimal/scientific/hexadecimal constants, separators and signed zero now
follow the pinned Go number profile. Direct integral in-range constants satisfy
typed integer parameters, while parenthesized/piped floats require explicit
conversion. Ten original non-complex Go number oracles retain their exact
spelling and values through authenticated GET/form POST, native Parquet and
loopback S3, separately from the Loki formatter row total. An independent Go
source-AST audit verifies the original oracle expressions and all ten ports.
All 26 successful retained templates independently agree with actual pinned Loki.

Both regressions fail before implementation (seed444); all three targeted tests
pass after it (seed445). Full precommit seed446 passes 2271 tests, one skipped
and 37 opt-in exclusions in 258.7s. All 6912 actual pinned pipeline comparisons
are accounted for: 6874 exact excluding diagnostics, 38 deliberate nonportable
out-of-range integer-cast rejections, zero unexpected differences. Six of the
deliberate rejections concern Go's rounded positive-int64 number-node boundary;
the other 32 use coercing integer helpers. The 2834 upstream runtime errors
remain part of the exact comparison, not skipped. Existing timeout/CAS/URI
diagnostics and reliability follow-ups remain visible/open.

Existing budgets/native/storage/keyed bytes are unchanged; upgrade query-serving
applications. Complex literals, other functions/control flow and exact diagnostics
remain open. Evidence/source hashes and limitations are recorded in the fixture
README and `.amp/in/artifacts/loki-template-floats-*`. Work remains local,
uncommitted and unpushed.

### Floating conversion, extrema and rounding continuation

`float64`, `minf`, `maxf`, `ceil`, `floor` and `round` now retain coercion,
signed-zero/nonfinite runtime values and typed float consumption. Three complete
original Loki formatter rows replay through authenticated GET/form POST, native
Parquet and loopback S3, raising the Loki source formatter total to 63. Separate
controls cover all threshold argument types, integer precision, skipped branches
and preserved metric errors. Nonportable float-to-integer casts still reject.

All 27,928 actual pinned parser/pipeline comparisons agree, including 30 runtime
errors, excluding exact diagnostics. All 19 retained successful templates agree
independently with Loki; a source-AST audit verifies the three original rows.
The pinned Go 1.27.3 runtime fuses the fractional residual, giving 123.555 for
round 123.5555 3 rather than Sprig's static 123.556 expectation. That difference
is an explicit independent control, not an altered upstream oracle or a
cross-compiler/platform bit-parity claim. Existing budgets are unchanged.

Both initial regressions fail before implementation (seed447). Final full
precommit seed450 passes 2273 tests, one skipped and 37 opt-in exclusions in
290.0s, including the fused-residual fix; strict Credo checks 445 files cleanly.
Timeout/CAS/URI diagnostics and reliability follow-ups remain visible/open.
Upgrade query-serving apps; native/storage/keyed bytes are unchanged. Decimal
addf/subf/mulf/divf, remaining control flow and exact diagnostics remain open.
Evidence/source hashes and licensing are in the fixture README and
`.amp/in/artifacts/loki-template-float-helpers-*`. Work remains local,
uncommitted and unpushed.

### Decimal arithmetic template continuation

`addf`, `subf`, `mulf` and `divf` now coerce operands through float64 and fold
their shortest decimal representations, with one float64 conversion on return.
Division rounds every step to 16 decimal places, halfway away from zero. Two
complete original Loki formatter rows replay unchanged through both formatting
stages, authenticated GET/form POST, native Parquet and loopback S3, raising the
source formatter total to 65. Separate controls distinguish decimal cancellation,
variadic order, float64 input precision loss, underflow/overflow and zero signs.
Zero division/nonfinite input preserves existing destinations and metric errors;
skipped failures do not execute.

Both new regressions fail before implementation (seed451) and pass afterward
(seed452). All 14,012 actual pinned Loki parser/pipeline comparisons agree,
including 1,524 runtime errors, excluding exact diagnostics. All 15 retained
successful templates agree independently with Loki; a source-AST audit verifies
both original table rows. Existing query/worker/output ceilings remain
authoritative. No dependency or native/storage/keyed-byte change; upgrade
query-serving apps. This is not full formatter/client or capacity acceptance.

The first full precommit seed453 passed 2274/2275 tests, with one unchanged
150k-span MCP top-k query hitting its 10s request deadline under concurrent local
validation. The same test passed alone and in three instrumented repeats:
5000-row projected queries took 1.356–1.386s; full-metadata queries 1.298–1.748s.
This suggests contention sensitivity, not a proven root cause or a closed
reliability item. No deadlines, fixtures or resource ceilings were widened.
The final targeted four formatter tests pass (seed454); strict Credo checks
445 files without findings, and both runtime matrices still agree after shared
float dispatch consolidation. The full same-seed rerun without competing heavy
validation passes all 2275 tests (one skipped, 37 opt-in exclusions) in 338.9s;
the unchanged trace test completes in 8.9s including its fixture and four
queries. The earlier timeout remains recorded, not closed by the green rerun.
Full diagnostic evidence remains retained.

Evidence, source hashes and MIT notices are recorded in the fixture README
and `.amp/in/artifacts/loki-template-decimal-*`. Work remains local,
uncommitted and unpushed.

### Complex template constant continuation

Finite imaginary/combined literals now preserve component values and signed
zeros, complex truthiness/equality, numeric-helper coercion to zero and Go's
direct-constant versus typed-pipeline numeric arguments. Seven complete Go
number rows retain original inputs and component oracles through rendered
HTTP GET/form POST, native Parquet and loopback S3. These supplementary Go
rows do not increase the 65 Loki source formatter evaluations. Separate
controls cover hexadecimal/separator/exponent components and underflow.

Both new regressions fail before implementation (seed455); all five selected
complex/float regressions pass afterward (seed456). All 22 retained successful
templates independently match actual pinned Loki in both stages; all eleven
malformed/overflowing literals reject in both upstream constructors. Public
replay proves no provider reads for those admission failures and retains
input/metric-error policies for ten executed type-error templates.
All 8240 actual pinned parser/pipeline comparisons agree, including 4744
runtime errors, excluding exact diagnostics. Strict Credo checks 445 files
without findings. Full precommit seed457 passes 2277 tests, one skipped and
37 opt-in exclusions in 282.7s; the unchanged 150k-span trace test completes
in 7.6s including setup and four queries. The earlier timeout remains open,
not erased by this green run. Existing nonportable integer-cast exclusions, query/worker/
output limits and native/storage/keyed bytes are unchanged. Upgrade query apps.
Full formatter/client/capacity and exact-error acceptance remain open.

Source hashes, adaptations and evidence are recorded in the fixture README
and `.amp/in/artifacts/loki-template-complex-*`. Work remains local,
uncommitted and unpushed.

### Root label-map and indexing continuation

Template root maps and `index` now provide arbitrary string-key label access,
missing-key empty values, lexical map rendering/length/truthiness and chained
string-byte indexing. Byte results retain uint8 type distinctions: integer
comparisons and numeric casts work, typed int arguments need explicit conversion.
Two original Go comparison regressions and twelve successful controls replay
through authenticated GET/form POST, native Parquet and loopback S3; separate
controls preserve metadata keys, same-stage snapshots and earlier-stage changes.
These supplementary Go cases leave the Loki formatter-source total at 65.

Both new HTTP tests fail before implementation (seed458); five selected
index/complex/budget regressions pass afterward (seed461). All 14 retained
successful templates match actual pinned Loki in both stages. All 7638 actual
pinned pipeline comparisons agree, including 4442 runtime errors, excluding
exact diagnostics. Full precommit seed462 passes 2280 tests, one skipped and
37 opt-in exclusions in 279.6s, with no trace-query timeout recurrence.
Strict Credo checks 445 files cleanly after sharing existing
built-in dispatch. Public regressions prove fail-whole map-output overflow on
log/top-k/metric paths despite later drops/error selection; separate boundary
probes accept cap-1/cap bytes and reject cap+1. Existing query/worker/output
ceilings and native/storage/keyed bytes are unchanged; upgrade query apps.
Generic arrays/JSON values/field chains, non-UTF-8 strings, exact errors and
full built-in/client/capacity acceptance remain open. Source hashes and evidence
are recorded in the fixture README and `.amp/in/artifacts/loki-template-index-*`.
Work remains local, uncommitted and unpushed.

### Go string-slicing continuation

String `slice` now uses zero-based exclusive byte bounds, optional indices,
integer/uint8 index types and empty results without Sprig `substr` clamping.
Invalid types/bounds and third indices preserve inputs with `TemplateFormatErr`.
Six original Go string cases plus separate controls replay through authenticated
GET/form POST, native Parquet and loopback S3. Supplementary Go cases do not
increase the 65 Loki formatter-source evaluations. Array slicing and non-UTF-8
byte-string propagation remain open; split UTF-8 rejects even before `b64enc`.

Both HTTP regressions fail before implementation (seed463); thirteen selected
slice/index/formatter/budget tests pass afterward (seed465). All eighteen
retained successful templates independently match actual pinned Loki in both
stages, and all six original rows retain their exact Go source inputs/oracles.
Full precommit seed466 passes 2282 tests, one skipped and 37 opt-in exclusions
in 284.9s, without a trace-query timeout recurrence.
Of 4240 actual pinned pipeline comparisons, 4076 agree excluding diagnostics,
including 3728 runtime errors; 164 deliberately reject non-UTF-8 intermediates.
There are no unexpected differences. Strict Credo checks 445 files cleanly.
Boundary probes accept cap-1/cap, reject cap+1 and prove later slicing cannot
hide an oversized intermediate expansion. Existing resource ceilings and native/
storage/keyed bytes are unchanged; upgrade query-serving apps. Exact diagnostics,
full templates and client/provider/capacity acceptance remain open.

Source hashes, adaptations and evidence are in the fixture README and
`.amp/in/artifacts/loki-template-slice-*`. Work remains local, uncommitted
and unpushed.

### Printing and explicit escaping continuation

Closed `print`, `println`, `html` and `urlquery` for existing template value
types, preserving Go variadic spacing, line feeds, default typed rendering,
HTML/NUL escaping and query-form escaping. Seven original Go rows and seventeen
controls replay through authenticated GET/form POST, native Parquet and loopback
S3. These supplementary Go cases do not increase the 65 Loki formatter-source
evaluations. All 24 retained successful templates independently match actual
pinned Loki in both stages; all seven source inputs/oracles are audited.

The new HTTP regression and extended evaluator budget regression fail on the
unsupported baseline (seed467). Nine selected printing/escaping/slicing/index/
budget tests pass afterward (seed470). All 8504 actual pinned Loki pipeline
comparisons agree, including 1488 runtime errors, excluding exact diagnostics.
All ASCII bytes, Unicode/chunk boundaries, mixed variadic types, nested failures
and separate label ownership are covered. Strict Credo checks 445 files cleanly.
Full precommit (seed471, trace-serialized to one concurrent case) passes **2283 tests**, one
skipped and 37 excluded, in 511.7s; strict compile, dependency and format checks
are included. No timeout assertions fail, without changing deadlines or fixtures.
This does not close the earlier contention-sensitive timeout reliability item.

Public budget replay accepts exact 16 MiB output and rejects amplified combined/
escaped intermediates on log/top-k/metric paths despite later trimming or error
selection. An initial dense HTML implementation exceeded the unchanged worker
heap; bounded replacement chunks fixed it without changing fixtures or ceilings.
No native/storage/keyed-byte change; upgrade query apps. `printf`, typed
pointer/interface values, byte-string propagation, exact errors and complete
formatter/client/provider/capacity acceptance remain open. Source hashes,
adaptations and evidence are in the fixture README and
`.amp/in/artifacts/loki-template-print-escape-*`. Work remains local,
uncommitted and unpushed.

### Untyped nil continuation

Closed untyped nil literals for formatter arguments, truthiness/defaults,
equality, zero numeric coercion and function-result rendering. Bare nil commands
fail only at execution; missing string labels remain empty strings. Print keeps
nil a nonstring `<nil>`, whereas escape functions convert it to a string
`<no value>` before joining, affecting separators as well as spelling.

Three original Go 1.27.3 rows plus controls replay through authenticated GET/form
POST, native Parquet and loopback S3: 24 successful templates, 21 runtime errors
and two admission controls. Both new tests fail on the unsupported baseline
(seed472) and pass afterward (seed473). All 24 successful expectations also match
actual pinned Loki in both formatter stages. All **7528 actual pinned pipeline
comparisons** agree, including **812 runtime errors**, excluding diagnostics,
with mixed typed values, nested/lazy functions and separate label ownership.
These supplementary Go cases leave the 65 Loki formatter-source total unchanged.

Full precommit (seed478) passes **2286 tests**, one skipped and 37 excluded, in
1536.4s, including strict compile/dependency/format checks. Trace mode serializes
the run to one concurrent case despite the supplied eight-case option. No
timeout assertions fail, but concurrent reliability/capacity remain unproven.

Existing resource ceilings and native/storage/keyed bytes are unchanged; upgrade
query apps. Typed nil pointers/interfaces, `printf`, byte-string propagation,
exact errors and full formatter/client/provider/capacity acceptance remain open.
Source hashes and adaptations are in the fixture README; evidence is in
`.amp/in/artifacts/loki-template-nil-*`. Work remains local, uncommitted and unpushed.

### JavaScript escaping continuation

Closed `js` for variadic typed/nil values with Go's argument joining, special
ASCII escaping and Unicode 17 printability. Eight complete upstream Go table
rows retain their original inputs/oracles, wrapped in a string label for public
HTTP replay. Fourteen successful controls and three nested runtime errors cover
typed/nil spacing, control bytes, new Unicode scalars, supplementary nonprintable
values, pipeline order and UTF-8 chunk boundaries through authenticated GET/form
POST, native Parquet and loopback S3. A separate Go AST source audit confirms all
eight original pairs; all 22 successful templates also match actual pinned Loki.

All **19060 actual pinned Loki pipeline comparisons** agree, including **304
runtime errors**, excluding exact diagnostics. Grouped inputs cover every one of
the **1112064 valid Unicode scalars**; typed/error/boundary controls are separate.
The shared printable-scalar classifier was extracted unchanged, with four
existing numeric-diagnostic HTTP regressions passing before new behavior
(seed475). Both new JS regressions fail without implementation (seed476);
ten selected JS/nil/numeric/string-budget tests pass afterward (seed477).
Full precommit (seed478) passes **2286 tests**, one skipped and 37 excluded, in
1536.4s, including strict compile/dependency/format checks. Trace mode serializes
to one concurrent case; this does not close the contention-sensitive timeout item.

The public evaluator budget regression accepts exactly 16 MiB output and rejects
oversized intermediates on log/top-k/metric paths despite later shrinking/error
selection. Full escaped size is proven before allocation; UTF-8-aligned chunks
bound temporary terms. Go's minimum-four-digit escapes above U+FFFF deliberately
remain, not JSON surrogate pairs or context-aware sanitization. These are eight
supplementary Go cases, not additional Loki formatter-source evaluations.
Existing ceilings/native/storage/keyed bytes are unchanged; upgrade query apps.
`printf`, typed pointer/interface values, byte-string propagation, exact errors
and full formatter/client/provider/capacity acceptance remain open. Source hashes
and adaptations are in the fixture README; evidence is in
`.amp/in/artifacts/loki-template-js-*`. Work remains local, uncommitted and unpushed.

### With scope continuation

Closed `with`/`else with` branching and `$` root lookup for existing template
values, with nested dot changes, unchanged false-branch dots and restoration
after each block. Root maps retain the label-format stage's first-template
snapshot and refresh in later stages; scalar field access is a runtime error.
Ten original Go 1.27.3 cases plus 22 successful templates, three pipeline scope
controls, eight runtime failures, six upstream admission failures and separate
64/65 nesting-boundary controls replay through authenticated GET/form POST,
native Parquet and loopback S3, including metric error-selection policies.
These supplementary Go rows leave the 65 Loki formatter-source total unchanged.

All **2387 actual pinned Loki pipeline comparisons** agree, including **516
runtime errors**, excluding diagnostics. Every retained success/error and all
six syntax/unknown-function rejections independently match actual Loki; a
standard-library Go AST audit checks the ten original template/oracle pairs.
The two HTTP regressions and extended budget regression fail on the unsupported
compiled baseline (seed479) and pass afterward (seed480); final scope/snapshot/
budget controls pass (seed481). Strict Credo checks 446 files cleanly.

Public budget replay accepts exact 16 MiB output and rejects accumulated
outer-plus-branch overflow on log/top-k/metric paths despite later trimming or
error selection. Existing ceilings/native/storage/keyed bytes are unchanged;
upgrade query applications. Variables, iteration, date/other functions, field
chains, byte-string propagation, exact errors and full formatter/client/
provider/capacity acceptance remain open. Source hashes/adaptations are in the
fixture README; evidence is in `.amp/in/artifacts/loki-template-with-*`.
Work remains local, uncommitted and unpushed.

### Concurrent timeout investigation

The first non-trace eight-case precommit (seed482) passed 2287/2288 tests and
failed a stale unsupported-`with` assertion, not a timeout. Replaced that control
with unsupported `range`; its targeted replay passes (seed483).
The next full eight-case run (seed484) reproduced three failures: the unchanged
150,000-span MCP top-k query reached its 10s deadline, and native LogQL parity
and Tempo special-character discovery reached ExUnit's 60s limits. Host load
exceeded 600 on 18 logical CPUs, with substantial compressed memory; this is
correlation, not proof of CPU starvation or a unique root cause.

The same three tests/seed pass together in 7.7s, with unchanged fixtures and
deadlines. Isolated timing puts the four MCP calls at 0.190/0.932/0.971/0.171s;
the final call correctly rejects the existing sample limit. A node-wide legacy
tracer conflicted with existing trace-owning tests, so that instrumented full
run is not a valid suite result. The uninstrumented full replay of seed484,
with eight concurrent cases, passes **2288 tests**, one skipped and 39 excluded,
in **151.4s** as host load subsides. Two exclusions are the then-unimplemented
variable regressions; the original 37 exclusions are unchanged. No deadline,
ceiling or existing fixture was widened, reduced or suppressed.

This establishes load-sensitive reproduction and a passing concurrent control,
not a permanent reliability fix or deployed capacity. The earlier timeout item
stays open. Evidence is in `.amp/in/artifacts/timeout-*` and the with-batch logs.

### Action and control-header variable continuation

Closed variable declarations and nearest-binding assignments in actions and
`if`/`with` headers. Shadowed declarations restore on block exit, outer
assignments survive, header variables exist in else branches, and each
template/destination/entry starts fresh. Saved-map field/index lookup and local
`$` reassignment do not mutate the label snapshot or change dot. Go's lexical
visibility can admit runtime-undefined self-initializers, assignments and
else-branch references; skipped branches do not execute those failures.

Three unchanged Go 1.27.3 assignment rows, 26 successful controls, ten runtime
failures, eight upstream admission failures and one deliberate nested-binding
fence replay through authenticated GET/form POST, native Parquet and loopback
S3, including metric error policies. All **6198 actual pinned Loki pipeline
comparisons** agree, including **1454 runtime errors**, excluding diagnostics.
An independent Go AST audit verifies the three original templates/oracles.
Both HTTP regressions fail on the compiled baseline (seed485); both plus the
existing scope controls and extended budget test pass after implementation
(seed486). Strict Credo checks 446 files cleanly.
Full precommit (seed487, eight concurrent cases without trace) passes **2290
tests**, one skipped and the original 37 excluded, in **156.7s**. All new
variable regressions are included; no timeout assertion fails. This is another
passing concurrent control, not closure of the load-sensitive reliability item.

Exact 16 MiB output succeeds; accumulated variable/branch output and oversized
unused initializers fail whole on log/top-k/metric paths despite shrinking or
explicit error selection. Existing ceilings/native/storage/keyed bytes are
unchanged; upgrade query applications. Bindings inside parenthesized pipelines,
iteration, date/other functions, field chains, byte-string propagation, exact
errors and full formatter/client/provider/capacity acceptance remain open.
Source hashes/adaptations are in the fixture README; evidence is in
`.amp/in/artifacts/loki-template-variables-*`. Work remains local, uncommitted
and unpushed.

### Nested template bindings and field-chain continuation

Closed the former parenthesized-pipeline binding fence. Runtime evaluation now
threads bindings explicitly through nested pipelines and sequential arguments;
lazy logical operators skip unselected side effects. Compilation tracks names
in source order, admitting self-initialization but rejecting forward references.
Nested declarations retain block scope, assignments use the nearest binding
after initializer effects, and root reassignment remains template-local.

The existing variable HTTP tests now retain three original Go rows, 48 successful
controls, 16 runtime failures and 13 constructor rejections. Both fail on the
unsupported compiler (seed489), then pass (seed490). All **16,622 actual pinned
Loki pipeline comparisons** agree, including **3764 runtime errors**, excluding
diagnostics. The complete Loki HTTP and budget suites pass **213 tests** (seed491).

Closed field-chain syntax for label maps, saved variables, functions and
parenthesized results, not generic JSON values or methods. Empty-string map
defaults differ from nil function results: nil propagates through fields and
returns before evaluating field arguments. The actual Loki comparison exposed
that difference; the regression includes skipped binding side effects.
One original Go successful row and three original failure rows retain their
templates/oracles, independently audited from the Go AST. Another 14 successful,
ten runtime-error and seven admission controls replay through authenticated
GET/form POST, native Parquet and loopback S3. Both HTTP tests fail before the
change (seed492) and pass after it (seed494). The combined **18,838 actual pinned
Loki pipeline comparisons** agree, including **5278 runtime errors**, excluding
diagnostics. All 20 retained constructor rejections agree with actual Loki.
The complete HTTP/budget suites pass **215 tests** (seed495).

Budget controls retain exact 16 MiB output and fail-whole accumulated or executed
intermediate overflow, including unused nested initializers and failed field
lookups, on log/top-k/metric paths despite error preservation or later shrinking.
Lazy-skipped initializers and nil-receiver arguments do not allocate. Strict
Credo checks 446 files cleanly. No native/storage/keyed-byte/dependency/ceiling
change; upgrade query applications. Normal replay needs no Go or upstream
service. Source hashes/adaptations are in the fixture README; evidence is in
`.amp/in/artifacts/loki-template-nested-*` and `loki-template-field-chains-*`.
Generic JSON objects/arrays, date/other functions, byte-string
propagation, exact diagnostics and full formatter/client/provider/capacity
acceptance remain open. Work remains local, uncommitted and unpushed.

Full concurrent precommit (seed496, eight cases without trace) passed **2292
tests**, one skipped and the original 37 excluded, in **126.4s**. This includes
all nested-binding/field-chain regressions and does not close load-sensitive
reliability. The following iteration batch supersedes its iteration exclusion.

### Bounded template iteration continuation

Closed `range` over currently expressible label maps and integer/uint8 values,
including single/two-variable declarations/assignments, empty/nil else paths,
lexical map ordering and nested `break`/`continue`. Integer ranges reject two
variables even when empty; byte sequences retain uint8 type boundaries. Dot
and root remain distinct, body declarations reset each iteration, outer
assignments survive and empty headers initialize their variables to the input.
Loop control in an empty inner loop's else reaches the enclosing loop.

Rendering first changed to explicit output/state/control threading without
altering admitted syntax; all **215 existing HTTP/budget tests** passed (seed497).
Both new HTTP tests then failed on unsupported range admission (seed498), and
passed after implementation (seed499). The permanent batch retains **26
successful controls**, **ten runtime errors**, **nine upstream constructor
rejections** and a separate unchanged 64/65-depth boundary. Ten original Go
`parse/parse_test.go:222–241` rows retain their syntax/admission oracles, not
invented value expectations for unsupported upstream structs/slices. An
independent Go AST reader verifies all ten against their original `noError` rows.
Tests use authenticated GET/form POST, native Parquet and loopback S3 for both
formatters and metric error selection; old deliberate range fences now use
genuinely malformed range syntax.

All **21,304 combined actual pinned Loki pipeline comparisons** agree, including
**5388 runtime errors**, excluding diagnostics. Cached compiled pipelines span
distinct stream/metadata contexts, integer/map/nil inputs, single/two-variable
bindings, nesting and loop control. All **29** combined retained constructor
failures agree with actual Loki. The existing output regression proves exact
16 MiB across iterations and fail-whole overflow on log/top-k/metric paths.
A new public budget regression proves empty-output/continue loops spend work,
share it across actions/entries and regex helpers in both orders, and fail whole
despite explicit error selection. An int64-max loop with immediate break succeeds
without preallocating or precharging potential iterations. The targeted batch
passes four tests (seed500); strict Credo checks 446 files cleanly.
Full concurrent precommit passes **2295 tests**, one skipped and the original
37 excluded, in 133.5s (seed501, eight cases without trace). Existing compaction
timeout diagnostics remain; this does not close load-sensitive reliability.

Every executed iteration spends one existing metric work unit or request-local
stream-template work unit, shared with regex counting/replacement. Empty output
is not retained per iteration. No native/storage/keyed-byte, dependency or ceiling
change; upgrade query applications. Generic JSON objects/arrays, channel/function
iteration, date/other functions, byte-string propagation, exact diagnostics and
full formatter/client/provider/capacity acceptance remain open. Source hashes
and adaptations are in the fixture README; evidence is in
`.amp/in/artifacts/loki-template-range-*`. Work is local, uncommitted and unpushed.

### Typed JSON template continuation

Closed `fromJson` for typed nested objects/arrays, float64 numbers, strings,
booleans and nil. Field/key/index lookup, printing, length/truthiness, numeric
coercion and ordered iteration retain distinctions from root string labels.
Duplicate keys replace earlier values, including entire objects. Malformed
documents/trailing content return nil; surrogate replacement and float64 signed
zero/rounding follow the actual pinned runtime. Numeric overflow becomes zero
under Go 1.27.3, not an assertion about every Go decoder version.

Both complete Sprig v3.3.0 `TestFromJson` oracles retain their unchanged input,
templates and expectations, independently audited from the Go AST. They are
supplementary MIT-licensed unit rows, not additional Loki integration rows.
Another 29 successful controls and 19 runtime failures replay through both
formatters, authenticated GET/form POST, native Parquet and loopback S3, including
metric error selection. Both HTTP tests fail before implementation (seed502);
the four new HTTP/budget tests pass (seed505). The complete HTTP/budget suites
pass **222 tests** (seed506).

All **10,292 actual pinned Loki pipeline comparisons** agree, including **3874
runtime errors**, excluding diagnostics. Every executed decode charges input
bytes before normalization/expansion to shared metric query work or request-local
stream-template work. Input/normalized bytes cap at 16 MiB and containers at 64
levels; growth is proven before allocation. Work/size/depth exhaustion fails
whole despite explicit error selection, later shrinking or unused output. Public
budget tests cover shared actions/entries/loops/regex, malformed input, exact
output, raw/normalized overflow and both sides of the nesting boundary.

Full concurrent precommit passes **2299 tests**, one skipped and the original
37 excluded, in 165.8s (seed507, eight cases without trace). Strict Credo checks
447 files cleanly. Compaction timeout/conflict diagnostics remain; this does not
close load-sensitive reliability. Array slicing, methods, channel/function
iteration, date/other functions, non-UTF-8 byte propagation, exact diagnostics and
full formatter/client/provider/capacity parity remain open. No native/storage/
keyed-byte/dependency change; upgrade query apps. Source hashes/adaptations are
in the fixture README and evidence in `.amp/in/artifacts/loki-template-json-*`.
Work remains local, uncommitted and unpushed.

### Decoded array-slicing continuation

Closed `slice` for typed JSON arrays with default/exclusive bounds, three-bound
capacity restrictions and nested recovery of decoded backing elements. Consumers
use the current view for indexing, length, truthiness, printing and iteration.
Views retain the original tuple without copying or allocating ranges.
Initial capacity equals decoded length, deliberately excluding Go allocator
spare slots; their exposure remains an explicit compatibility difference.

Ten original Go 1.27.3 slice templates and success/error oracles replay through
authenticated GET/form POST, both formatters, native Parquet and loopback S3.
An independent Go AST audit checks every template, oracle and original SI fixture;
the fixture becomes a typed JSON object selected by an enclosing `with`.
These supplementary Go rows do not increase Loki integration-source counts.
Another 18 success/13 failure controls plus two explicit spare-capacity
rejections cover nested views, reduced caps, rebased indices/iteration, nil,
types, empty results and skipped errors. Ordinary metrics reject formatting
errors; explicit error selection retains their unchanged inputs.

The success HTTP test fails before implementation (seed508). The representation
refactor passes all four unchanged JSON HTTP/budget tests (seed509), then both
slice HTTP tests pass (seed510). The final three-test HTTP/budget batch passes
(seed511): nested-loop shared work, exact 16 MiB rendered arrays and fail-whole
overflow on ordinary/top-k/metric paths despite error selection or later shrinking.
Of **5984 actual pinned Loki pipeline comparisons**, **5980 match**, including
**4304 upstream runtime errors**. Four deliberately reject allocator spare cells;
there are no unexpected differences, excluding diagnostics.

Full concurrent precommit passes **2302 tests**, one skipped and the original
37 excluded, in 209.0s (seed512, eight cases without trace). Strict Credo checks
447 files cleanly. Existing compaction timeout/conflict diagnostics remain;
load-sensitive reliability and full provider/client/capacity parity remain open.
No native/storage/keyed-byte/dependency/ceiling change; upgrade query apps.
Source hashes/adaptations are in the fixture README and evidence in
`.amp/in/artifacts/loki-template-array-slice-*`. Work is local and uncommitted.

### Histogram diagnostic and collision continuation

Twelve unchanged pinned Mimir evaluations now replay through instant/range HTTP
and memory/native Parquet/S3: four classic repair/admission/mixed-identity cases
and eight native NaN-observation quantile/fraction cases. Both fixture files
are byte-identical to their documented source selections; normal replay needs
no Go or network. The first fixture fails before the classic/collision change
(seed513); the second fails before native info propagation (seed517), then both
pass together (seed518).

Only valid classic bounds participate in same-name/full-input-label collision
detection. A native `le` remains part of its identity. Mixed pairs omit only
their own step, malformed/NaN bounds warn, and invalid quantiles warn even for
empty inputs. Real count decreases publish repair info; tiny changes in either
direction remain silent. Existing native NaN result/skew/fraction-exclusion
flags now reach responses. Go diagnostic quoting reuses the existing numeric
quoter without changing its escaping. Additional public controls cover unrelated
groups, escaped/overflow bounds, numeric duplicate boundaries, missing `+Inf`,
stale transitions, form POST and per-source warning/info isolation.

Full concurrent precommit passes **2310 tests**, one skipped and the original
37 excluded, in 123.7s (seed519, eight cases). Strict Credo checks 447 files
cleanly. No native/storage/keyed-byte/dependency/ceiling change; upgrade query
applications. Evidence is in `.amp/in/artifacts/mimir-histogram-*`; work is local,
uncommitted and unpushed. Full Mimir diagnostics remain open, including AST
positions. Expanded monotonicity summaries are a vendored Prometheus feature;
the pinned Mimir streaming engine deliberately emits the generic message.
`histogram_quantiles`,
classic fractions and newer multi-bucket NaN interpolation are not covered;
native primitives still follow Prometheus 3.5.0, including its last-bucket quirk.

### Plural histogram quantile continuation

`histogram_quantiles(vector,"label",q0,...)` now reuses classic/native grouping
once per evaluation step, with per-quantile scalar values and OpenMetrics label
text. Destination overwrite, metric-name removal and same-step duplicate errors
apply before range merging. Potential group/quantile fan-out reserves the shared
intermediate budget before construction; bucket/custom-bound traversal and
generated label bytes spend shared work. Existing ceilings, native arithmetic,
storage and keyed bytes remain unchanged. Upgrade query applications.

The complete five-case Mimir fixture fails at admission before implementation
(seed520), then passes (seed521). Four more unchanged upstream native cases and
public label/overwrite/nonfinite/form-POST/budget controls pass together
(seed522). Both source selections are byte-identical; no Go or network is needed
for normal replay. Native multi-bucket NaN arithmetic, classic fractions and
diagnostic positions remain separate gaps. The pinned Mimir streaming engine
does not expose extended repair summaries.

### Classic fraction and corrected native NaN interpolation continuation

Classic `histogram_fraction` now shares valid-bound grouping and mixed-identity
omission with quantiles. It sorts/coalesces buckets and linearly interpolates
lower/upper ranks, without quantile monotonicity repair. Missing final `+Inf`,
zero totals and NaN bounds return NaN before reversed-bound checks. Three
unchanged Mimir evaluations fail before implementation (seed524), then pass with
public boundary, per-step bound, collision, source-notice and quota controls
(seed525). Another **14,400 comparisons** against the actual pinned Go
`BucketFraction`/`coalesceBuckets` functions match numerically, including shuffled
duplicate bounds, nonmonotonic/nonfinite counts and nonfinite thresholds.

Eight further unchanged Mimir evaluations retain complete multi-bucket NaN and
±Inf-observation inputs/oracles. After admitting their explicit positive/negative
offsets in the fixture loader, they fail numerically on both HTTP/storage paths
(seed527). Removing the last-bucket reassignment makes them pass alongside the
other histogram fixtures/controls (seed528). Native interpolation now keeps the
bucket where the requested rank is reached, intentionally replacing Prometheus
3.5.0's quirk with pinned Mimir's fix. A NaN sum alone still does not imply NaN
observations. Supplementary primitive controls cover negative, zero and custom
buckets. Other native arithmetic remains at its prior compatibility level.

These continuations supersede the classic-fraction/multi-bucket exclusions above.
The imported Mimir math corpus now has **875 evaluations in 70 files**, with exact
source ranges/hashes and unchanged input/output rows. Normal replay requires no
Go/network. Existing limits and native/storage/keyed bytes remain unchanged;
upgrade query applications. Evidence is in `.amp/in/artifacts/mimir-histogram-*`.
All work remains local, uncommitted and unpushed; provider/client/capacity and full
annotation parity are not established.

### Native counter histogram zero-point extrapolation continuation

The complete eight-evaluation upstream extrapolation block fails numerically
before implementation (seed530), then passes on memory and native Parquet/S3
(seed531). Native `rate`/`increase` now limit left extrapolation by the original
first count divided by the reset-corrected count increase. This bounds one
shared factor, not individual buckets or the sum; gauge `delta` and instant
`irate` remain unchanged. Public controls cover reset-discarded first samples,
zero starts, flat counts, negative sums, form POST and positive/negative/zero/
custom buckets. Histogram controls and all imported math fixtures pass together
(140 selected tests, seed534).

Before this extrapolation continuation, full concurrent precommit passed 2324
tests, one skipped and 37 excluded (seed529, eight cases, 173.5s), and strict
Credo checked 447 files cleanly. These results cover the classic-fraction and
multi-bucket NaN corrections above, not the subsequent extrapolation change.

Full concurrent precommit including counter extrapolation passes 2328 tests,
one skipped and 37 excluded (seed535, eight cases, 297.4s).

### Last-pair gauge delta and custom-bound subtraction continuation

The complete ten-evaluation Mimir `idelta` block preserves all input/oracle rows,
including its final custom-bound reconciliation case. After admitting gauge hints
in count/sum ramps, both HTTP/storage paths reject before implementation
(seed537). `idelta` now subtracts only the last nonstale pair without counter
reset correction, time scaling or extrapolation. Native results are gauges;
mixed pairs/schema families omit with warnings, and either non-gauge histogram
warns while still subtracting. Per-source notices and shared native bucket/bound
work remain query-local and bounded.

Custom subtraction coarsens both inputs to their common bounds, mapping upper
buckets to +Inf with source-ordered compensated accumulation. Addition/reset
detection retain their older profiles; full reconciliation annotation parity
outside `idelta` remains open. Another **4983 comparisons** against the actual
pinned Go intersection/mapping/Kahan helpers match exact bucket geometry and
bit-exact finite counts, including sparse layouts, negative/subnormal counts,
NaNs and infinities. Public controls add decreasing gauges, disjoint/asymmetric
bounds, nanosecond observations, anchors/subqueries, form POST, tenant/source
isolation and scan/work/result/batch limits. No native/storage/keyed-byte change;
upgrade query-serving applications. Normal fixture replay needs no Go/network.

### Instant counter rates, custom resets and window delta continuation

The complete eleven-evaluation Mimir `irate` block first exposes missing gauge
warnings (seed541), then a numerical false reset after warning support (seed542).
Changed custom bounds no longer imply a reset: each input's buckets roll up with
plain source-ordered addition to common boundaries, including +Inf, and only a
decrease resets. Explicit yes/no hints, total-count decreases and bucket-family
changes retain precedence; matching-layout/exponential detection keeps the older
profile. All upstream cases pass through HTTP/memory and native Parquet/S3
(seed543). Another **9950 comparisons** against the actual pinned, unchanged
Mimir `FloatHistogram.DetectReset` agree over sparse layouts, subnormal/rounded
counts and reset/gauge hints, not merely a reimplementation of the helper.
Public controls distinguish finite/infinite/missing interval decreases, forced
hints and separate Parquet objects. Reset branches do not emit notices for
subtractions that never run; batch warnings/info remain source-local.

The adjacent complete four-evaluation `delta` block fails on missing non-gauge
warnings (seed547), then passes with whole-window mixed-type warnings and full
native outputs (seed548). Only endpoint histogram schemas/gauge hints govern
subtraction: intermediate schemas/hints are ignored, but intermediate floats
omit the whole result. Public controls cover this distinction, insufficient
samples, extrapolated custom buckets and isolated batch notices. All three
histogram-difference functions charge endpoint bucket/bound work. The fixture
adapter independently expands same-layout bucket-bearing ramps by repeated
field addition; it does not call Pulse's histogram arithmetic.

The imported Mimir math corpus now totals **890 evaluations in 72 files**:
621 instant and 269 range, replayed as **3022 HTTP requests across both adapters**
before separate Pulse controls. Source ranges/hashes and original input/oracle
rows are preserved. Custom addition, other-operation reconciliation notices,
complete native arithmetic/provider/client/capacity parity remain gaps. Upgrade
query-serving applications; native/storage/keyed bytes remain unchanged.

Full concurrent precommit including `idelta`, custom resets, `irate` and `delta`
passes **2343 tests**, one skipped and 37 excluded (seed550, eight cases,
211.5 seconds). Strict Credo checks 447 files cleanly.

### Custom-bound histogram addition and binary arithmetic continuation

The complete eleven-evaluation Mimir block at native_histograms.test:1224–1276
retains its three-step sum/avg, counting/grouping/sampling/set controls, binary
addition/subtraction, gaps and complete bucket outputs. It fails numerically
on both adapters before implementation (seed552). Generalizing the existing
custom subtraction mapper preserves primitive behavior first (seed551), then
addition coarsens both inputs to their common bounds with source-ordered
compensated accumulation. Binary +/- reports executed reconciliation info and
charges input buckets/bounds before mapping; subtraction marks results as gauges.
Unchanged upstream fixture replays pass on both adapters (seed553).

Another **9950 comparisons** against the actual pinned, unchanged Go
`FloatHistogram.Add` match compacted geometry, finite count/sum/bucket bits and
reset hints. This is separate from the equally sized reset-method comparison,
not a claim of 19,900 unique input pairs. Public HTTP controls cover asymmetric
layouts, reverse operands, instant/range aggregates, subtraction gauge identity
through a subquery, per-source info and shared query/batch work (seed555).
Legacy differing-bound primitive expectations intentionally follow Mimir's
coarsening rather than Prometheus 3.5.0's rejection.

The current imported Mimir math corpus is **901 evaluations in 73 files**:
621 instant, 280 range, **3044 HTTP requests across both adapters** before
separate controls. All 294 math/primitive tests pass together after final style
adjustments (seed558). Full concurrent precommit passes **2347 tests**, one
skipped and 37 excluded (seed557, eight cases, 173.9 seconds); strict Credo is
clean across 447 files. No storage/native/keyed-byte changes; upgrade query
applications. Aggregation/range-counter reconciliation notices, reset-conflict
warnings and complete provider/client/capacity parity remain open. All work
remains local, uncommitted and unpushed.

### Native histogram range/group aggregation annotation continuation

Two complete pinned Mimir blocks add 21 unchanged evaluations from
native_histograms.test:1294–1387 and 1389–1410. Both adapters first fail on
missing notices (seeds559/563), then pass without changing source expectations
(seed565). The fixture reader now tolerates original trailing histogram-field
whitespace; source bytes remain identical. Sum/avg and their over-time forms
report custom reconciliation, mixed samples, incompatible families and original
reset/no-reset conflicts. Tracking original hints avoids hiding conflicts
behind intervening gauge/unknown hints. Diagnostic scans stop at the first
incompatible family and retain prior notices; grouped samples preserve their
original metric names. Input bucket/bound work charges shared query/batch limits.

Public memory/S3 controls cover both functions, cross-object windows, stale
inputs, failed-family prefixes, original names, independent groups, batch
isolation and whole-query work exhaustion. The imported corpus now contains
**922 evaluations in 75 files**: 642 instant and 280 range, replayed through
**3128 HTTP requests across 150 fixture wrappers** before separate controls.
The combined math/primitive suite passes 300 tests before the final vector
controls (seed564). Final concurrent precommit passes **2355 tests**, one skipped
and 37 excluded (seed566, eight cases, 138.9 seconds). Strict Credo is clean
across 447 files. No native/storage/keyed-byte changes; upgrade query applications.
Counter-range notices, implicit iterator-generated reset hints and complete
aggregation precision/annotation/provider/client parity remain open. Work is
local, uncommitted and unpushed.

### Native histogram counter-range annotation continuation

The complete pinned native_histograms.test:1096–1147 block adds seven unchanged
evaluations, including gauge rates, nested histogram-count calls and successful
first-pair family resets. Both adapters fail on missing gauge notices before
the fix (seed567) and pass afterward. Rate/increase reconciliation notices now
describe actual endpoint subtraction and reset-recovery additions, not arbitrary
middle layout changes. First-reset discarded layouts retain their original
gauge warnings; failed middle-family validation replaces only that window's
earlier gauge notices. Constant-size fact sets and precharged bucket/bound work
preserve shared query/batch resource limits.

Public controls distinguish no-op middle layouts, subtraction-only,
addition-only and combined reconciliation, error precedence, stale/short/mixed
windows, source isolation and whole-query work exhaustion. The independently
audited corpus contains **929 evaluations in 76 files**, with 649 instant and
280 range evaluations producing **3156 HTTP requests across 152 wrappers**.
Full concurrent precommit passes **2359 tests**, one skipped and 37 excluded
(seed570, eight cases, 185.0 seconds); strict Credo, warnings-as-errors compile,
format and whitespace checks pass. Implicit iterator-generated reset hints and
complete aggregation precision/annotation/provider/client parity remain open.
No native/storage/keyed-byte change; upgrade query applications. Work remains
local, uncommitted and unpushed.

### Native histogram compensated aggregation continuation

The complete native_histograms.test:1412–1584 selection adds 26 unchanged
evaluations, preserving disabled upstream tests as comments rather than counting
them. Both adapters fail on cancellation before the change (seed571). Native
sum/avg and their over-time forms now retain separate count/sum/zero/bucket
compensation through resolution, custom-bound and zero-threshold changes.
Averages retain direct sums until a candidate histogram field overflows, then
switch to weighted incremental means without losing the prior compensation.
Binary addition remains uncompensated. The fixture reader independently derives
negative/zero as well as positive buckets; no source expectations were changed.

All 26 evaluations pass on memory and S3/Parquet, alongside public cross-object
and grouped controls for cancellation during resolution/custom/zero changes and
bucket/zero-field overflow without count overflow (seed574). Another 10,000
chains execute 55,112 calls to the actual, unchanged pinned Go `KahanAdd`,
matching compacted geometry, finite count/sum/zero/bucket bits, nonfinite classes
and result reset hints. These are primitive checks, not upstream engine tests.

The independently audited corpus contains **955 evaluations in 77 files**:
675 instant and 280 range, replayed through **3260 HTTP requests across 154
fixture wrappers**. Full concurrent precommit passes **2363 tests**, one skipped
and 37 excluded (seed575, eight cases, 171.0 seconds). Strict Credo, formatter,
compile and whitespace checks pass. No native/storage/keyed-byte change; upgrade
query applications. Implicit iterator reset hints, complete annotation semantics
and provider/client/capacity parity remain open. All work is local, uncommitted
and unpushed.

### Native histogram reset-tail continuation

Closed Mimir's complete previous-bucket traversal after current exhaustion:
zero-prefixed missing populations now count as resets on either bucket side and
in matching custom layouts, including the +Inf tail. Zero-threshold widening
uses the pinned compensated traversal; explicit reset/no-reset hints retain
precedence. Both HTTP adapters fail the public regression before the fix
(seed576). Seven cases exercise resets/irate/rate/increase, separate source
objects, empty sides, missing tails after a matched prefix, all-zero nonreset
tails and hint overrides. The full math/primitive selection then passes 312
tests (seed577).

Another 50,000 calls to the actual unchanged pinned Go DetectReset agree:
25,000 exponential and 25,000 custom pairs, including schema/zero changes,
sparse sides, reset/nonreset outcomes and hint overrides. Counts are held equal
to force bucket/geometry decisions rather than mostly count-decrease shortcuts.
These are primitive comparisons, not 50,000 upstream engine evaluations.

### Native histogram negative-scaling continuation

Closed negative multiplication/division and unary-negation gauge identity,
including its preservation through nested arithmetic and double negation.
Positive factors, signed zero and NaN retain input hints; division by either
zero drops ordinary buckets without changing hints. Both adapters fail the
nested delta warning regression before the fix (seed578). Five nested forms
now preserve delta results without gauge warnings, warn for counter rate, and
retain a positive-scaling counter control. Primitive Sub still preserves its
receiver's hint; its reverse-value unit oracle no longer mistakes Mul(-1)'s
new gauge hint for primitive subtraction semantics.

The complete native_histograms.test:955–1060 block adds 25 unchanged evaluations
for scalar/vector multiplication/division, zero division, unary negation and
incompatible arithmetic notices. HTTP expectation mapping follows the actual
upstream iterator: only positive zero counts, including +Inf, are buckets;
negative/NaN zero counts remain omitted without rewriting fixture fields.
Another 26,000 actual pinned Go Mul/Div calls agree on full geometry, finite
field bits, nonfinite classes and reset hints, including signed zero, overflow,
subnormals, NaN and infinite factors. These are primitive validations, not
additional engine evaluations. Combined math/primitive tests pass 316 (seed580).

The audited corpus now contains **980 evaluations in 78 files**: 700 instant
and 280 range, replayed through **3360 HTTP requests across 156 fixture
wrappers**. Full concurrent precommit passes **2369 tests**, one skipped and
37 excluded (seed581, eight cases, 157.7 seconds). Strict Credo checks all 447
source files without issues; compile, formatter and whitespace checks pass.
Intentional blocked-native deadline controls still log timeouts; the historical
load-sensitive query-timeout/capacity investigation remains open. No resource
ceilings were raised. Upgrade query apps; no native/storage/keyed-byte change.
Implicit iterator-generated reset hints, remaining native operations and complete
annotation/provider/client/capacity parity remain open. Work is local,
uncommitted and unpushed.

### Native histogram trimming continuation

Closed Mimir histogram `</` and `>/` for scalar and matched float-vector
cutoffs. The complete native_histograms.test:2181–2678 block adds 124 unchanged
evaluations, replayed as instant and one-step range queries over both storage
adapters (496 requests). It preserves logarithmic exponential and linear custom/
biased-zero interpolation, explicit infinite endpoints, chained trims, ordinary
matching/grouping and fraction identities. Changed populations recompute count/
sum in positive/negative/zero source order; no-op trims preserve original totals
and layout. Names/reset hints survive. Invalid matched types omit with info;
bool and scalar-only trims reject before storage. Scalar-only rejection is
stricter than upstream syntax admission, which reaches an unsupported scalar
engine operation. The unchanged application rejected both fixture wrappers
with HTTP400 (seed582).

Public controls cover complete outputs, form POST, tenant isolation, gauge/
counter hints through nested delta, immutable source reuse and request-local
notices in both query-batch orders. Wide custom bounds distinguish ordinary
selection from trimming work; shared batch exhaustion fails whole before
conversion. Sample/result and native physical-scan ceilings remain enforced.
Parser/formatter regressions cover precedence, associativity and admission.
Combined math/primitive/parser checks pass 355 (seed587); strict Credo passes
across 447 source files after splitting coherent infinite/zero-bound cases.
Full `mix precommit --seed 588 --max-cases 8` passes 2376 tests, with one
skipped and 37 excluded, in 194.4 seconds; no resource limits were raised.

An additional 49,840 actual unchanged pinned Go TrimBuckets calls match every
finite field bit, signed zero, nonfinite class, layout and hint. Go 1.25.10 is
built with `-gcflags=all=-d=fmahash=n`, matching Pulse's pre-existing unfused
histogram profile. Default arm64 FMA execution exposes rounding and finite
cancellation versus overflowing unfused products; it is deliberately not claimed
as bit parity. Source comparisons confirm no upstream runtime code changed.
The corpus is now 1104 evaluations/79 files, 824 instant/280 range, 3856 HTTP
requests/158 wrappers. No native/storage/keyed-byte change; upgrade query apps.
Implicit iterator hints, full annotation/provider/client/capacity acceptance
remain open.

### Native histogram properties and retained-bucket continuation

The complete native_histograms.test:1–35,321–415,2680–2735 blocks add 37
unchanged evaluations, replayed as instant and one-step range queries over both
adapters (148 requests). They cover empty exponential/custom histograms,
count/sum/average, sparse positive/negative buckets, geometric-midpoint
variance/deviation, NaN/infinite sums and bucket-sensitive equality/inequality,
changes and distinct-value counts beneath count/sum/timestamp/absence wrappers.
Those numerical operations were already implemented; this closes missing
permanent upstream regression coverage rather than claiming new functions.

New Pulse controls reproduced two missing work charges on both memory and S3:
variance/deviation (seed590) and histogram equality/inequality (seed594) returned
success instead of `query_work_limit`. Both now reserve bucket slots and custom
bounds before traversal. Empty slots and sparse bounds still cost work;
false/`bool` comparisons cannot hide it beneath constant-time wrappers.
Count/sum/average alone do not pay for unused geometry. Controls cover positive
admission, exact outputs, repeated range steps and shared query-batch exhaustion
without publishing partial results. The eight focused checks pass (seed595).
No native/storage/keyed-byte change; upgrade query-serving applications for
stricter work accounting. Source ranges/hashes and offline reproduction are in
the fixture README. Corpus totals are 1141 evaluations/81 files, 861 instant/
280 range, 4004 HTTP requests/162 wrappers. This does not close implicit iterator
hints, full annotation/provider/client/capacity acceptance or other protocols.
Full `mix precommit --seed 596 --max-cases 8` passes 2384 tests, one skipped
and 37 excluded, in 158.8 seconds; strict Credo checks 447 files without issues.

### Native histogram fundamentals and interpolation continuation

The complete selected native_histograms.test:36–319,1062–1094 blocks add 65
unchanged evaluations, covering repeated/accumulating histograms, resolution
changes, positive/negative/zero/custom buckets, newest-sample selection,
`sum(last_over_time(...))`, rates and bucket-only resets despite growing total
counts. The independent test-only loader now handles finer-schema increments,
empty increments and disjoint sides/offsets. All seven source ramps/149 generated
samples match actual pinned Go `Copy().Add()` under exact `Equals` and hint
comparison; no production arithmetic produces the fixture inputs. Existing
numerical operations pass unchanged. Full precommit seed599 passes 2386 tests,
one skipped and 37 excluded, in 198.0 seconds.

The complete native_histograms.test:417–953,1147–1202 interpolation and constant-rate
blocks add another 147 unchanged evaluations (588 HTTP requests across both
adapters). They cover positive/negative/mixed exponential quantiles and fractions,
biased/symmetric zero buckets, multiple resolutions, inverse identities,
infinite/NaN/empty endpoints and zero-rate downstream functions. These numerical
paths were already implemented; this closes permanent regression coverage gaps.

New Pulse controls reproduce a separate scaling-work bypass on both adapters
(seed600): multiplication beneath `histogram_count` returned success despite a
lower work cap than its bucket traversal. Multiplication, nonzero division and
unary negation now reserve bucket slots before traversal, including empty slots
and multiplication by zero. Scalar/vector operand orders, exact results,
repeated steps and shared batches are covered. Unary plus and division by zero
do not traverse buckets; unused custom bounds are not charged by scaling. The
four focused interpolation/scaling checks pass (seed603). Corpus totals are now
1353 evaluations/83 files, 1072 instant/281 range, 4850 HTTP requests/166 wrappers.
Upgrade query applications for stricter work accounting; no native, storage or
keyed-byte change. Implicit iterator hints, full annotations and provider/client/
capacity acceptance remain open. Historical load-sensitive timeouts are not
closed by these passing assertions; no resource ceilings were raised.
Full precommit seed604 passes 2390 tests, one skipped and 37 excluded, in
150.5 seconds. Strict Credo checks 447 files without issues.

### Binary histogram warning continuation

The complete ours/binary_operators.test:189–345 blocks add 25 unchanged
evaluations (19 instant, six range; 88 HTTP requests across both adapters).
They preserve full float/histogram timestamp grids, one-to-one matching,
scalar/vector operand order, invalid-type info notices, incompatible-family
warnings and custom-bound reconciliation info. The upstream fixture fails on
both adapters before the change because binary addition silently omitted an
incompatible exponential/custom pair without the expected warning (seed605).

Binary addition/subtraction now publish the missing incompatible-layout warning.
Successful arithmetic with directly conflicting explicit reset/no-reset hints
retains the computed value with the pinned collision warning. Unknown/gauge or
identical hints alone do not create a collision; schema rejection precedes hint
diagnostics. Separate Pulse controls reproduce the missing collision warning
before the change and cover both operand orders, values, controls and per-source
query-batch isolation. All four focused checks pass (seed606). No production
numerical algorithm or native/storage/keyed-byte change is required. Upgrade
query apps for notices. The source hash matches a fresh pinned download; source
selection and offline reproduction are recorded in the fixture README.

Corpus totals are now 1378 evaluations/84 files, 1091 instant/287 range,
4938 HTTP requests/168 wrappers. AST positions, implicit storage-iterator hints,
complete annotation/provider/client/capacity acceptance and other protocols
remain open. Work remains local, uncommitted, unpushed and undeployed.
Full `mix precommit --seed 607 --max-cases 8` passes 2394 tests, one skipped
and 37 excluded, in 151.4 seconds. Strict Credo checks 447 files without issues.
Existing fault-test timeout/CAS/URI diagnostics remain visible; this passing
run does not close historical load-sensitive reliability or capacity findings.

### Complete classic-histogram fraction continuation

The entire pinned upstream/histograms.test:1–1327 file adds 183 unchanged instant
evaluations, each also replayed as a one-step range on both memory and native
S3/Parquet storage. They retain paired classic/custom-native inputs, quantiles
and fractions, positive/negative/zero-crossing and infinite-width buckets,
aggregation, rates, duplicate numeric bounds, empty distributions and resets.
Commented upstream cases remain disabled and uncounted. Three NaN-boundary
evaluations duplicate the earlier fractions selection; totals count replays.

The loader retains classic samples and independently derives custom-native
samples for all 34 load_with_nhcb blocks. All 419 generated inputs match the
actual pinned TempHistogram.Convert, including exact compacted populations,
custom bounds, geometry and reset hints. This checks test input construction;
the unchanged upstream DSL supplies output expectations. Ordinary replay needs
neither Go nor network. Source hashes and reproduction are in the fixture README.

The full fixture failed on both adapters before the production fix (seed609):
custom buckets crossing zero incorrectly used exponential zero-bucket clipping.
Custom fractions now retain those bounds and use zero as the lower bound only
for a first custom bucket with positive upper bound. First negative-infinite
buckets contribute their full count at finite interior bounds. Linear
interpolation computes the width fraction before population multiplication,
matching pinned Bucket.FractionBelow and avoiding intermediate overflow/underflow.
An additional public native-histogram regression checks exact 0.5 fractions for
huge/tiny custom and exponential-zero populations and widths.

Both complete fixture wrappers pass (seed610); all 31 native histogram unit
checks pass (seed612). Corpus totals are 1561 evaluations/85 files,
1274 instant/287 range, 5670 HTTP requests/170 wrappers. Upgrade query apps for
corrected answers; no native, storage or keyed-byte change. Other native
annotations, modifiers, protocols and provider/client/capacity acceptance remain
open. Work remains local, uncommitted, unpushed and undeployed.

The continuation also retains 24 unchanged evaluations in existing selections:
all twelve paired classic/custom-native NaN-sum quantile/fraction cases, three
cross-schema subtractions (including negative bucket populations), one
`@ start()`-anchored last-over-time subquery, two complete mixed float/native
range grids, three shared-source property/quantile queries and three custom
`irate` reconciliation/reset cases. They pass through both adapters (seeds614,
616). These previously implemented numerical paths now have permanent upstream
HTTP regressions; no HistogramStatsIterator optimization is introduced. The
repeated plural-quantile case duplicates an earlier selection and remains counted
as a replay. Six additional custom-native inputs bring the independent converter
audit to 425 inputs across 35 blocks, including NaN sum classification.

Final corpus totals are 1585 evaluations/85 files, 1295 instant/290 range,
5760 HTTP requests/170 wrappers. All 31 native histogram checks pass again
(seed615), and strict Credo checks 447 files without issues. The intermediate
full precommit seed613 passed 2397 tests, one skipped and 37 excluded, in 133.3s.
The later ten-check arithmetic run took 189.8s; the host reported load averages
729.12/616.57/394.63 shortly afterward. This is consistent with runner contention,
not provider capacity acceptance or closure of historical timeout findings.
No resource ceiling or test timeout was increased.

### Classic quantile extreme-count continuation

Public HTTP regressions first reproduced two further failures on both memory
and native S3/Parquet: subnormal cumulative counts returned a finite quantile
instead of upstream NaN (seed619), and sums of large finite counts caused valid
queries to return HTTP400 (seed620). Classic quantile repair now uses the pinned
almost.Equal minimum-normal absolute floor, maximum-float-capped relative scale
and strict comparison, with IEEE-safe intermediate arithmetic. Six additional
public controls preserve both zero and nonzero subnormal operands, the exact
absolute-floor boundary, large near-equal counts and real large decreases with
their repair notice. The initial wrappers pass after the correction (seed621);
the complete six-control version passes in the full module run (seed622).

An independent temporary executable used the actual pinned Go BucketQuantile,
coalesceBuckets, ensureMonotonicAndIgnoreSmallDeltas and almost.Equal functions,
not Pulse-derived expectations. All 10,030 results and repair flags agree:
10,010 results are numerically exact and 20 differ by less than 1e-12 relative
error; repair flags match exactly. Inputs include normal/subnormal/huge finite
counts, signed zeros, NaNs, infinities and decreasing counts. Source hashes are
recorded in the fixture README; ordinary regression replay needs no Go.

Five more unchanged upstream range evaluations extend the existing custom
arithmetic and grouped-aggregation fixtures: equality/inequality preserve the
full changing timestamp grid, ordering omits results with info, and sum/average
retain pure-schema steps while omitting the mixed exponential/custom step with
a warning. Complete inputs, expectations and source selection bytes remain
unchanged. All 312 checks in the HTTP math conformance module pass (seed622).
Current corpus totals are 1590 evaluations/85 files, 1295 instant/295 range,
5770 HTTP requests/170 wrappers. Upgrade query applications; no native ABI,
storage, keyed bytes, timeout or resource ceiling changes.

The earlier broad precommit seed617 had one failure: the unchanged 60-second
Tempo special-character discovery test, making 152 sequential HTTP requests,
timed out waiting for HTTP receive. It passed in isolation with the identical
seed and default timeout in 15.0s; no timeout was relaxed. The next complete
precommit seed618 passed all 2397 tests, one skipped/37 excluded, in 417.0s.
Host load was above 400 during the rerun, consistent with contention but not
proof of the sole cause. Historical timeout findings remain open; these runs
are not deployed-provider or capacity acceptance.

The corrected histogram code also passes the complete precommit seed623:
2397 passed, one skipped/37 excluded, in 374.3s. Strict Credo checks all 447
source files without issues after correcting two numeric-literal style notices.

### Tempo special-character deadline granularity

The pinned upstream TestTagValuesWithSpecialCharacters uses separate t.Run
cases per key/scope/WAL-or-backend phase. The Elixir port had collapsed its
152 JSON/protobuf retrievals into one 60-second ExUnit deadline. It now uses
four independent scope/window tests, with 38 retrievals each. Every fixture
still ingests all 19 pairs together and restarts manifest supervision. The full
response and protobuf expectations, both windows/scopes and separate slash
routing checks remain unchanged. This adds three fixture setups; it neither
speeds up queries nor changes a production deadline.

Instrumented replay of seed617 passes all four cases in 1.8–5.3s each, 18.5s
total, with timeout=60000 and trace=false. No slowest/trace option relaxes the
deadline. This reduces accumulated per-test work without dropping coverage,
not proof of the sole historical timeout cause or provider capacity. The
public Tempo module now has 65 wrappers; this increase is test organization,
not additional upstream compatibility scenarios.

The final precommit seed625 passes 2400 tests, one skipped/37 excluded, in
294.9s. All four special-character cases complete in 3.0–5.4s each with the
ordinary timeout=60000 and trace=false, including the full-suite contention.
The separate slash check also passes. Strict Credo checks all 447 files with
no issues. An independent fixture audit confirms 1590 evaluations across 85
files, 1295 instant/295 range; all 82 continuation digest-table entries match.
The three original basic-math/collision files remain separately documented.
These are local results, not commits, publication or deployed-client acceptance.

### Loki timestamp and Unix-time template continuation

The next bounded formatter gap is original entry time. Both line_format and
label_format now expose typed __timestamp__ and unixToTime/unixEpoch/
unixEpochMillis/unixEpochNanos. Source nanoseconds survive line rewrites and
variable/with scopes. Unix parsing follows the pinned helper's five byte-length
units, including signs/leading zeros, int64 admission/wrapping and floor-based
pre-epoch seconds/milliseconds. Time values retain equality/truthiness and render
in UTC deliberately, not host-local time. Arbitrary date layouts, named zones,
time methods and now remain open. No native/storage/keyed-byte/dependency,
resource ceiling or production deadline changes; upgrade query applications.

Three async HTTP/S3 wrappers retain seven complete original Loki formatter rows
and both invalid-time inputs, plus separate timestamp-boundary, scope, wrapping,
type/arity and metric-error-selection controls. Inputs/labels/templates/source
timestamps stay unchanged except selector isolation and freezing upstream's
host-local output in UTC. Provenance and source hashes live in the Loki fixture
README. The initial public regression fails before implementation (seed626);
the upstream wrapper passes seed627, and all three wrappers pass seed628.
All 444 existing Loki upstream/LogQL checks pass seed629 with ordinary timeouts.
Strict Credo checks 447 files without issues after dispatch complexity is fixed.

An independent temporary Go 1.25.10 executable extracts the actual pinned Loki
Unix helpers and Sprig v3.3.0 unixEpoch, then executes Go text/template with the
original timestamp closure under UTC. All 28,292 line/label pipeline comparisons
agree, including 100 runtime errors, excluding diagnostics. Signed-int64 source
times, all unit widths, sign/zero variants, subsecond boundaries, overflow,
scoped values and wrong types/arity are exercised. This is helper/pipeline
evidence, not a full Loki service, distributed topology or deployed-client test.
Ordinary retained regressions need no Go, downloads or external service.

Final full precommit seed630 passes 2403 tests, one skipped/37 excluded, in
239.3s with four concurrent cases and ordinary timeouts. The complete current
Mimir/Loki/Tempo corpus is included; provider/deployed-client/capacity and
historical load-sensitive timeout/lifetime findings remain open. All work is
local and uncommitted, not published or deployed.

### Mimir repair-notice target correction

The pinned Mimir streaming engine deliberately passes four zero summary fields
to its classic quantile repair annotation, with an explicit comment deferring
annotation merging. Expanded time/bucket/difference summaries belong to its
vendored Prometheus engine, not the pinned MQE compatibility target. The
remaining-gap lists now distinguish that source fact from the genuine missing
AST positions and broader diagnostic parity. Source ranges and SHA-256 live in
the Mimir fixture README. The public memory/Parquet/S3 repair control now asserts
the exact generic message; 174 histogram-annotation checks pass seed631. No
production change is needed to match this Mimir behavior.

### Loki named-capture and literal-quoting continuation

Template count/replacement helpers now accept numeric and repeated ASCII capture
names in both Go spellings, without changing capture positions. Named expansion
selects the first participating capture, including an empty match before a later
nonempty match. Numeric reference parsing preserves leading-zero and one-billion
cutoff rules. Literal `\Q...\E` runs bypass capture/class interpretation,
terminate at the first `\E` or EOF, and retain last-character quantification.
Selector and regexp-parser admission is deliberately unchanged.

All 135 original replacement mode evaluations must now succeed; ten former
profile rejections are removed without changing their success oracles. The
public regression fails before the fix (seed632). Twenty-two retained controls
add capture/header/quoting boundaries, including all five original Go quoted
patterns; the initial quoting regression fails seed634. Four wrappers pass
seed635, including shared-work/output controls and both sides of the new
duplicate-lookup work boundary. Extra duplicate probes spend shared work in
both native passes, even when no bytes result; exhaustion still fails whole.

An independent standard-library Go executable extracts the three actual pinned
Loki helper functions, then executes them through Go text/template. All 97,332
comparisons against Pulse's real line/label pipelines agree, including 24,300
runtime errors, excluding diagnostic wording. The matrix covers 36 patterns,
18 inputs, 12 replacements, both replacement modes, counting, both formatting
stages and three label owners, plus the retained controls. This is helper/
pipeline evidence, not a full upstream service or deployed-provider test.

The expanded HTTP fixture publishes all 55 original/control rows together,
including the octal continuation below, avoiding one-row segment growth without
removing any input or relaxing timeouts.
Upgrade query-serving app/native pairs to log tuple `{1,1,10}`. Storage/keyed
bytes, configured ceilings and dependencies are unchanged. All 133 Rust tests,
strict all-target Clippy, Rust formatting and offline fixture regeneration/vet
pass. Before the octal continuation, full precommit seed637 passed 2403 tests,
one skipped/37 excluded, in 480.7s; all four final targeted wrappers passed
seed638 in 12.9s, and strict Credo checked 447 files cleanly. Timeouts remain
unchanged. The self-metrics worker warning comes from the test's deliberate
100ms deadline over a blocked GET; this does not establish that every historical
timeout/lifetime diagnostic is intentional or resolved. Work remains local,
uncommitted, unpushed and undeployed.

### Loki template octal regex-escape continuation

Template count/replacement helpers accept up to three octal digits, interpreted
as Unicode characters through 0777 rather than raw bytes. A lone zero is valid;
nonzero first digits require a second octal digit, preserving backreference
rejection. Quoted/escaped backslashes, classes, quantifiers and capture positions
retain their meanings. Selector/regexp-parser admission and existing budgets
remain unchanged; the addition shares the unreleased log tuple `{1,1,10}`.

Both original Go hex/octal parser-table patterns are retained with matching
controls on both sides of their ranges, alongside twelve additional successful
and four invalid controls. The upstream AST expectations remain provenance,
not invented HTTP oracles. Existing HTTP wrappers replay both formatting stages
and GET/form POST through native Parquet/S3; the original octal pattern fails
before implementation (seed639). Source ranges/hashes live in the Loki README.

All four expanded wrappers pass seed641. An independent Go executable using
the extracted pinned Loki helpers agrees with all 144,480 actual Pulse pipeline
executions, including 2,268 runtime errors, excluding diagnostic wording.
Every three-digit octal value is covered in five pattern contexts with neighboring
inputs; short/invalid/fourth-digit/quoted/escaped controls run too. Both formatters,
three label owners, four replacements, both modes and counting participate.
All 133 Rust tests and strict all-target Clippy pass. These are helper/pipeline
checks, not upstream service/provider/client/capacity acceptance.

Both independent oracle matrices are additionally replayed with Loki's exact
`grafana/regexp` dependency, `v0.0.0-20250905093917-f7b3be9d1853`, with
byte-identical outputs to the standard-library oracles. The final native
artifact repeats all 97,332 named/quoted comparisons without differences.
Offline/read-only fork build and vet pass; source and module checksums and
linked identity are recorded in the Loki README and fork audit log.

Final `mix precommit --seed 642 --max-cases 4` passes 2403 tests, one skipped
and 37 optional exclusions, in 249.3s. Strict compile, dependency, formatter,
Credo (447 files), Rust format and whitespace checks pass. Timeouts and resource
ceilings are unchanged. This does not close historical provider/load-sensitive
timeout/lifetime findings. Work remains local, uncommitted, unpushed and undeployed.

### Shared Loki/Mimir regex escape and repetition

The shared lexical guard now treats `\x{...}` as one escape instead of reading
its digits as a repetition counter. Valid following single/counted/lazy
repetition works, while malformed escapes and actual nested/possessive
repetition remain invalid. This changes the shared bounded regex profile;
Tempo predicates also consume this compiler, although this increment's HTTP
controls covered Mimir/Loki only. Native ABI, storage/keyed bytes and budgets
are unchanged. All query-serving native artifacts need the fix.

The existing Go fixture gains 399 independent matching answers (620 total,
original 221 unchanged). It includes the complete Go 1.27.3 hex parser-table
pattern, with matching inputs rather than invented AST/HTTP expectations.
Two local HTTP wrappers use the existing Mimir/Loki integration harnesses and
actual ingestion/Parquet/S3. Both fail on unchanged production code (seed643).
These controls are not extra upstream integration rows or full regex/service
acceptance. Fixture provenance lives in `test/fixtures/regex/README.md`.

Boundary checks also exposed accepted malformed lazy suffixes: `a???` and
`a{2}??` compiled natively, and the first returned HTTP200 with a selected row
instead of rejecting the query. Six executed Go rejection controls fail in
native/HTTP regressions before the second fix (seed646). The guard now permits
only one lazy suffix, preserving valid `a??` and counted lazy forms. Escaped
question marks and character classes do not become lazy-suffix state.

Both final public wrappers and native/reference controls pass seed647. All
620 retained matching answers and eight admission controls are byte-identical
with Loki's pinned `grafana/regexp` dependency. A separate temporary matrix
executes 4,608 grammar combinations: 960 accepted, 3,648 rejected, with 26,880
byte/string matching comparisons and no differences. The matrix covers literal,
hex, escaped-question-mark, class, capture and flag atoms, counted/single/lazy
repetition and following literal/class/escape boundaries. Its fork output is
also byte-identical; this is bounded compiler/matcher evidence, not full service
or capacity acceptance. All 133 Rust tests and strict all-target Clippy pass.

Final full precommit passes with seed648 and four concurrent test cases:
2,405 passed, one skipped and 37 optional tests excluded, in 191.1 seconds.
Strict Credo reports no issues across 447 source files. No timeout or resource
limit was relaxed. Changes remain local, uncommitted and unpushed.

### Shared Mimir/Loki/Tempo quoted and octal regex literals

The shared native compiler now normalizes `\Q...\E` quoting, including an
omitted terminal `\E`, and Unicode-valued octal escapes. Anchoring happens
after normalization, so an unfinished quote cannot swallow wrapper syntax.
Quantifiers bind to the final quoted character. Class quoting, backreferences,
invalid octals and existing unsupported grammar still reject. PromQL evaluation,
discovery, exemplars and label replacement; LogQL selectors, pipeline filters,
named captures and native metrics; and trace retained/window-local search,
filtered discovery and raw regex predicates all use the corrected paths.

Ordinary native patterns borrow their input. Changed patterns use one output
buffer, with no per-quoted-run or per-octal-character temporary allocation.
Trace consumers compile once with correct anchors instead of compiling the
same regex twice. Raw grouping balance is checked in the existing lexical pass
before wrapper insertion, including direct native calls. Loki `label_replace`
also closes an unfinished quote before adding its non-dot-all flag scope and
rejects malformed raw syntax before storage. Compilation stays bounded by the existing 1 MiB program/DFA
ceilings. No ABI/capability tuple, storage/keyed bytes, timeout, dependency,
feature gate or resource ceiling changes; upgrade all query-serving app/native pairs.

The existing Go corpus grows from 620 to 3,664 substring answers plus 1,140
whole-label answers, preserving the original 620 maps. It includes all five
complete Go 1.27.3 quote-parser patterns and the original octal pattern, with
matching oracles executed independently rather than inferred from private ASTs.
Thirty quote/octal patterns cover 38 inputs; another 1,904 controls cover all
14 POSIX classes with/without case folding and both forms of negation. They
exposed and fixed PCRE reference handling of folded named classes and complements.
All retained answers are byte-identical with Loki's pinned `grafana/regexp` fork.

Three new local `:regex_literals_batch` wrappers exercise real HTTP ingestion
and native Parquet/S3 through the existing upstream integration harnesses.
Mimir/Loki replay all 30 patterns over 15 values, positive/negative matchers,
GET/form POST, and separate label-replacement/discovery/exemplar/named-capture
controls. Tempo replays eight patterns over eight traces through resource/span
retained search, JSON/protobuf discovery and authenticated MCP window-local/raw
queries. These are local controls, not extra upstream integration rows or proof
of full Go regex/client/provider/capacity acceptance. Mimir/Loki and the shared
matcher fail before the fix (seed650); all three final wrappers pass seed657.

The first full run (seed658) caught two direct-native malformed-pattern
regressions after redundant compilation was removed. The lexical grouping
check restores rejection without compiling twice. All 371 tests in the affected
shared-regex/Mimir/Loki/Tempo/trace suites pass seed659, including the existing
native malformed-pattern regressions and added public Loki flag-scope controls.

A temporary independent Go matrix covers 3,896 accepted and 406 rejected
patterns, all 512 three-digit octals, quote/repetition/capture/class boundaries,
POSIX unions/complements, case folds and malformed grouping. Four native/reference substring/full
matching paths agree across 514,272 comparisons; invalid patterns reject through
all three native compilation entry points. All 133 Rust tests and strict
all-target Clippy pass. Evidence is under `.amp/in/artifacts/regex-literals-*`;
fixture provenance is in `test/fixtures/regex/README.md`.

### Shared counted regex repetition and literal braces

Go's 1,000-copy limit now applies to counted bounds and nested products before
automaton expansion. Leading-zero and malformed counts remain literal braces;
syntactically complete oversized counts reject. Invalid inner counts still
reject under outer zero, and a valid erased inner factor cannot erase a later
outer count's contribution. Braced hex/properties, classes and quote/octal
normalization retain their meanings.

Normalization allocates only when source text actually changes. A saturating
decimal scan avoids integer overflow and completes syntax recognition before
rejecting large numbers. Only patterns with actual counted repetition receive
an additional bounded AST parse and one postorder count walk. The direct
`regex-syntax` dependency reuses the already-locked 0.8.11 parser without new
packages/versions or Unicode table features. Ordinary patterns keep the
existing path; program/DFA/query ceilings, timeouts, ABI/capability tuples,
storage and keyed bytes stay unchanged. Upgrade every serving app/native pair.
POSIX-class lookahead also uses a fixed six-byte stack buffer instead of a
temporary heap string per class, preserving all existing admission decisions.

The separate frozen Go fixture retains 53 admission cases (39 valid/14
invalid), 27 compact inputs per accepted pattern and 1,053 answers each for
substring/full-label matching. Eight complete patterns come from the original
Go parser table; the rest are explicit local controls. Both shared fixtures
regenerate byte-identically with Go 1.27.3 and Loki's pinned regexp fork.
Three `:regex_admission_batch` HTTP tests replay all patterns through actual
Mimir/Loki/Tempo ingestion and native Parquet/S3, asserting invalid queries
perform no storage requests. These are local controls in upstream harnesses,
not extra upstream integration exports or full regex/client/capacity proof.

The shared test failed before normalization/count admission (seed 661); the
additional zero-erasure regression failed before the factor correction
(seed 663). All three HTTP wrappers pass seed 664, the six shared tests pass
seed 665, and all 133 Rust tests and strict all-target Clippy pass. A temporary
independent Go matrix checks 2,610 accepted/1,686 rejected patterns and 156,423
native/reference comparisons. PCRE's 177 execution-limit results are explicitly
unavailable references, never nonmatches; all native paths still agree with Go.
The existing 514,272-comparison matrix passes unchanged. Fixture/source hashes
and exact scope are in `test/fixtures/regex/README.md`; evidence is under
`.amp/in/artifacts/regex-admission-*`.

Full precommit passes seeds 666 and 667: 2,412 tests, one skipped and 37 optional
exclusions. Strict Credo reports no issues across 447 files. The final native
build passes all 133 Rust tests, strict all-target Clippy and both differential
matrices after the allocation-free POSIX lookahead change. No timeout or
resource-limit increases were needed.

### Shared literal character-class ampersands and tildes

Repeated `&&`/`~~` inside a Go character class are literal members, not Rust
intersection/symmetric-difference operators. The native normalization pass
escapes the repeated member before its existing dialect guard and compiler;
ordinary patterns borrow unchanged source, and changed patterns use the same
output buffer without per-member allocations. Negation, simple case folding,
leading `]`, POSIX/complement/Perl classes, octal/hex escapes and adjacent ranges
keep their meanings. Actual bad ranges still reject, rather than being repaired.
There is no PCRE execution fallback, new thread pool, extra storage read or
change to program/work/output ceilings, timeouts, native/capability tuples,
storage or keyed bytes. Upgrade all query-serving app/native pairs.

The new frozen fixture retains 32 local Go cases: 29 accepted, three rejected,
47 compact inputs per accepted pattern, 1,363 substring and 1,363 whole-label
answers. These are independent executed Go oracles, not additional copied
integration/table rows. All three frozen fixtures regenerate byte-identically
with Go 1.27.3 and the pinned Loki regexp fork. Refactoring only the producer's
common oracle emission leaves both older JSON fixtures byte-identical.

The shared matcher fails seed 668 and all three Mimir/Loki/Tempo HTTP wrappers
reject valid `[x&&y]` queries seed 669 before the fix. The existing wrappers now
replay both repetition and literal-class fixtures through real ingestion and
native Parquet/S3, retaining no-storage assertions for rejected patterns.
All 370 affected shared, metric-matcher, discovery and protocol tests pass
seed 670. The old discovery rejection control now uses actual invalid `[z-a]`
instead of valid `[a-z&&b]`; unimplemented nested-class forms still reject.
All 133 native tests and strict all-target Clippy pass. Full remaining literal
bracket/`--` class forms, capture-name admission, diagnostics and deployed
protocol/client/capacity parity remain open. Fixture scope and evidence are in
`test/fixtures/regex/README.md` and `.amp/in/artifacts/regex-classes-*`.

A separate Go matrix checks 7,184 accepted/eight rejected class patterns and
689,664 native/reference comparisons, with no unavailable PCRE results. Both
earlier matrices pass unchanged, including their explicitly counted 177 PCRE
execution-limit results. Full precommit seed 672 passes 2,412 tests, one
skipped and 37 optional exclusions; strict Credo reports no issues across
447 files. No production timeout, limit or concurrency increases were needed.

### Shared literal brackets and left-to-right class ranges

The class gap now excludes literal opening brackets and scalar hyphen ranges.
`[[]` matches `[`, while `[[ab]]` matches `[`, `a` or `b` followed by a literal
`]`; it is not a nested union. Go recognizes complete POSIX tokens only at a
member position, not as a scalar range endpoint. Hyphens consume one scalar at
each endpoint, so `[--x]` spans `-` through `x`, `[a-b--x]` includes two ranges,
and `[a--b]` rejects its descending range. Perl/Unicode class escapes cannot
be scalar endpoints. Earlier leading-`]`, folding, quoting, octal/hex and
counted-repetition policies remain intact, including admission after a class.

The existing native normalization pass tracks constant-sized lexical state,
borrows unchanged input and writes changes into its existing output buffer.
There is no per-member allocation, production PCRE fallback, additional storage
read, new thread pool or change to program/work/output ceilings, timeouts,
capability/native tuples, storage or keyed bytes. The independent PCRE reference
separately preserves member/range boundaries and literal colon classes.
Upgrade all query-serving app/native pairs.

Compile preparation also reuses normalized text when no ASCII-class/boundary
translation or anchoring wrapper is required. Unchanged patterns remain
borrowed through compilation; changed normalized strings move instead of
incurring a second full-pattern allocation/copy. A removed scratch ownership
check verified pointer identity for literals, ordinary/POSIX classes, escaped
punctuation and valid counted groups, with controls for required owned output
and rejection of excessive nested counts. Compiler-owned regex programs and
the existing counted-repeat AST check still allocate as required; this is not
an allocation-free compilation or throughput claim.

The frozen fixture retains 72 local Go cases: 56 accepted, 16 rejected and
61 compact inputs per accepted pattern, with 3,416 substring and 3,416
whole-label answers. It regenerates byte-identically with Go 1.27.3 and Loki's
pinned regexp fork; all three earlier fixtures remain byte-identical. These
are executed independent matching controls, not additional copied upstream
integration/table rows. Fixture scope, source hash and reproduction are in
`test/fixtures/regex/README.md`.

All three Mimir/Loki/Tempo HTTP wrappers reject valid `[[]` before the fix
(seed 673), then replay the new fixture through ingestion and native Parquet/S3
with no-storage assertions for invalid patterns. All 375 affected tests pass
seed 677. The old metric rejection control now accepts literal `[[ab]]`, with
`[z-a]` retaining real invalid-range coverage. A separate independent Go matrix
checks 14,388 accepted and 351 rejected patterns, with 1,496,352 native and
PCRE-reference substring/full-label comparisons and no unavailable results.
All 133 native tests and strict all-target Clippy pass. Capture-name admission,
exact diagnostics and full protocol/client/provider/capacity parity remain
open. Evidence is under `.amp/in/artifacts/regex-ranges-*`.

### Shared raw-header and inline-flag continuation

Native regex preparation validates raw capture/modifier headers before literal
normalization. Nonempty ASCII capture names remain available; Unicode,
punctuation and quoted/octal/hex repairs of raw header syntax reject. This
closes erroneous acceptance, not numeric/repeated selector-name support.
The 44-case name fixture retains two original Go parser-table patterns,
16 accepted/28 rejected cases and 624 substring plus 624 whole-label answers.
The old compiler accepted 19 Go-invalid patterns; all three HTTP wrappers
failed before implementation (seed 680). All 375 affected tests and the
1,496,352-comparison range matrix passed the header-only checkpoint (seed 681).

Empty and repeated inline flags also follow Go, with disabling precedence,
group-scope restoration and preserved atom binding and `U`/lazy capture
greediness. Flag directives do not create atoms: `x(?)*` repeats `x`.
Quantifiers after directives still bind to an earlier unquantified atom without
retroactively changing that atom's flags. Consecutive directives combine once;
raw invalid headers and excessive counted bounds still reject. Flag-separated
repetition of an already quantified atom remains unsupported and rejects,
rather than accidentally becoming a lazy suffix.

The 58-case flag fixture retains one original Go parser-table pattern,
43 accepted/15 rejected cases and 1,892 substring/whole-label answers each,
plus complete anchored capture maps. PCRE comparisons use Go's printed AST
for flag rows because PCRE's raw directive/quantifier grammar differs; native
paths always compile the original source. All six producer modes reproduce
byte-identically with Go 1.27.3 and Loki's pinned regexp fork. These are actual
independent matching/capture oracles, not additional Mimir/Loki/Tempo integration
exports. All three HTTP wrappers rejected valid `(?)` at the baseline (seed 682).

Header parsing uses borrowed iterators, flag masks and the existing output
buffer, without per-header strings. A group-scope stack is needed only when
the pattern contains `U`. Ordinary unchanged patterns remain borrowed; no
new thread pool, production PCRE fallback, timeout/resource increase, native
ABI/capability change or storage/keyed-byte change is introduced.

LogQL's native matcher is the admission authority; PCRE supplies diagnostic
wording only after a native rejection, except for remaining named-parser
metadata inspection. Trace BEAM/reference search/discovery predicates now use
existing compiled native boolean resources instead of constructing capture
maps for true/false checks. Input bytes stay borrowed through those calls;
actual capture-producing label replacement remains unchanged. No measured
throughput or deployment-capacity claim follows.

A removed scratch Rust replay agrees with Go on 178,444 matching/capture
checks across both frozen fixtures and a separate header/flag/quantifier matrix;
all 133 native tests and strict all-target Clippy pass. Evidence is under
`.amp/in/artifacts/regex-{names,flags}-*`. Remaining numeric/repeated selector
names, flag-separated nested
repetition, exact diagnostics and full protocol/client/provider/capacity
acceptance stay open; the parser metadata restriction is closed below.
All 400 affected tests pass seed684; full precommit seed685 passes 2,412 tests,
one skipped and 37 optional exclusions. Strict Credo is clean across 447 files.
The additional native/reference matrices pass 169,004 header/flag and
1,496,352 class/range comparisons. Upgrade all query-serving app/native pairs.

### Native regexp-parser metadata admission

Closed the extra PCRE grammar restriction on LogQL `regexp` parser admission.
The compiled native byte-regex resource now answers whether it contains any
named capture, without producing names/capture maps, reparsing the pattern in
another engine or examining input lines. The existing dialect-validation pass
records presence before HIR optimization, so zero-repeated captures retain
their prior admission. This does not establish erased-capture extraction parity.
The public stage still requires a real named capture and keeps nonmatching
lines without extracted labels.
Native Boolean admission runs on the existing dirty-CPU pool; no new threads,
regex cache, provider reads or larger resource ceilings are introduced.
Matching log app/native pairs require tuple `{1,1,11}`; trace/metric tuples,
storage formats and keyed encoder bytes are unchanged.

The existing Go flag fixture adds independent unanchored named-capture maps
and ordered capture names; every earlier admission, matching and anchored
capture oracle remains unchanged. Eight named patterns provide 352 capture
oracles. One HTTP/S3 wrapper replays all eight over eleven retained inputs,
asserting exact log labels, nonmatch preservation, GET/form POST and metric
filters through native Parquet. The original six Loki regexp constructor rows
remain intact, with four separately identified metadata controls for quoted/
class fake headers, unnamed flag directives and a zero-repeated named group.
These are local Go-executed controls around the pinned Loki constructor
contract, not additional exported upstream integration/table rows.

Before implementation the new HTTP regression fails with PCRE's
`quantifier does not follow a repeatable item` (seed686). Evidence is under
`.amp/in/artifacts/regex-parser-flags-*`. All 449 targeted tests pass seed690;
full precommit seed691 passes 2,413 tests, one skipped and 37 optional exclusions.
All 133 native tests and strict all-target Clippy pass; the 169,004 header/flag
and 1,496,352 class/range native/reference comparisons pass unchanged.
Numeric/repeated selector names,
flag-separated nested repetition, exact diagnostics, other Go regex forms
and full protocol/client/provider/capacity acceptance remain open.

A separate local probe executes 20,000 matching calls in each of three rounds
on both old capture-producing and new Boolean trace predicates. All answers
agree. The old path performs 879 BEAM minor collections per round; Boolean
matching performs zero. Timings vary and establish no CPU/throughput advantage,
total native-memory bound or deployment-capacity result. Evidence is retained
in `.amp/in/artifacts/trace-regex-boolean.log`.

### Shared Unicode-property caret negation

Closed the shared native rejection of Go `\p{^Name}` and `\P{^Name}` syntax,
including class unions/negation, case folding and following quantifiers. Go's
leading caret toggles `p`/`P`; quoted text and escaped backslashes stay literal.
The existing Rust normalization pass performs the rewrite in its output buffer,
with no per-entry allocation/conversion, new threads or further capability,
storage/keyed-byte, program/work/deadline changes.

The new frozen fixture retains 37 actual Go admission cases (30 accepted,
seven rejected), with 53 compact inputs per accepted case: 1,590 independent
substring and 1,590 whole-label answers, plus exact indexed/unanchored named
capture maps. Nine complete original patterns come
from Go 1.27.3 `regexp/syntax/parse_test.go:99–107`; their private ASTs are not
matching oracles. Other patterns/inputs are local controls. All previous producer
modes/fixtures remain byte-identical, and the new fixture matches Loki's pinned
regexp fork byte-for-byte. Ordinary replay needs no Go or network access.

The shared matcher covers all Unicode/Braille boundaries and malformed controls.
All three existing Mimir/Loki/Tempo HTTP/S3 wrappers add the new fixture using
their original eight stored ASCII/repetition inputs, retaining negative-filter
and pre-storage rejection controls. The named-parser wrapper additionally replays
the Latin-property capture over its eleven stored values, including Kelvin sign,
asserting exact log labels, GET/form POST and metric filtering; the original
eight flag cases are unchanged. Every admission wrapper fails on valid
`\p{^Braille}` before implementation (seed693), as does the shared matcher
(seed692). Evidence is under `.amp/in/artifacts/regex-unicode-*`.
All 449 targeted tests pass seed694, along with all 133 native tests, strict
all-target Clippy and strict Credo across 447 files. A separate 1,386-pattern
Go matrix matches the pinned Loki fork byte-for-byte and passes 90,480
native/PCRE-reference comparisons. Direct Rust replay of that matrix and the
final frozen fixture passes 74,220 matching/capture checks across 810 accepted and
613 rejected patterns, including the native string engine.
The final expanded capture replay and parser HTTP wrapper pass seed696;
full precommit seed697 passes 2,413 tests, one skipped and 37 optional exclusions.
Strict Credo remains clean across 447 files. The earlier 169,004 header/flag,
1,496,352 class/range and 178,444 direct Rust checks also pass after this change.
Temporary producers, matrices and executables were removed; fixture producers
and bounded artifact logs remain.
Full Unicode property-name/version admission, zero-erased capture extraction,
numeric/repeated selector names, flag-separated nested repetition and full
regex/client/provider/capacity acceptance remain open.

### Original capture-schema continuation

The optimized-away capture gap is closed for the supported query-regex profile.
Rust HIR can erase capture declarations, not just their values. The unchanged
compiler loses trailing numeric groups in Go's `(a)(((b))){0}c` case and lets a
later parser overwrite an erased named capture (seed698). Compilation now records
original indices and names in the existing validation pass. Ordinary log/tail
extraction, indexed metric capture maps and native metric stages use that schema;
an erased group publishes an empty value on a match, while a nonmatch adds none.
Later live groups do not shift and first-extraction ownership remains intact.

`erased-capture-controls.json` freezes 28 executed Go patterns over 21 inputs,
with 588 substring and 588 full-label decisions plus exact capture maps. The
first four patterns are the complete zero-repetition patterns in Go 1.27.3
`regexp/all_test.go:232–235`; their substitution expectations are not mislabeled
as capture oracles. Other controls cover impossible classes/alternatives,
nesting, both named headers, optional live groups, fake quote/class headers,
trailing/middle holes and Unicode byte boundaries. All eight producer modes,
including the seven earlier outputs, match the pinned Loki regexp fork exactly.
The shared regression and stream/tail ownership control pass seed701.

The `:regex_erased_capture_batch` HTTP test checks all 23 named patterns over
ten retained inputs, exact labels before/after another parser, both empty and
nonempty metric filters, no-series results, GET/form POST and actual Parquet
codecs over the local S3-compatible HTTP store (seed700). These are local
controls, not extra exported Loki integration rows. A separate 4,212-pattern,
26-input matrix agrees byte-for-byte with the pinned fork and passes 547,560
native/reference matching/capture comparisons. Rebuilt actual Loki syntax and
pipeline code at `5aa4b9212d64d723f63b2770452054aa23df114d` also agrees on all
39,123 line/label/category/filter decisions, including stream/metadata collisions,
repeated parsers, drops, formatting and empty/nonempty filters.

Named log values still borrow input binaries and retained results detach at
their existing lifetime boundary. Indexed/named metric aliases now share one
detached BEAM value, without intermediate Rust strings or a second binary copy.
Native metric stages skip copying captures already owned by earlier stages.
Boolean compiler paths do not allocate name metadata; no per-entry parsing,
additional cache, thread pool or whole-input copy is introduced.

Predicate and regexp/indexed-extraction schemas have an independent 1 MiB logical
ceiling, charged at 32 bytes per original group plus raw name bytes even when
optimization erases every group. Template named-alias preparation stays separate.
Compiler regressions exercise 32,768 versus 32,769 anonymous groups and exact
1 MiB versus one-extra-byte named schemas. Existing program/query budgets still
apply; this is not a physical-RSS or capacity claim. All query-serving app/native
pairs require log tuple `{1,1,12}`; trace/metric tuples and storage/keyed bytes
are unchanged. Full Unicode property-name/version admission, numeric/repeated
selector names, flag-separated nested repetition, exact diagnostics and full
regex/client/provider/capacity acceptance remain open. Evidence is under
`.amp/in/artifacts/regex-erased-*`.

Full precommit seed703 passes 2,416 tests, one skipped and 37 opt-in exclusions
in 187.6 seconds. The broader shared/protocol run passes 795 tests with one
skipped (seed702); all 133 Rust tests, strict all-target Clippy, formatting and
strict Credo pass. Direct Parquet scans answer natively for zero-repeat and
impossible-branch captures with exact packed samples and fail-whole sample
budgets. A memory probe confirms numeric/named aliases share one detached
128 KiB BEAM binary instead of retaining the 2,176 KiB input. These local
checks establish neither total-memory bounds nor deployed/provider capacity.
Temporary producers, matrices, executables and the reference checkout were
removed; checked-in fixtures/producers and bounded artifact logs remain.

### Flag-separated nested repetition continuation

The flag-separated nested repetition gap is closed for the supported regex
profile. Go directives clear the adjacent-quantifier guard without adding an
atom: `x*(?)?` is `(?:x*)?`, not lazy `x*?`. The shared normalizer now tracks
atom boundaries, inserts noncapturing wrappers and restores moved directives
outside those wrappers. Earlier literal flags, subsequent scope, inner/outer
U/lazy choices and original capture numbers remain intact. Directly adjacent
quantifiers still reject; counted products still fail above 1,000, including
inner errors under outer zero. Existing compiled-program/schema and query
work/output limits remain unchanged.

The 57 local source-derived cases in `nested-repetition-controls.json` include
46 accepted and 11 rejected patterns. Forty inputs per accepted case freeze
1,840 answers each for substring/whole-label matching, named/indexed captures,
counts and expanding/literal replacements. Ordinary replay requires no Go or
network. All nine producer modes match the pinned Loki fork exactly; all eight
earlier fixtures stay byte-identical. These are executed local controls, not
additional copied upstream test-table or service-integration rows.

The new shared regression fails unchanged code (seed704) and passes seed707,
including exact template-count work exhaustion. Existing Mimir/Loki/Tempo
admission wrappers and Loki parser/metric-filter controls pass seed706 through
HTTP and actual Parquet/local S3-compatible HTTP stores; invalid patterns do
not read storage. Parser controls cover 24 named cases, 15 newly added, over
eleven retained values. A separate 5,400-pattern/21-input matrix agrees exactly
between Go and the pinned Loki regexp fork and passes 453,600 native
matching/capture checks. No full upstream service suite or deployed/capacity
acceptance is claimed.

Wrapper opens are deferred, sorted and merged once instead of repeatedly
inserting/copying prefixes. Only these nested forms require the extra
normalized-pattern copy; line buffers, existing compiled match loops and
thread pools are unchanged. Upgrade all query-serving app/native pairs to
log tuple `{1,1,13}`; trace/metric tuples and storage/keyed bytes are unchanged.
Full Unicode property-name/version admission, numeric/repeated selector names,
exact errors and full Go regex/client/provider/capacity acceptance remain open.
Evidence is under `.amp/in/artifacts/regex-nested-*`.

Full precommit seed708 passes 2,416 tests, one skipped and 37 opt-in exclusions
in 147.5 seconds. All 133 Rust tests, strict all-target Clippy, formatting and
strict Credo pass. A direct Parquet NIF probe answers natively for all 15 new
named patterns with exact packed samples; exhausted sample budgets fail whole,
never returning partial output. Temporary generators, matrices and executables
were removed; checked-in fixtures/producers and bounded artifact logs remain.

### Numeric and repeated selector capture-name continuation

Numeric/repeated ASCII names now work in shared selectors and `label_replace`.
Go replacement expansion chooses the first participating named group (including
matched empty groups); decimal indices below one billion without leading zeros
cannot be shadowed by aliases. Original numbering survives zero-erasure,
impossible alternatives and flag-separated repetitions. Loki regexp-parser
destinations retain their distinct contract: repeated raw names reject, numeric
names gain `_`, and normalized collisions preserve first-declaration ownership
before ordinary stream/metadata suffixing.

The shared native compiler removes named headers in its existing schema pass,
without inserting captures or copying input lines. Replacement aliases group
once at compilation and share detached numeric values; log captures still borrow
input bytes. Template helpers now share schema admission instead of reparsing
headers separately; counting allocates no name metadata. The existing 1 MiB
logical schema ceiling also bounds template preparation, with exact boundary
controls. Matching loops, thread pools, storage/keyed bytes and trace/metric
tuples are unchanged. Upgrade all serving app/native pairs to log tuple `{1,1,14}`.

`selector-name-controls.json` freezes 35 Go cases (28 accepted, seven rejected),
25 inputs and 700 oracles per matching/expansion operation. Two complete upstream
patterns are reused, but the selected inputs and executed expansion answers are
local controls, not extra copied integration rows. Fourteen admitted parser
patterns have 350 separate source-derived normalized capture oracles. The actual
pinned Loki constructor independently confirms all 35 admission decisions;
its sanitizer plus an adapted ordered loop confirms the capture maps, not the
whole Loki pipeline. Provenance and regeneration are in the regex fixture README.

Two shared tests fail before implementation (seed709). All five focused
Mimir/Loki/Tempo HTTP/Parquet/S3 wrappers pass seed711, including replacement
expansion, numeric parser labels, normalized/stream collisions and no-read
rejections. Native/tail/parity tests pass seed712. All ten producer modes agree
with the pinned Loki fork; all nine earlier fixtures remain byte-identical.
An independent 1,694-pattern/ten-input matrix produces 50,820 exact native
Boolean/capture checks. Direct native Parquet probes answer for all 14 parser
patterns with exact packed output and fail whole at exhausted sample budgets.
Full precommit seed713 passes 2,419 tests, one skipped and 37 opt-in exclusions
in 221.2 seconds. All 133 Rust tests, strict Clippy/Credo and formatting pass.
These are bounded component/local-provider controls, not full upstream service,
deployed-client, total-memory or capacity acceptance. Full Unicode property-name/
version admission and exact diagnostics remain open. Evidence is under
`.amp/in/artifacts/regex-selector-names-*`.

### Unicode property-name and version admission continuation

Shared regex properties now use Go 1.27.3's Unicode 17 categories/scripts,
category aliases, Any/ASCII/Assigned and loose ASCII case/space/underscore/
hyphen spelling. ISO script abbreviations, binary properties, tabs/Unicode
whitespace and property=value forms reject. Property-specific folds precede
negation and respect inline scopes; source class grammar, original captures,
zero-erasure, quantifier and work policies remain intact. This does not update
literal/class-range case folding or establish full Go regex/capacity parity.

The pinned Loki fork's root regexp package imports standard-library
`regexp/syntax`; its separate older syntax directory is not the executed
parser. Executing that dependency, rather than reasoning from the unused
directory, establishes alias admission. The separate producer freezes 973
cases (953 accepted/20 rejected), 54 inputs and 51,462 oracles for each of
substring and anchored matching. All 215 canonical categories/scripts/special
properties and every category alias are covered. All 22 original Go
property-parser patterns are retained, alongside 108 executed capture maps.
Other inputs/results are local executed controls, not additional upstream
integration rows. Replay needs only Elixir/
Rust, no Go or network; provenance and regeneration live in the regex README.

Property preparation uses static native ranges and a 32-byte stack name buffer,
without copying values or adding runtime lookup caches/dependencies/threads.
Only property-bearing patterns need expansion. A separate 1 MiB logical charge
reserves 21 bytes per source range plus 24 per property before union or
zero-repeat simplification; emitted text reserves a bounded maximum before writing. Program/DFA,
schema and query ceilings remain authoritative. Highly repetitive property
patterns can deliberately reject earlier than upstream. Upgrade every serving
app/native pair to log tuple `{1,1,15}`; trace/metric tuples, storage and keyed
bytes are unchanged. This is not total-memory or throughput acceptance.

The new regression fails before implementation on Unicode 17 uppercase input.
Three local Mimir/Loki/Tempo HTTP wrappers replay 49 accepted/20 rejected
rows over 15 persisted values in 966 requests, including positive/negative
log/metric filters, GET/form POST and resource/span trace predicates. Rejections perform
no storage reads. These reuse upstream integration harnesses with actual native
Parquet and a local S3-compatible provider, not deployed upstream services.
Separate exhaustive matching of all 1,112,064 scalars for 860 property/sign/fold
patterns exposed and corrected LC over-folding and surrogate-gap complements;
both native engines now agree exactly with the pinned Go dependency. The
standard Go engine separately agrees on all 973 decisions/102,924 Boolean
answers. Literal/class-range Unicode version folding remains open; the
literal-only surrogate-gap complement continuation follows below.
Full precommit seed724 passes 2,424 tests, one skipped and 37 opt-in exclusions
in 160.7 seconds. All 133 Rust tests, strict all-target Clippy, strict Credo,
formatting and whitespace checks pass. Fixture and formatted table regeneration
are byte-identical; a separate source audit confirms all 22 original rows.
Evidence is under `.amp/in/artifacts/regex-properties-*`.

### Scalar class complement continuation

Negated literal classes now exclude U+D7FF/U+E000 together, including raw,
hexadecimal, mixed and range-endpoint forms. The previous native dependency
reversed the empty scalar gap between separate intervals and reintroduced
both endpoints. Preparation joins only already-present endpoints during the
existing normalization scan, without allocating/expanding ordinary classes,
copying values or changing matching loops, caches, dependencies or threads.
Counted-product/schema/program/work limits and original capture indices remain.

The independent producer freezes 99 patterns (94 accepted/five rejected),
34 inputs, 6,392 Boolean answers, capture maps, 3,196 counts and 6,392
replacement results. Pinned Go 1.27.3 and Loki-fork executions agree
byte-for-byte. These are local executed controls, not extra upstream source
rows; original fixture expectations remain unchanged. The regression fails
before the fix. The existing three protocol HTTP/Parquet/S3 harnesses add
1,386 requests over 17 persisted values, including GET/form POST and invalid
grammar with zero storage requests. Separate actual Go execution compares all
1,112,064 Unicode scalars for 84 class variants; both native engines agree
on every scalar. This does not close literal Unicode folding, full regex or
client/provider/capacity acceptance. Upgrade every query-serving app/native
pair to log tuple `{1,1,16}`; trace/metric tuples and storage/keyed bytes are
unchanged. Provenance lives in the regex fixture README; evidence is under
`.amp/in/artifacts/regex-scalar-complements-*`.

Full local precommit seed725 passes 2,424 tests, one skipped and 37 opt-in
exclusions in 397.1 seconds after incorporating main's 1.16.0 release bump.
All 133 codec and five object-store Rust tests, strict all-target Clippy for
both changed crates, strict Credo, formatting and source whitespace checks pass.
Verbatim Mimir `.test` fixtures retain upstream indentation and final blank
lines; the scoped whitespace check excludes those imported data files.
All eleven producer modes regenerate byte-identically; the new fixture also
agrees byte-for-byte with the pinned Loki regex fork.

### Remaining upstream coverage and product gaps

- **Mimir:** additional histogram/exemplar policies and tenant downscaling,
  remaining invalid/partial-write permutations, OTLP translation, remote-read, federation, cardinality,
  exact upstream printer layout, remaining warning/info annotation text/taxonomy
  (classic quantile admission/collision/repair and native NaN notices are covered;
  positions remain; generic repair messages match the pinned streaming engine;
  classic fractions and corrected
  native multi-bucket NaN interpolation are covered by the continuation above),
  `anchored`/`smoothed`, delayed name removal and streaming. Sample-backed discovery now uses native histogram
  input but still does not establish TSDB-tier behavior.
- **Loki:** enabled label policies, deletion,
  federation, per-request lookback/byte/sharding policies, tail/client permutations, OTLP
  mapping, probabilistic sketches/distributed merging/high-cardinality acceleration.
  Complete parser-error generation remains open; quoted/raw literal decoding
  follows the pinned scanner/decoder, and numeric/duration/byte diagnostics
  preserve pinned wording/escaping and precedence. IP line/label predicates are
  covered by the separate bounded IP-filter batch, not an outstanding gap.
  Line-filter `or` alternatives are also covered, including inherited operators,
  mixed IP/string operands and negative-union semantics.
  Label-filter comma/implicit conjunctions, case-insensitive AND/OR and pinned
  mixed-operator grouping are covered by the conjunction batch.
  Logfmt default/strict decoding, byte-position errors, empty-value flags,
  extract-all normalization/first duplicates and quoted Unicode are covered.
  Explicit-field source grammar/admission, normalized lookup and absent-source
  defaults are covered by the source-expression continuation; last-definition
  duplicate destinations, ordered destination/source capture and replacement-rune
  values are covered by its value/ordering continuation. Stream/metadata/drop/
  repeated-parser ownership is covered by the ownership increment; shared-source
  aliases use a documented lexical choice, not exact Go map iteration. Broader
  parser grammar outside range placement/label replacement, malformed partial-extraction/diagnostic parity and hint-driven
  early exits remain open; explicit JSON paths, ordered plain-JSON flattening,
  numeric lexemes, first duplicates and null/array omission are covered.
  Regexp/pattern admission, partial short-line captures and string-only unpack
  with `_entry` replacement are covered by the remaining-parser continuation.
  Formatter assignment/admission, ordered self-renames and label snapshots are
  covered. Deterministic string-function pipelines, parentheses, simple Unicode
  casing and argument-error/input-preservation behavior are covered by the string
  template continuation. Literal replacement, cutset trimming, historical title
  casing, query-form URL escaping and Base64 encoding are covered by the string
  transformation continuation. Counted replacement, repeat/indent/nindent,
  Unicode-scalar alignment and signed-int64 literals are covered by the integer
  template continuation. Base64 decoding and public byte-based truncation/slicing
  with UTF-8 results are covered by the decoding/slicing continuation.
  Conditional branches, lazy logical helpers, typed comparisons and byte length
  are covered by the conditional/logical continuation. Integer conversion and
  wrapping arithmetic are covered by the integer-arithmetic continuation.
  Byte/duration conversion helpers and typed float consumption are covered by
  the quantity continuation, with explicit stricter overflow-cast rejection.
  Regex counting and replacement are covered by their bounded native
  continuations, including numeric/repeated names, literal quoting and octal
  escapes in template helpers. Shared LogQL/PromQL/trace predicates also support
  quoted/octal literals, braced hexadecimal escapes before repetition and Go
  counted-bound/nested-product admission with literal malformed/leading-zero braces.
  Literal class brackets, `&&`/`~~` members and left-to-right hyphen ranges are
  covered by their shared native continuations. Raw-header validation and
  empty/repeated inline flag semantics are covered by their continuation.
  Native regexp-parser metadata admission and Unicode-property caret negation
  are covered by the continuations above. Optimized-away capture extraction is
  covered by the original-schema continuation; flag-separated nested repetition
  and numeric/repeated selector names are covered by their continuations.
  Unicode property-name/version admission is covered by the bounded Unicode 17
  continuation. Full Go regexp syntax/case-fold/capacity parity remains open.
  `with`/`else with` dot scoping and `$` root lookup
  are covered by the scope continuation. Action/control-header declarations,
  assignments and shadowing are covered by the variable continuation; nested
  bindings and field-chain syntax are covered by the following continuation.
  Label-map/integer iteration and nested loop control are covered by the bounded
  iteration continuation. Typed JSON objects/arrays, their operations and
  iteration are covered by the JSON continuation. Original timestamps and
  Unix-time helpers are covered by the timestamp continuation, with explicit
  UTC rendering. Channel/function iteration, arbitrary date layouts/named zones/
  time methods/now and other template functions, non-UTF-8 byte strings and exact
  error text/ownership remain open.
  Rune constants and byte-escape numeric values are covered by their separate
  character-literal continuation. Finite float constants and contextual integer
  arguments are covered by the floating-point constant continuation, with the
  explicit nonportable overflow-cast exclusions.
  Finite complex constants and contextual zero-imaginary typed arguments are
  covered by the complex continuation; component values remain complex in
  generic/piped/parenthesized contexts, not implicitly real-valued numbers.
  Root label maps, arbitrary-key lookup and typed byte indexing are covered by
  the indexing continuation. The JSON continuation adds typed object/array
  access while retaining label-map/scalar/nil boundaries and errors.
  String `slice` is covered by its continuation, with stricter rejection of
  non-UTF-8 intermediates. Array slicing is covered by its continuation, with
  explicit remaining Go allocator spare-capacity differences.
  Variadic `print`/`println`, explicit `html` and query-form `urlquery` are
  covered by their continuation; untyped nil is covered separately, not typed
  pointer/interface values. Explicit `js` has its own continuation; `printf`
  remains open.
  Floating conversion/extrema/ceil/floor/round are covered by their continuation;
  decimal addf/subf/mulf/divf are covered by the decimal arithmetic continuation.
  Literal ASCII-whitespace delimiter trimming and non-nesting comments are
  covered by the whitespace/comment continuation.
  The pinned `0B` scanner/test contradiction remains explicit. Runtime/query
  duration/byte conversions, bracket profiles, typed-filter
  errors and post-unwrap label/error filtering are covered. Full numerical and
  equal-time ordering parity remain unproven.
  The upstream seven-day no-step metric case cannot reproduce its expected
  last-four-second samples on the regular default grid; its imported count
  assertion explicitly supplies 60s resolution. No extra terminal sample or
  budget exemption is invented to conceal the discrepancy.
- **Tempo:** partial time bounds, intrinsic/OR/partial-query discovery,
  structural/spanset TraceQL, metrics exemplars and `compare()`,
  query streaming, broader trace filters/diffs and legacy-v1
  collisions. Existing typed/export/search fixtures do not fill these gaps by
  implication. Unsupported discovery filters still reject rather than vanish.
- **Architecture-specific exclusions:** upstream Kafka/WAL/ring/quorum,
  sharding/cache and multi-storage-engine permutations are not transplanted as
  fake equivalents. Pulse needs its own multi-instance CAS, maintenance,
  admission, restart and provider tests, plus separately authorized deployed
  clients and representative capacity validation.

Prioritize additional portable upstream tables by those missing public
behaviors. Keep exact ports, explicit adaptations, deliberate stricter failures
and unsupported surfaces separate; never skip a mismatch or widen a safety
ceiling solely to turn a selected case green.

## Historical pause point: landed protocol increment

The implementation below landed in `f7a3ebe` (PR #34). Work has resumed with
explicitly requested, bounded follow-ups. The original landing constraint and
its validation caveats are preserved here; landing did not satisfy operational
or Tuist cutover gates.

Pause new protocol/storage/alerting feature increments and prepare the existing
implementation for review and landing. The backlog below is follow-up work, not
an instruction to expand this PR until every protocol is complete.

Before landing, review the actual diff (including untracked source/tests/fixtures),
keep operator contracts and upgrade caveats accurate, and verify the final PR
revision. Existing correctness/safety regressions remain review blockers; deferred
feature breadth is distinct from those blockers. Passing bounded tests does not
close the recorded timeout/lifetime diagnostics or establish production capacity.
No merge, deployment or migration is authorized merely by this planning note.

See [the landing review checkpoint](landing-review.md) for concrete fixes,
failed/successful validation, review coverage limits and explicit open findings.

Resume from [Remaining protocol work](#remaining-protocol-work-independent-of-application-usage),
including the storage/scale and operational follow-ups, after this PR lands.

## Completed increment: Loki label-name volumes

- Remove `aggregateBy=labels` from the unsupported list. Both volume endpoints
  accept GET/form POST, count bytes by stream label name across values, restrict
  explicit targets, and rank by descending bytes with lexical tie-breaking.
  Range limits apply per bucket, not globally before aggregation.
- Semantic references are Grafana Loki v3.5.0 at
  `4b16bc4fa823f7ec6e865ebf51fad89d98a2371c`:
  [TSDB volume tests](https://github.com/grafana/loki/blob/4b16bc4fa823f7ec6e865ebf51fad89d98a2371c/pkg/storage/stores/shipper/indexshipper/tsdb/single_file_index_test.go#L593),
  [response conversion tests](https://github.com/grafana/loki/blob/4b16bc4fa823f7ec6e865ebf51fad89d98a2371c/pkg/querier/queryrange/volume_test.go#L174),
  and [target-label preparation](https://github.com/grafana/loki/blob/4b16bc4fa823f7ec6e865ebf51fad89d98a2371c/pkg/util/series_volume.go).
  The upstream label-volume, response and middleware tests pass unmodified.
  [Extracted upstream fixtures](../test/fixtures/logs/README.md#exact-upstream-loki-volume-cases)
  preserve all ten label-mode cases; eight portable cases replay through both
  HTTP endpoints/methods with exact byte expectations. Chunk-filter callbacks
  and partial-chunk estimates remain explicit exclusions. Additional independent
  Pulse cases exercise row-byte and safety contracts.
- Deliberate boundaries: selector-only; actual inclusive nanosecond rows rather
  than estimated chunk overlap/whole-second windows; matrix range responses
  even for a single bucket. Stream names reuse discovery's projection, excluding
  structured metadata and the internal tenant name. No new storage authority,
  native ABI or keyed encoder bytes. Existing series mode remains unchanged.
- Scan/line/work/intermediate/result budgets and a complete 5,000-name/1 MiB
  name dictionary fail whole before top-k. The implementation scans Parquet
  in batches; it does not claim Loki's index-backed cost or provider capacity.
  See [operator contract](../docs/querying.md#index-statistics-and-volume).

## Live-tail reliability follow-up

- Replace count-then-register admission with unique process-owned slots, retaining
  the per-tenant, per-instance cap during concurrent connection/history startup.
  Leave, caller death and failed follower startup release reservations.
- Close existing sockets with WebSocket1013 on follower loss, including a tail
  supervision restart. Never silently establish a replacement cursor after losing
  dedupe/baseline state or tailer memberships. Before upgrade, unavailable local
  supervision returns retryable HTTP503 instead of a request-process crash.
- Reconnection queries history and resumes best-effort delivery; it does not
  establish continuity, deduplicate across sockets or turn polling into a journal.
  Independent instances still multiply provider pressure. No storage/ABI/keyed-byte
  changes, new durable authority or rollout are involved.
- The old configuration-ETS traceback points to a test-owned shared table expiring;
  the current follower fixture already captures immutable configuration. A new
  full run reproduced a different teardown error: a periodic follower accessed
  its manifest cache after storage supervision stopped. Starting tail supervision
  after its storage dependencies now ensures followers stop first. No exception
  suppression was added to storage polling. This does not independently resolve
  the old shared-configuration failure or broader lifecycle/capacity acceptance.

Validation for this follow-up (logs in `/tmp/pulse-tail-lifecycle/`):

- Before production changes, regressions failed on non-idempotent rejoin and a
  missing close frame after follower loss. The concurrency control passed on that
  run; the count-then-register race is a source finding, not a reproduced overflow.
- `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mix precommit --max-cases 4 --seed 432996`:
  **1,618 passed, 1 skipped, 37 excluded**; strict compile, dependency and format
  checks included. Strict Credo is clean across 428 files. No native sources or
  storage formats changed; native crates were built, not separately unit-tested.
- Four focused tail files: **30 passed** on each of 11 consecutive runs using
  `--repeat-until-failure 10`; no tail ETS/manifest-cache teardown error in these
  runs or the final full run. Loopback WebSockets exercise follower death,
  orderly registry-supervisor restart, explicit 1013/503 and history/live reconnect.
  This does not establish abrupt registry-kill storms or provider acceptance.
- The first full run failed on a compaction peer's 30s application-start timeout,
  alongside acceptor teardown diagnostics and the manifest-cache error above.
  The exact failing peer test and full suite pass on same-seed replay, but the
  peer/acceptor root causes remain open. Existing compaction timeout warnings
  also remain; a later green run is not diagnostic closure. The intentional
  gRPC handler-crash test still emits its expected error log.
- No deployment, provider exercise, private application change, commit or cutover.

## Completed increment: exponential projection correctness

The working tree already contains exponential/delta receivers and other protocol
extensions beyond the historical checkpoints below. This increment hardens that
existing implementation rather than claiming a new receiver or accepting every
current extension by inspection.

- Keep finite bounds below exponent1024 and rounded subnormals above-1075.
  Merge equal rounded boundaries at their own complete cumulative count, including
  signed-zero collisions; retain negative infinity explicitly.
- Reject ordinary populated bins wholly inside the closed zero region, clip
  partial negative overlap, and preserve stale-value/optional/source-bit behavior.
- Enforce existing 65,536-count per-side conversion and 160-populated-coarsened-bin
  ceilings, even at scale-10. Exhaustion fails whole, including valid neighbors,
  keyed/unkeyed and JSON/protobuf. No cap increases or new mutable state.
- Freeze 1,160 public OTLP1.11.0/Google1.36.12 source points with Go1.26.5
  decomposed mathematical geometry and actual Prometheus0.315.0 bucket iterators.
  Preserve the observed direct-Exp2 subnormal discrepancy separately, not as a
  silently changed golden. Original typed owners/time/arrays survive native
  Parquet and gzip exact-key S3 replay across owned runtime instances.
- Classic projection is deliberately approximate, not native-histogram/negative
  endpoint parity. Mathematical overflow differs from Prometheus's max-finite
  sentinel. Source envelopes remain faithful, with unchanged formats/API tuples.
- Affected projected keyed bytes can change; upgrade every ingress application
  and drain retries. Exact-byte409 remains permanent; never evade it by key
  mutation, overwrite, unkeyed/subset resend or metadata reconstruction.

## Completed increment: quoted trace counts and flags

- Accept exact quoted uint32 dropped counts and fixed32 flags at every trace
  owner, matching public OTLP v1.9.0/Google protobuf v1.36.11 decisions without
  float rounding or exponent-sized integers. Preserve whole-request metadata
  rejection, per-span partial success and keyed fail-whole publication.
- Keep enums as numeric JSON tokens. The dedicated public corpus proves quoted
  enum digits reject; generic ProtoJSON named enums remain invalid OTLP forms.
- Freeze 451 actual quoted-field decisions plus complete public JSON/protobuf
  requests. Native/reference JSON, Parquet and cross-instance gzip keyed S3 replay
  establish component behavior, not deployed-client/provider/capacity acceptance.
- Existing Rust decoding/preflight/storage stays in place. Only application-side
  trace metadata normalization changes; no native ABI, format or keyed-byte
  change. Upgrade all ingress applications before relying on accepted forms.

### Additional trace uint32 validation

The branch's independent corpus retains 306 public OTLP1.9.0/Google1.36.11
quoted-integer decisions across the nine count/flag fields, plus original and
canonical JSON and actual public protobuf. It adds native/reference/direct-map
parity, 50 randomized all-owner requests, native Parquet and gzip keyed S3 replay
across owned independent runtime instances. Both corpora remain replayable without
Go or network access.

Before merging the independently landed implementation:

- Five focused wire/JSON/controller files: **46 passed**.
- `ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mix precommit --max-cases 4`:
  **1,627 passed, 1 skipped, 37 excluded**. Existing compaction timeout warnings
  remain diagnostic follow-ups, not resolved by this passing run.
- Strict Credo: **429 files, no issues**. No Rust source/ABI changed; the native
  crates were built, not separately unit-tested for this app-only increment.
- A local, sequential 20-sample/1,000-span decoder check alternated the original
  baseline and branch implementation after warmup: numeric sparse medians
  **10,328/10,302 µs** and numeric dense **14,534/14,569 µs**. These historical
  component checks are not concurrent capacity/provider proof or measurements
  of the combined implementation.
- Claude design iteration rejected early native string rewriting because it
  would reclassify admission terms. Adversarial source review found no blocking
  defect; count-field body-vs-attribute byte bounds and the prevalidated
  construction invariant were clarified. Raw public captures retain their
  provenance; regeneration whitespace differences stay documented.

The merge retains the landed parse-once span/event/link decoder and both
independent fixture and regression-test sets, without changing admission,
numeric-only enums, storage formats or keyed fail-whole behavior. Combined
validation: six focused OTLP files **55 passed**; full precommit **1,637 passed,
1 skipped, 37 excluded**. Existing compaction timeout diagnostics remain open.

## Completed checkpoint: receiver-scoped duplicate JSON fields

- Reject recognized duplicate JSON fields before any append, across scalar,
  message, repeated-container and oneof fields. Equal values, nulls and escaped
  key spellings do not evade rejection; separate object siblings reuse masks.
- Bind JSON parsing to the static receiver signal, not payload inference. Unknown
  names, opaque unknown objects and foreign signal roots remain ignored. General
  JSON outside OTLP retains its previous first-key behavior.
- Ignore syntactically valid overflowing numeric tokens in opaque unknown fields
  without losing their scalar node/eight-byte admission. Do not hide malformed
  JSON, drop supplied containers or infer a schema from nested field names.
- Keep object pairs in the independent fallback until duplicate validation. A
  native fallback must not silently collapse duplicates into an ordinary map.
  Existing exact integers, signed zero, scalar costs and all safety caps remain.
- Require shared wire capability 3; unchanged Parquet/envelope/keyed scalar formats
  and signal metadata/search tuples. Upgrade every serving ingress app/native pair.
- Freeze 704 actual Google protobuf v1.36.11/OTLP v1.9.0 field decisions over 35
  contexts, including all fields enumerated by public message descriptors. Prove
  known-duplicate whole-request rejection and unknown-field exact keyed publication
  in owned gzip HTTP/S3 cross-instance contexts. No SDK/Go/network in normal replay.
- Correct generic ProtoJSON assumptions: OTLP requires integer enums/lowerCamelCase.
  Named enums/snake_case aliases are not missing mandatory OTLP features.
- [GreptimeDB and OpenObserve reference notes](backend-protocol-references.md)
  identify concrete naming/default/oneof lessons without copying code or adopting
  another authority/topology. Public protocol semantics remain the acceptance oracle.

## Completed checkpoint: exact raw JSON integer numbers

- Decode numeric tokens in supported OTLP message schemas without first rounding
  through float64. Cover source times, int64 values, uint64 counts/bucket arrays
  and numeric 32-bit/enum fields, including escaped keys.
- Reject true fractions/overflow as invalid protocol numbers, including tiny
  nonzero fractions that previously underflowed to zero. Invalid source time must
  never trigger unknown-time/receive-time fallback. Preserve scalar node/eight-byte
  accounting, not string reclassification or synthetic JSON containers.
- Keep ordinary floating/unknown fields and quoted values separate. An OTLP-only
  zero-mantissa adapter preserves double `-0e0` sign; general JSON behavior stays
  unchanged. Native answers match an independent Elixir token/schema reference,
  randomized exact integers and explicit fallback/malformed-input cases.
- Require shared wire capability 2 across every serving ingress app/native pair;
  no signal metadata/search tuple, Parquet, scalar keyed-byte or budget change.
- Freeze 156 actual public Google protobuf integer-token decisions, 11 float-bit
  cases and three full raw-number/canonical-JSON/protobuf request sets. Prove
  native Parquet fidelity and gzip keyed publication across independent runtimes
  sharing an owned local S3 stub. Ordinary replay needs no Go or network.
- Remaining null/entity-ref forms, other metric types and actual
  deployment/capacity acceptance remain independent gaps. Quoted trace counts/flags
  are now covered by the dedicated increment above; enums require numeric tokens. The earlier generic
  named-enum/alias assumptions are corrected by the OTLP-specific contract above.

## Completed checkpoint: shared OTLP wire semantics

This checkpoint introduced wire capability 1 and quoted forms; its raw-number
limitations are superseded by the capability-2 increment above.

- Merge singular protobuf messages recursively, append repeated values and follow
  known oneof selection for AnyValue, Metric data, scalar points and exemplars.
  Switching away and back must not resurrect a previous message member.
- Run allocation-free raw preflight before a bounded native borrowed-slice plan;
  account source fragments, losing data/oneofs and unknown field occurrences.
  Apply cumulative logical-owner attribute counts/bytes/nodes before BEAM term
  materialization, without refunding replaced metadata.
- Accept exact quoted decimal/exponent integer forms without float rounding or
  exponent-sized bignums. Reject noncanonical leading-zero/plus spellings that
  were previously extensions. Broader unquoted forms and trace count/flag strings
  were addressed by the later dedicated increments above, not inferred from this
  component; enum strings remain invalid.
- Fence matching native artifacts with shared OTLP wire capability 1, separate
  from unchanged log/metric/trace storage/search capabilities. Upgrade every
  serving ingress pair; there is no Parquet, envelope or keyed scalar format change.
- Freeze actual public Google protobuf v1.36.11/OTLP v1.9.0 decoding, canonical
  wire and JSON across all three signals, including signed zero and 60 numeric
  string cases. Replay offline, validate native Parquet and owned local HTTP/S3
  CAS keyed replay across two runtime instances. These are not capacity or
  deployed-client acceptance. See [operator contract](../docs/otlp-wire.md).

## Completed checkpoint: explicit distributions

- Accept cumulative explicit OTLP histograms and summaries in HTTP JSON/protobuf,
  including packed/unpacked primitive arrays, optional sum/min/max, exact uint64
  counts, original quantiles, typed owners and histogram exemplars.
- Project classic Prometheus float samples without replacing the original point.
  Independently cap supplied source points, expanded samples and additive encoded
  metadata. Rejections count source points; safety failures append nothing.
- Honor no-recorded-value markers without validating ignored count/sum/value
  relationships; retain their originals, validate label-defining structure, and
  prove the latest marker suppresses an earlier ordinary value after compaction.
- Reject ambiguous projected families and conflicting same-time source envelopes
  within a request. Do not introduce a mutable cross-request metric registry.
- Fence the enriched wire decoder with capability 2, leaving metadata/storage
  formats and the other metric capabilities unchanged: `{1,2,1,1,1}`.
- Validate with public OTLP proto v1.9.0, actual protoc/Google ProtoJSON fixtures,
  actual Go fixed-decimal label spellings, native storage, HTTP/MCP/PromQL,
  cross-instance publication, restart and compaction. These are independent
  protocol components, not application bootstrap or provider-capacity evidence.

Full source envelopes repeat per projected row. Keeping the existing 16 MiB cap
is deliberate: do not increase resource bounds to make oversized distributions
pass. Shared source-point representation would require a separately designed,
self-contained immutable storage format and coherent reader/compactor upgrade,
not a second mutable authority or dangling point-reference store.

## Completed checkpoint: Remote Write 2.0 source starts

- Investigated the experimental schema transition: public Prometheus 3.5.0
  (rc.3, per-series created timestamp) versus 3.8.0 (rc.4, per-sample/histogram
  start timestamp). Retain both in an optional signed-int64 millisecond column,
  including exact extremes, zero-as-unset and same-label entries with differing
  starts. Hybrid precedence is explicitly a Pulse policy, not upstream parity.
- Match default public receiver operation with optional zero-injection disabled;
  preserve ordinary PromQL samples and exact written counts, not synthetic rows.
  No per-series local/cluster authority, ingest forwarding or sticky routing.
- Keep source-record/body/label bounds and native preflight; malformed start
  fields and safety failures append nothing. Preserve sample-time retention,
  series identity, immutable PUT/CAS, old nil-start encoder bytes and keyed
  fingerprint stability. Starts join content hashes only when present.
- Metric metadata/start capability 2 changes the current tuple to `{2,2,1,1,1}`.
  Retention activates immediately. Require a fleet-wide maintenance pause:
  block metric delivery, drain old keyed retries, stop all old readers/writers/
  compactors, replace every participant, then resume traffic. Old ingress can
  change derived object keys; old compactors erase starts. No under-traffic
  rolling rollout, default-off switch, automatic historical repair or safe old
  compactor rollback is provided.
- Freeze actual public Go-schema production/decoding plus actual release
  receiver written headers and stored-query results: 56 cases / 112 source
  samples across floats and integer/float/custom histograms. Replay with native
  project tooling; validate raw MCP native/fallback JSON, Parquet, owned local
  S3/CAS, independent runtime instances, restart and mixed null/start compaction.
  See [fixture provenance](../test/fixtures/metrics/remote_write_start/README.md).
  This does not establish separate-node, real-provider, SDK/Alloy, pressure or
  full compliance-suite acceptance.

## Remaining protocol work, independent of application usage

1. **OTLP metric semantics:** native exponential-histogram representation beyond
   existing bounded classic projection; broader source-scale/grid and mixed-series
   aggregation acceptance. Existing stored delta interval reports do not establish
   cumulative conversion, reset, interval-boundary, overlap, out-of-order, retry
   or multi-writer semantic acceptance. Do not accumulate acknowledged
   deltas only in node memory or depend on sticky routing. Evaluate retaining
   interval observations and query-time conversion before adding mutable state.
2. **Prometheus interoperability:** explicit versioned OTLP naming/unit/resource
   policies; broader native-histogram/exemplar query/export, remote-write2
   metadata/client/compliance acceptance and newer stateless-mode validation.
   Optional created/start zero-injection and start-aware query/reset semantics
   remain open: do not infer them from source-start retention or add a
   node-local durable reset cache. Projection must
   not silently mix incompatible original instruments or invent counter resets.
3. **OTLP wire breadth:** entity references, remaining
   null/presence/request-shape and unsupported-message validation, broader OTLP
   conformance and broader direct-gRPC client/default-policy acceptance. Keep shared auth, tenant boundaries, budgets and partial-success
   semantics across transports. Validate public independent producers, not only
   hand-built encoders.
4. **Query languages:** expand the remaining PromQL functions/modifiers and
   LogQL against public semantic engines, then full TraceQL types,
   structural/spanset operations and discovery. Preserve
   independent time contracts, same-parent ownership, complete retained context,
   original-type proofs, native accounting and whole-query failure.
5. **Alert compatibility:** native and imported rule/lifecycle semantics, missing
   series/no-data/error behavior, keep-firing, recordings, templates and delivery
   routing/grouping/silences/mutes/resolution. Parser and empty-data passes do not
   establish execution or lifecycle compatibility.
6. **Client and operational acceptance:** versioned public client matrices,
   batching, queues, post-publication ambiguity, TLS/auth gateways, cancellation,
   node-wide pressure, multiple instances and real providers. Keep capacity,
   restore, rollout and cutover acceptance separate from feature semantics.
7. **Storage and scale:** external label/posting indexes; selective column/row-group
   reads; bounded large-history catalogs without finite retention; node-wide
   admission, tenant fairness and aggregate object-store pressure; representative
   cardinality, cold-history and sustained-ingestion measurements. Current native
   footer postings and per-request caps are not completion of these items. See
   [architecture](../docs/architecture.md#storage-model) and
   [storage costs](../docs/storage-costs.md).
8. **Reliability follow-ups:** root-cause the retained compaction timeouts,
   tail-follower configuration-ETS lifetime error and earlier high-parallelism
   failures. Preserve diagnostic evidence and distinguish deliberate fault-test
   output from actual lifecycle defects; do not treat a subsequent passing run
   as closure. Separate-node/provider crash recovery, backup/restore and rolling
   upgrade/rollback/cutover rehearsals require their own acceptance and authorization.

## Required proof for each increment

- Public specification/version pin and clearly identified deviations.
- Independent wire producers and semantic consumers where applicable, retaining
  source inputs, observed bytes and derived expectations as distinct artifacts.
- JSON/protobuf/non-finite/signed-zero/boundary and malformed-input parity tests.
- Native source/expanded-node/work/byte limits before expensive materialization;
  no dropped filters, silent truncation or keyed subset publication.
- S3/manifest/CAS, tenant denial, cross-instance reads, restart and compaction
  regressions; no new non-S3 authority.
- Matching local artifact fences plus explicit all-serving-pool upgrade rules.
- Frozen ordinary replay without external tools/network; optional live exercises
  fail explicitly when opted into without prepared tools.
- Documentation synchronized with implemented behavior and remaining gaps.

## Completed increment: PromQL basic math

- Add `ceil`, `sqrt`, `exp`, `ln`, `log2`, and `log10` using Prometheus 3.5.0's
  one-instant-vector contract. Histograms are omitted, metric names removed and
  other labels retained. Negative domains return NaN; logarithm zero returns
  negative infinity; signed zeros survive. `exp` and `log2` reproduce Go 1.24.5
  arm64 reduction/scaling, including its early exponential underflow, rather
  than promising universal libm or correctly rounded mathematical results.
- Extend the existing offline conformance corpus with 166 independently
  promtool-verified cases, including adjacent overflow inputs, subnormal values,
  staleness and signed-zero reciprocals. The complete 946-case snapshot remains
  linked to its exact input SHA-256; it contains verified Pulse answers, not
  captured upstream API responses. Finite math replay allows one ULP for
  platform differences; 780 exact boolean checks independently establish
  NaN/zero/infinity classes and zero signs, without fuzzy comparison.
- Import 30 verbatim Mimir query-engine integration evaluations, with pinned
  source ranges and AGPL/Apache notices, covering nested calls, histogram
  omission, metric-name collisions and disjoint range-series lifetimes.
  This is a selected suite, not Mimir's Docker/service integration suite.
- Preserve the existing query sample/work/materialization bounds and shared
  HTTP/MCP evaluator. No new state, native ABI, stored format or keyed encoder
  bytes. Every query-serving application must upgrade before callers rely on
  these functions. This closes the basic-math slice, not full PromQL, provider,
  deployed-client or capacity acceptance.

Validation:

- The new parser and IEEE regression tests failed on the unchanged application
  with `invalid_function_arguments`, then passed with the implementation.
- Adversarial review found near-one `log2` cancellation, Go arm64 `exp`
  underflow differences, and fuzzy verification accepting classification
  errors. Source-compatible arithmetic and exact classification checks fix
  these sampled mismatches. Regression failed before the fix; an isolated
  mutation passed fuzzy comparison but failed the new exact classifier.
- Promtool 3.5.0 verified all 946 cases, 780 exact math classifications and
  four exact epoch checks. A separate 4,303-value sweep concentrated on
  adjacent-to-one logs and exponential boundaries: finite answers within
  one ULP, zero/infinity classes exact. This is sampled arm64 validation,
  not an all-input or cross-architecture proof. The
  previous 780 stored oracle cases are unchanged. Focused PromQL/HTTP/MCP tests:
  174 passed, one optional live conformance test skipped. All 30 imported Mimir
  evaluations pass on memory and native S3/Parquet storage: 114 HTTP endpoint
  checks including instant cases replayed as one-step ranges.
- An owned loopback S3 stub exercised all 156 stored math cases through an
  independent runtime, exact-key retries, compaction/cleanup and reader restart.
  MCP, tenant isolation, authorization denial and work-budget rejection passed.
  This earlier temporary validation was removed; the imported upstream replay
  now permanently covers the native S3/Parquet HTTP path.
- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: 1,654 passed, one skipped,
  37 excluded; strict compile, dependency and format checks included. Existing
  compaction timeout/conflict diagnostics remain open; the passing suite does
  not establish provider capacity or close those reliability findings. Strict
  Credo is clean across 433 source files.

## Quoted trace integer validation checkpoint

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4 --seed 432996`:
  **1,627 passed, 1 skipped, 37 excluded**, 81.1s; strict application compile,
  unused-dependency and formatting checks included. Strict Credo is clean across
  429 source files. Native crates were built; no native sources/ABI changed and
  native unit tests were not separately rerun for this application-only increment.
- Dedicated corpus: 451 actual public decisions and 102 randomized/explicit-boundary
  normalization cases, native/reference JSON parity, faithful native Parquet and
  gzip HTTP exact-byte keyed replay across independent owned S3 runtime instances.
  The pinned optional Go producer passed offline generation, vet and build.
- Claude reviewed the design and implementation adversarially. No blocking
  implementation findings; corrected the randomized zero generator and added
  explicit zero/uint32-max cases. Public evidence also corrected the initial
  assumption that enum numeric strings should be accepted: they must reject.
- Logs in `.sc/trace-integers/` retain compaction timeout/conflict and manifest-CAS
  diagnostics. The passing suite does not close earlier reliability findings or
  establish capacity. No provider/deployed-client/rollout or commit is implied.

## Current exponential-boundary validation checkpoint

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,479 passed,
  1 skipped, 37 excluded**, 278.6s. Logs retain compaction timeout diagnostics
  and a test tail-follower ETS-lifetime error; no operational cause/capacity
  closure follows from passing assertions.
- Focused projection/distribution/HTTP tests: **40 passed**, including 64
  randomized mass-collision cases and cross-instance exact-key replay.
- Locked/offline native codec tests: **123 passed**; strict compile, Credo,
  all-target Clippy, formatting and whitespace/local-link checks pass. No Rust
  source/native ABI change was required for this scalar-normalization correction.
- 1,160 public points, 796 actual Prometheus iterator observations, and 20
  separately retained direct-Exp2/decomposed differences. Six-file index SHA256:
  `bfcab3e720eaa1fa0349a42dbab2a40b0a70553b2b1f907d7f0fd3e76514aff7`.
- Prepared public dependency downloads were preparation; final generation/vet/
  build succeeded offline/read-only. Actual linked identities are captured, not
  tool/cache attestation. Ordinary replay requires neither Go nor network.
- No provider/separate-node/deployed-client/capacity or independent-reviewer
  acceptance, commit, rollout or historical projection repair is implied.

## Historical field-validation checkpoint

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,293 passed,
  1 skipped, 37 excluded**, 310.8s. Logs retain a self-metrics worker timeout and
  ThousandIsland acceptor `noproc` diagnostics; this pass does not establish their
  root cause or capacity acceptance.
- Locked/offline codec tests: **96 passed**; strict all-target Clippy, Credo,
  compile, formatting and whitespace/local-link checks pass.
- 704 public field decisions replay without Go/network in ordinary tests. Offline
  pinned producer generation/vet/build succeeds; actual linked dependency
  versions/checksums are captured, not cryptographic attestation.
- Four-file field-corpus index SHA-256:
  `1d0dedc0dedd1be09c22da1568d80bfb0741e0411b44b950a49bf55223f52768`.
- Source-only GreptimeDB/OpenObserve comparisons do not establish backend,
  deployed-client, provider or default-policy parity. Earlier high-parallelism
  failures remain unresolved; no independent reviewer closure is claimed.

## Historical explicit-distribution validation checkpoint

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,259 passed,
  1 skipped, 37 excluded** on the final corpus. Earlier full validation passed
  the same counts; no resource ceilings were raised.
- Locked/offline codec tests: **89 passed**; strict all-target Clippy and Rust
  formatting clean. Compile with warnings-as-errors, strict Credo, formatter
  and whitespace/local-link checks clean.
- Optional producer `go vet -mod=readonly ./...` passed offline on the isolated
  pinned module. Public protoc/Google capture and 2,055 Go label cases replay
  without those tools in ordinary tests.
- Final eight-file corpus index SHA-256:
  `ce2cc283a84965c80815b86e6c8d4c74e977cf8117eea28b23ebf20b0034b2d6`.

These are owned loopback/S3-stub contexts, not separate-node/provider/load,
full SDK/application bootstrap, deployed-client or capacity acceptance. The
previous high-parallelism failures remain unresolved.

No commit, deployment or production migration is implied by this plan.
