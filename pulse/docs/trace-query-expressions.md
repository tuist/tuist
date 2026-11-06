# Bounded trace search expressions

Experimental `GET /api/search` and MCP `search_trace_metadata` support a
bounded TraceQL subset (same-span spansets, original typed owner attributes, structural
operators and `select`); `with (most_recent=true)` is optional because results
are always the most recent matching traces. They remain
behind `PULSE_TEMPO_SEARCH_ENABLED` / `tempoSearch.enabled`, disabled by default.
This is not full TraceQL or deployed Grafana compatibility.

```traceql
{ resource.service.name = "worker" && (status = error || span.http.response.status_code >= 500) } with (most_recent=true)
```

```traceql
{ span.http.route !~ "/(health|metrics)" && duration > 500ms } with (most_recent=true)
```

## Operators and types

| Operand | Supported comparisons | Meaning |
| --- | --- | --- |
| `resource.<key>`, `span.<key>` with a JSON string literal | `=`, `!=`, `=~`, `!~` | Original `stringValue` only, never a projected/coerced value |
| `resource.<key>`, `span.<key>` with a signed int64 literal | `=`, `!=`, `<`, `<=`, `>`, `>=` | Original `intValue`, compared exactly, including values above 2^53 |
| `resource.<key>`, `span.<key>` with a finite decimal/scientific float literal | `=`, `!=`, `<`, `<=`, `>`, `>=` | Original `doubleValue`, compared as float64; `1.0` and `1` target different stored types |
| `resource.<key>`, `span.<key>` with `true` or `false` | `=`, `!=` | Original `boolValue` only |
| `name`, `span:name` with a JSON string literal | `=`, `!=`, `=~`, `!~` | Stored span name, including its empty default, not an attribute called `name` |
| `kind`, `span:kind` | `=`, `!=` with `unspecified`, `internal`, `server`, `client`, `producer`, `consumer` | Stored OTel span kind, not an attribute called `kind` |
| `status`, `span:status` | `=`, `!=` with `unset`, `ok`, `error` | Stored span status, not an attribute called `status` |
| `duration`, `span:duration` | `=`, `!=`, `<`, `<=`, `>`, `>=` with a duration literal | That span's end minus start in exact nanoseconds |
| `traceDuration`, `trace:duration` | `=`, `!=`, `<`, `<=`, `>`, `>=` with a duration literal | Complete retained trace max-end minus min-start, in exact nanoseconds, not the selected span's duration |
| `event.<key>` with a string, int64, float or boolean literal | Same as `span.<key>` | True when **any** event of the span has a matching original value |
| `link.<key>`, `instrumentation.<key>` | Same original typed comparisons as `span.<key>` | Span links or the span's original instrumentation scope, never projected strings |
| `statusMessage`, `span:statusMessage` | `=`, `!=`, `=~`, `!~` with a string | Original status message, including its empty default |
| `rootName`, `trace:rootName`, `rootServiceName`, `trace:rootService` | `=`, `!=`, `=~`, `!~` with a string | Root of the complete retained trace, not the selected span's name/service |
| `trace:id`, `span:id`, `span:parentID`, `link:traceID`, `link:spanID` | `=`, `!=` with a string | ID string predicates; regex/ordering reject, and the pinned Parquet ID caveats below apply |
| `event:name`, `instrumentation:name`, `instrumentation:version` | `=`, `!=`, `=~`, `!~` with a string | Original event name or instrumentation metadata |
| `event:timeSinceStart` | All six duration comparisons | Event timestamp minus that span's start, not trace start |

Empty `{}` spansets select all spans, including as structural operands such as
`{name = "request"} >> {}` or `{} > {}`. They still require known valid stored
metadata, complete retained context and all the existing query budgets.

Unscoped `.<key>` accepts the same typed comparisons. An original span
attribute takes precedence over an original resource attribute with that key,
even when the span value has the wrong type or fails the predicate. Only an
absent span key falls back to the resource. Event attributes are searched only
with an explicit `event.` scope; links and instrumentation also require their
explicit scopes. For example, `.region = "eu"` does
not match a resource value `eu` when the same span has `region = "us"`.
Window-local search retains its separate narrower filter grammar. Expressions never prune sources by
summaries, but are planned newest first like selectors.

Missing and differently typed attributes **do not match even negative
predicates**. Integer-literal attribute predicates do not coerce doubles,
strings or booleans; the pinned Tempo 2.9 Parquet search also excludes a double
`503.5` from `>= 500` and `!= 503`. This is not general TraceQL numeric arithmetic.
Likewise, a float literal never coerces an integer attribute. Float literals round
to float64 (so `9007199254740993.0` equals the stored double
`9007199254740992.0`, but not an original int64). Signed zeros compare equal.
Stored NaN doubles match only `!=` against finite literals; stored infinities
follow IEEE ordering. Nonfinite/overflowing **query literals** reject.
Strings use JSON quoting, not the entire Go/TraceQL string grammar: JSON `\/`
is accepted as `/`, while raw tabs and Go `\x`/octal escapes reject. Do not assume
all string spellings accepted by Tempo are interchangeable.
Double-quoted attribute-key segments are supported, including spaces, Unicode,
commas/parentheses and concatenated pieces: `span."http.route"`,
`span.http."route name"`, `link."odd,key)"`. In identifiers, only `\"` and `\\`
escapes decode; JSON `\n`, `\u` and `\x` escapes do not. Quoted keys and value
literals deliberately have different lexers. Keys are limited to 256 decoded
UTF-8 bytes. Unary negation, arithmetic, pipeline stages other than one trailing `select`,
spanset `&&`/`||`, negated structural operators (`!>>`, ...) and unexpanded
variables reject the whole query. Discovery of `trace:duration` remains a separate API.

Regexes use the existing bounded RE2 subset, fully anchored with dot matching
newlines. `!~` complements the regex **only for a present original string**.
Use `.*health.*` for substring matching; `/health` matches the whole value.

`&&` and `||` combine conditions on **one span**, never conditions satisfied
separately by a parent and child. As in Tempo 2.9, both have the **same precedence
and group left-to-right**. Use parentheses explicitly:

- `a || b && c` means `(a || b) && c`.
- Write `a || (b && c)` for the other grouping.

Duration literals accept nonnegative integer/fractional components using `ns`,
`us`, `µs`, `ms`, `s`, `m`, `h`, including compound forms such as `1m30s`.
Components use Go-compatible bounded fractional parsing/rounding, then truncate
to integer nanoseconds; comparisons and the summed result stay exact int64.
The sum must fit signed int64 nanoseconds. Other spellings, units,
negative durations and bare numbers reject. Span duration is **not** the full
retained trace envelope returned as search metadata.

Trace duration is the full **retained** envelope, not a sum of span durations,
root-only timing, selected-span timing, query-window clipping or an assertion of
exporter completeness. Grafana's migrated min/max duration filters use
`traceDuration`; both aliases compare this same envelope. Candidate discovery
conservatively substitutes true for unknown trace-duration leaves, then recovers
all candidate-ID context **without the ordinary one-hour context horizon**.
Final matching/sampling runs only after bounds are complete. Native evaluation
replays the captured immutable inputs without another GET or payload copy;
reference evaluation revisits its admitted records. The extra pass has its own
1M-row ceiling and consumes the same 20M work budget; 32 MiB/1024 input,
candidate-ID, sample and output bounds remain. Broad retained histories can
therefore fail whole even with `limit=1`. Root predicates also recover all
retained candidate-ID context without a time horizon. A genuinely absent root
has empty name/service intrinsic defaults; conflicting root evidence fails
whole instead of choosing an ingestion-order-dependent root. An observed root
whose original service is absent or not a string cannot establish a known
root service and returns `trace_root_unknown` for a root-service predicate.
Trace metrics, exact-ID filters and window-local legacy filters do not acquire
these complete-context semantics. Broader autocomplete filters use the separate
bounded discovery API.

ID predicates follow the pinned public engine and Parquet fetch, not arbitrary
numeric conversion. Trace IDs trim leading zeroes but preserve query case;
span/link ID strings are case-sensitive. In particular, the pinned Parquet
span-ID byte predicate trims leading zeroes **without padding bytes back**.
Conjunctive search for a leading-zero span/parent ID can consequently return no
match even with a canonical-looking string. Root parent IDs render as sixteen
zeroes. Search preserves these independently observed upstream outcomes;
autocomplete's stored-value/filter completeness extensions are separate.

## Events, structural operators and select

Exceptions recorded as OTel span events (`exception.type`,
`exception.message`, `exception.stacktrace`) are searchable:

```traceql
{ event.exception.type =~ ".*DBConnection.ConnectionError" }
{ event.exception.stacktrace != "" } | select(event.exception.type, event.exception.stacktrace)
```

An `event.` predicate selects the **span**, not an event result. In a pure
conjunction, all requested event predicates must match **one event**; links have
the same single-owner rule. Separate events/links cannot satisfy separate AND
leaves. In mixed boolean programs, Parquet first retains owners matching any
requested leaf, then the engine evaluates the program against the first fetched
value of each requested field. This can differ from independently existential
leaves. Missing or differently typed original values never match, so `!= ""`
means "has a nonempty string value". Sampling uses the last fetched value of a
field, which can differ from the value used for boolean evaluation. These
rules follow the pinned engine/Parquet outputs, not a generalized event language.

Up to four spansets can be joined, left to right, by structural operators.
Each operator returns spans of its **right-hand** spanset related to spans
selected so far:

| Operator | Returns right-hand spans that are |
| --- | --- |
| `{a} >> {b}` | descendants (any depth) of an `a` span |
| `{a} > {b}` | children of an `a` span |
| `{a} << {b}` | ancestors (any depth) of an `a` span |
| `{a} < {b}` | the parent of an `a` span |
| `{a} ~ {b}` | siblings of an `a` span: same parent, not the span itself |

```traceql
{ span.selected_account_handle = "tuist" } >> { span.error.type != "" }
```

Relations follow stored parent span IDs within one trace's complete retained
context: a missing parent ends a chain, parentless spans have no siblings,
duplicate rows of a span share its relatives and cycles terminate. A span is
not its own descendant, so a span carrying both attributes does not match the
example above by itself. The search result's `matched` count and samples are
the returned right-hand spans; traces without one are not results.

A trailing `| select(attr, ...)` (at most 8) adds the named values to every
sampled span. It accepts all five owner scopes, unscoped attributes and the
intrinsics above, including their aliases. As in the public engine, duration,
trace/root and span-ID selections are not duplicated in sampled attributes:
the search metadata/dedicated sample fields already carry them. Parent IDs,
status messages, instrumentation/event/link intrinsics are sampled using their
canonical intrinsic names. Absent original attributes are omitted; selecting an
event/link intrinsic on a span with no such owner returns its upstream empty/
zero default. Event times render as Go duration strings, not integer attributes.

TraceQL metrics accept `event.` predicates; a span counts once however many
of its events match. Structural operators and `select` are search-only:
metrics queries using them reject. Trace-by-ID `q` filters accept `event.`
predicates but reject structural operators and `select`.

Event attribute value sets are **not** added to segment and leaf summaries.
`!= ""` presence predicates, the common error-panel shape, can never be pruned
by bounded value sets, and exception types and messages quickly exceed the
eight values per key that keep a summary complete, so they would mostly
displace resource/span keys that do prune today. Event expressions are planned
newest first in rounds, like other expressions; metrics read every source in
the window either way.

## Context, samples and bounds

All matching spans select candidate trace IDs. Search then recovers their
complete retained context **before** trace overlap, ordering and limiting.
Root metadata, service/error counts and trace duration therefore include
nonmatching spans, other services and earlier roots. Matching is not exporter
completeness. HTTP seconds and MCP nanosecond window semantics remain as
[documented for metadata search](traces.md#experimental-tempo-search).

Samples include original typed values from individually matching predicates;
false OR branches do not invent attributes. Status samples use enum strings;
kind samples use enum strings too. Intrinsic name predicates and `select(name)`
populate the sample's dedicated `name` field (omitted when empty), not an
attribute called `name`. An original `.name` attribute remains an attribute.
Span duration is already represented by `durationNanos`, not an added attribute.
An unscoped predicate samples independently matching values from both owners;
the same key may appear twice. A matching resource value can appear when an
overriding span value makes that leaf false but another OR branch selects the
span. Samples therefore do not prove which boolean branch selected a span.
Samples are bounded examples, not all matching spans or a full trace export.

Expressions permit at most **16 predicates (across all spansets), 8 regexes,
16 nested groups, 4 spansets, 8 selected attributes and 16 KiB query text**, with a 576-token tokenizer ceiling covering those
predicate/group limits. Existing 256-byte keys, 4096-byte string literals and
1024-byte regex limits remain. Native execution independently validates the
program. An additional **20,000,000 work-unit ceiling per scan attempt** charges
two resource/span owners, every original resource/span attribute and every
program instruction before filtering, in both candidate and context passes.
Queries naming event/link attributes or intrinsics also charge each requested
owner and its original attributes, plus a conservative bound for repeated-owner
predicate/selection revisits. Instrumentation predicates charge the original
scope attributes. Complete root context charges every link attribute it traverses,
and structural queries charge every candidate-trace span once per operator.
Structural queries retain 48 bytes plus the rendered sample per candidate-trace
span against the 16 MiB bookkeeping bound.
Nonmatches and false OR branches spend work; exhaustion returns a whole-query
`422 query_resource_limit`, never truncated results.

Expression queries deliberately **do not use the exact-service/ID source
planner**, even when a branch contains service equality. They admit the entire
retained source scope under the existing **1024 objects / 32 MiB compressed
input / 1,000,000 raw rows**, 65,536 candidate IDs and independent 16 MiB
sample/result bounds. Replay uses the same captured binaries without another
provider GET. Selective predicates, smaller windows and limits do not promise
less I/O or work. Legacy uncertainty, corruption, admission and storage failures
retain complete-or-error behavior. These are per-instance safety ceilings, not
capacity or total native-memory guarantees; native work may outlive a deadline.

Original positive-string AND searches retain their existing planner. Window-local
MCP `search_traces` retains its narrower positive string-AND grammar; this change
does **not** widen it. Trace metrics and exact-ID filters continue rejecting the
new scoped/intrinsic forms rather than silently adopting search semantics.

## Remaining client-visible gaps

The pinned Grafana datasource's five attribute scopes, quoted key-builder forms
and 25 advertised intrinsic spellings are covered by this bounded search
grammar. This is not all of TraceQL: arrays, nil/existence tests, arbitrary
expressions, additional pipeline stages, broader spanset/structural forms and
all Go string spellings remain unsupported. Metrics, legacy window filters,
discovery and exact-ID APIs have distinct capability boundaries. No
deployed-client or full generic protocol parity is claimed.

## Upgrade and evidence

Require matching application/native search capability **10** and trace metrics
capability **7**, current trace tuple **`{2,1,3,10,13}`**, on every serving instance
before sending new expressions.
Startup verifies only the local pair, not an old serving pool. There is no
Parquet/envelope/idempotency-format change from these operators. Existing rich
metadata upgrade and retry-draining requirements still apply independently.
Custom adapters need explicit expression-search support or the bounded complete
reference path; old string-search callbacks never receive expression programs,
and adapters without the separate event/structural/select callback never
receive such programs. Empty spansets, boolean/double attributes and name/kind
predicates, plus intrinsic name selection, require the separate typed-search
callback; otherwise the bounded complete reference path runs rather than sending
new wire programs to old adapters.
Trace-duration predicates require their own `tempo_context_search_json/3`
callback or the bounded complete reference path, never an older typed callback.
New intrinsic/link/instrumentation programs require
`tempo_scoped_search_json/3`; expression discovery uses
`tempo_expression_discovery_json/5`. Old adapters receive neither program through
an older callback. The complete reference fallback fetches a max-row sentinel
and fails whole rather than truncating dictionaries or context.

Frozen synthetic inputs and expected results come from actual public **Tempo
2.9.0 Parquet blocks and TraceQL engine execution**, with ordinary offline native
and independent Elixir replay. Local authenticated HTTP ingest, S3-stub
publication, HTTP/MCP queries and the pinned Elixir clients also exercise the new
operators. See [fixture provenance](../test/fixtures/traces/search_expressions/README.md).
An additional [16 public-engine cases](../test/fixtures/traces/tempo_integration/README.md)
cover unscoped collisions, precedence across original types, both sampled owners
and zero-bound windows against actual Tempo 2.9.0 Parquet fetches.
Event, structural and select semantics are checked against a hand-built
fixture shaped like the tuist server's spans
(`test/pulse_web/controllers/tuist_dashboards_test.exs`), with expected spans
derived from Tempo's documented semantics. An additional **48 actual pinned
Tempo public-engine/Parquet cases** establish basic boolean/double/intrinsic
search, empty structural operands and selected names. Those independent oracles
replay through native and reference evaluation, old-adapter fallback, and
authenticated HTTP ingestion → native Parquet → owned S3 → search. See the
[basic-search provenance](../test/fixtures/traces/tempo_integration/README.md#basic-same-span-search-and-discovery-transport).
An additional **20 actual pinned-engine/Parquet cases** compare both trace-duration
aliases and all six comparisons with own-span timing, boolean combinations,
selection and one structural operator. HTTP replay publishes five spans as
separate sources, including two tiny spans over two hours apart, and exercises
a limit-1 query with an early-root-only window and the late-child predicate.
This is not production Alloy, real-provider, separate-node, capacity, full
TraceQL or cutover acceptance.

An additional **76 pinned public-engine/Parquet cases** cover the remaining
Grafana intrinsic/owner/key forms, including original type/missing controls,
repeated owners, ID normalization and independently executed selection outputs.
The first eleven predicates are transplanted unchanged from Tempo's fetch unit
table; the rest are authored probes. Six spans include an absent root, empty
instrumentation, typed links/scope attributes and a child over two hours after
its root. Native/reference and separately published authenticated HTTP/S3
replays retain this asymmetry and compare the frozen upstream outcomes.
See [intrinsic provenance](../test/fixtures/traces/tempo_integration/README.md).
