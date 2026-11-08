# Bounded regex controls

`go-controls.json` records 3,664 `regexp.MatchString` answers, plus 1,140
whole-label matching answers, from the standard library in Go 1.27.3
(`darwin/arm64`), generated with `produce.go.txt`.
It exercises ASCII Perl classes, Unicode case folds (Kelvin sign and long s),
vertical tab, codepoint dot, strict dollar anchors, word boundaries and literal
carets/hyphens following word-complement classes and literal closing-brace
repetition. The original 221 answers, including the earliest 80, are unchanged.
The additional 399 answers cover 19 hexadecimal-escape patterns over 21 inputs:
single/counted/lazy repetition, padded digits, Unicode folding, NUL/control
characters, class ranges, escaped metacharacters and literal backslashes.
One complete pattern, `[\x{41}-\x7a]\x61`, comes from Go 1.27.3's
[`regexp/syntax/parse_test.go:124`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L124).
Its private AST expectation is not a matching oracle: all matching answers
are executed independently by Go, with locally chosen inputs. Other new
patterns are local controls, not extra upstream test rows. Go source attribution:
Copyright 2009 The Go Authors, BSD-3-Clause; see the existing
[`Go-LICENSE`](../logs/loki-upstream/Go-LICENSE).
The original 620 maps remain unchanged. Another 1,140 rows cover 30 literal-quote
and octal patterns over 38 values, with independent substring and whole-label
answers. Whole-label matching parses the source using Go's
`syntax.Perl|syntax.DotNL` flags and prints that AST before adding strict anchors.
It does not append anchors inside an unfinished quote. Five complete patterns
come from Go 1.27.3's
[`regexp/syntax/parse_test.go:152–156`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L152-L156),
and one from [line 123](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L123).
Their private AST expectations are not matching oracles. Other patterns and
inputs are local controls, not additional upstream integration rows.

The final 1,904 rows exercise all 14 POSIX classes, positive/named-complement/
outer-negation/double-negation forms, with and without case folding, over
17 inputs. These local controls catch PCRE's different named-class handling of
Unicode folds such as Kelvin sign and long s, including complements.

Ordinary Elixir tests replay these answers against the independent PCRE
reference and native matchers; no Go installation or network is needed.
The Mimir, Loki and Tempo HTTP/S3 suites additionally replay selected independent
answers through actual remote-write/log/OTLP ingestion and Parquet queries.
This corpus is not full RE2, malformed-syntax, deployed-client or capacity conformance.

All 3,664 substring and 1,140 whole-label answers also match byte-for-byte when the producer links Loki's pinned
`github.com/grafana/regexp` dependency
`v0.0.0-20250905093917-f7b3be9d1853` under Go 1.27.3. The offline/read-only
comparison's linked module identity is recorded in
`.amp/in/artifacts/regex-literals-fork.log`; the fork is not required for replay.

| Go 1.27.3 source selection | SHA-256 (including final newline) |
| --- | --- |
| Complete `regexp/syntax/parse_test.go` | `4cd14979742f9b43d287c0c27f62bacead4b1e4e6fe56f8d47570cfff9481d2b` |
| Quote patterns, lines 152–156 | `c56d70060d4eeec1300b4bb42441e6a69a38cbad7a9ad3c812f51ee4d698c87d` |
| Octal pattern, line 123 | `96734c263f7ab0b771e9136789c8fc3889454dc1dc175755709ecbe0bf738b6e` |

Six separate malformed lazy-repetition controls are checked against executed
Go `regexp.Compile` results and retained in the native, Elixir and Mimir HTTP
tests: `a???`, `a{2}??` and four braced-hex variants. They are local controls,
not upstream table rows or additional matching answers. The matching corpus
includes both valid optional-lazy and counted-lazy forms to guard against
rejecting every doubled question mark.

To regenerate deliberately, copy the producer to a `.go` file and run
`GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off go run <producer.go>`.
Review differences instead of silently refreshing expected answers.

## Counted repetition admission and literal braces

`admission-controls.json` records Go 1.27.3 `regexp.Compile` decisions for
53 patterns: 39 accepted and 14 rejected. Each accepted pattern has 27 compact
run-length-encoded inputs with independent substring and whole-label answers
(1,053 of each). `produce.go.txt admission` regenerates this separate fixture;
its default mode preserves `go-controls.json` byte-for-byte.

Eight complete patterns come from Go's `regexp/syntax/parse_test.go`: the
accepted literal-brace row 44 and all seven rejected-count rows 480–483 and
501–503. Private ASTs and diagnostic strings are not output oracles. The
remaining patterns and all matching inputs are local controls. They cover
999/1,000/1,001 boundaries, nested products, inner errors under outer zero,
zero-erasure nesting, alternation, unbounded repetition, leading zeros,
incomplete/overflowing malformed counts, quoting, classes, octals and braced
hex/Unicode escapes. The existing Go license applies.

| Go 1.27.3 `regexp/syntax/parse_test.go` selection | SHA-256 (including final newline) |
| --- | --- |
| Line 44 | `1881387740aeede4536059283a6ab2b02393760e3ec5e8a5a71e1844ebf07028` |
| Lines 480–483 | `61be9b06f64563e799a910c6f39a91faa79cca7aebd4f91be97775500c995b5f` |
| Lines 501–503 | `d631fa2bd7b2e23cac31017862c0a8f090464b588d97e230772f053dc4d5dfce` |

The shared Elixir test replays actual admission and matching through native
substring/full-label engines and PCRE matching for accepted patterns. Three
local `:regex_admission_batch` HTTP tests replay eight distinct ingested values
through the existing Mimir/Loki/Tempo integration harnesses and native
Parquet/S3. Invalid patterns must reject before any storage request. These
are local controls, not additional upstream integration rows or full Go regex,
diagnostic, deployed-client or capacity acceptance.

Both frozen fixtures regenerate byte-identically with the pinned Loki fork
listed above. A temporary independent Go matrix additionally checks 2,610
accepted and 1,686 rejected patterns across nested counts, optional/unbounded
repetitions, alternations, zero-erasure and malformed braces. All three native
substring/full-label paths agree; 156,423 native/reference comparisons pass.
PCRE reaches its execution limit on 177 complex inputs, which are explicitly
counted as unavailable reference results, never nonmatches. Go and all native
paths agree on those inputs. The earlier 514,272-comparison matrix also passes
unchanged. Evidence is under `.amp/in/artifacts/regex-admission-*`.

## Literal class members instead of Rust set operators

`class-controls.json` records 32 local Go 1.27.3 admission cases: 29 accepted
and three rejected. Each accepted pattern has 47 run-length-encoded inputs,
with 1,363 independent substring answers and 1,363 whole-label answers.
`produce.go.txt classes` regenerates it; the producer's original/default and
`admission` outputs remain byte-identical. All three fixtures also match Loki's
pinned regexp fork byte-for-byte.

These are local controls, not copied upstream table/integration rows. They
exercise `&&`/`~~` as literal class members, negation, Unicode case folding,
leading literal `]`, counted/unbounded repetition, named and complement
classes, Perl classes, octal/hex escapes, quoting, outside-class literals and
adjacent ranges. The invalid rows preserve actual Go rejections of `[a-&&]`,
`[~~-x]` and `[a--b]`; escaping a literal member must not repair a bad range.

The existing shared test and all three `:regex_admission_batch` HTTP wrappers
replay these additional cases through native matching and actual persisted
Parquet/S3. All three HTTP wrappers failed before implementation (seed 669),
as did the shared matcher (seed 668). All 370 tests in the affected shared,
metric-matcher, discovery and Mimir/Loki/Tempo suites pass seed 670.
No production matcher switches to PCRE; ordinary patterns still borrow their
source during normalization, and changed patterns use the existing output
buffer without per-member allocations. Other literal-bracket/`--` class forms,
capture-name admission, exact diagnostics and full Go regex/capacity/client
parity remain open. Evidence is under `.amp/in/artifacts/regex-classes-*`.

A separate temporary Go matrix covers 7,184 accepted and eight rejected class
patterns, with 689,664 native/reference substring/full-label comparisons and
no unavailable PCRE results. Both earlier matrices also pass unchanged.
Full precommit seed 672 passes 2,412 tests, with one skipped and 37 optional
exclusions; strict Credo, all 133 Rust tests and strict all-target Clippy pass.

## Literal opening brackets and scalar hyphen ranges

`range-controls.json` preserves 72 local Go 1.27.3 admission cases: 56 accepted
and 16 rejected. Each accepted case has 61 compact inputs, with 3,416 substring
and 3,416 whole-label answers. Run `produce.go.txt ranges` to regenerate; the
three earlier producer modes and JSON fixtures remain byte-identical. This
fixture also matches Loki's pinned regexp fork byte-for-byte. Ordinary replay
requires only Elixir/Rust, not Go or downloads.

These are independent executed matching oracles, not extra copied upstream
integration/table rows. The source contract is Go's left-to-right class parser:
[`regexp/syntax/parse.go:1836–1929`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse.go#L1836-L1929).
The complete installed file's SHA-256 is
`f93b85f4b63a6f6ecb5c1452a6c0ded1fef5953f9c73e5d814dfc08207e7d1b6`.

Cases distinguish literal `[` from POSIX tokens, including malformed tokens,
negated classes, leading `]`, Unicode folding, complete scalar escape endpoints,
literal hyphens after ranges, and `--` ranges versus actual descending ranges.
A named class at a range endpoint starts with the literal scalar `[`, not a
nested-class union. Perl/Unicode class escapes cannot be scalar range endpoints.
Following unfinished quotes, invalid flags/groups and oversized counts verify
that literal brackets do not conceal later admission errors or weaken anchoring.

The existing shared matcher and all three `:regex_admission_batch` HTTP wrappers
replay this fixture through native matching and persisted Parquet/S3; rejected
patterns must perform no storage request. All three HTTP wrappers failed on
valid `[[]` before implementation (seed 673). The Rust normalization pass uses
the existing output buffer without per-member allocations; ordinary unchanged
patterns still borrow their source. Existing program/work/output bounds,
timeouts, native/capability tuples, storage and keyed bytes are unchanged.
Capture-name admission, exact diagnostics and full regex/client/capacity parity
remain open. Evidence is under `.amp/in/artifacts/regex-ranges-*`.

All 375 affected shared/metric/discovery/Mimir/Loki/Tempo tests pass seed 677.
A separate independent Go matrix covers 14,388 accepted and 351 rejected
patterns, with 1,496,352 native/PCRE-reference substring/full-label comparisons
and no unavailable results. All 133 native tests and strict all-target Clippy pass.

Compile preparation avoids another full-pattern allocation/copy when normalized
text needs no further translation or anchoring. A removed scratch check confirms
borrowed pointer identity for unchanged inputs and owned output for actual
rewrites. Regex-program construction and counted-repeat AST validation still
allocate as required; no allocation-free compilation or throughput claim follows.

## Raw headers and inline flag directives

`name-controls.json` retains 44 Go 1.27.3 cases: 16 accepted, 28 rejected,
39 compact inputs and 624 substring plus 624 whole-label answers. The first
two complete patterns are the original capture rows at
[`regexp/syntax/parse_test.go:169–170`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L169-L170).
Their selected-line SHA-256, including the final newline, is
`5bcb1bc4b8c0c0640abab97f1923222ec5bbbde752146b12f023d271e28f953d`.
Other patterns and all matching inputs are local controls, including quoted
fake headers, class boundaries, invalid raw names and octal/quote repairs of
capture/modifier headers. Run `produce.go.txt names` to regenerate.

`flag-controls.json` retains 58 Go cases: 43 accepted, 15 rejected,
44 inputs and 1,892 substring plus 1,892 whole-label answers, with complete
whole-label capture maps. It includes the original `(?-s).` row at
[`parse_test.go:193`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L193),
whose selected-line SHA-256 is
`79374462e47e8e41c2e14c2786bfeba56f7c09eb23ad4d7e331e47ab208070d4`.
The remaining patterns are local controls for empty/repeated flags, disabling
precedence, scoped restoration, case folding, dot/newline/multiline behavior,
atom/quantifier binding and `U`/lazy capture greediness. Missing disabled flags,
unknown/escaped flags, missing atoms and excessive counts reject. Run
`produce.go.txt flags` to regenerate. Go's flag parser contract is
[`parse.go:1201–1253`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse.go#L1201-L1253);
the complete-file hash is recorded in the bracket/range section above.

Go actually executes every matching/capture oracle. For flag rows only,
`reference_pattern` preserves Go's printed substring AST because PCRE rejects
quantifiers immediately after directives, even when Go correctly binds them
to the preceding atom. The PCRE comparison uses that canonical source;
native substring/full-label/capture paths always compile the original raw
pattern. Whole-label answers retain the existing Go DotNL/strict-anchor
adaptation. Ordinary Elixir replay needs no Go or downloads. All six producer
modes, including all older fixtures, also reproduce byte-identically with
Loki's pinned regexp fork. The existing Go license applies.

The shared matcher and all three HTTP/Parquet/S3 wrappers retain these rows,
with no-storage assertions for invalid headers. Before implementation, the
name corpus exposed 19 incorrectly accepted Go-invalid patterns and all three
HTTP wrappers failed (seed 680). All three wrappers also rejected valid `(?)`
before the flag increment (seed 682). These are local protocol controls, not
additional Mimir/Loki/Tempo integration exports or full regex acceptance.

Raw validation uses borrowed iterators, flag masks and the existing output
buffer, without per-header strings. Only patterns containing `U` need a
group-scope greediness stack. Production matching remains non-backtracking;
limits, timeouts, thread pools, native/capability tuples and storage/keyed
bytes are unchanged. Numeric/repeated selector names, broader regexp-parser
metadata grammar (closed below), flag-separated repetition of an already
quantified atom, exact diagnostics and client/provider/capacity acceptance
remain open at this checkpoint.

The final header/flag checkpoint passes all 400 affected tests (seed684),
full precommit with 2,412 passed/one skipped/37 optional exclusions (seed685),
all 133 native tests, strict all-target Clippy and strict Credo. A separate
matrix passes 169,004 header/flag native/reference comparisons; the previous
1,496,352 class/range comparisons also pass unchanged.

## Native named-parser admission

The flag fixture additionally records original ordered capture names and
1,892 independent unanchored named-capture results, including 352 results
for its eight named patterns. Go executes `FindStringSubmatch` on the raw
pattern; full-label/anchored maps remain distinct. Every earlier pattern,
admission decision and matching/anchored-capture answer remains unchanged.
All six producer modes also regenerate byte-identically with Loki's pinned
regexp fork. No Go/network dependency is added to ordinary replay.

Loki's pinned [`NewRegexpParser`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/logql/log/parser.go)
inspects the compiled expression's named groups, not a second regex dialect.
Pulse now does the same with its native byte-regex resource, returning only a
Boolean rather than materializing capture names or values for admission.
The shared test checks the new exact unanchored maps. The HTTP/S3 wrapper
`:regex_parser_flags_batch` replays all eight named patterns over eleven
retained values, including exact parser labels, nonmatch preservation,
GET/form POST and metric filters. It fails at the unchanged PCRE admission
boundary (seed686). Original Loki constructor rows remain intact; four local
controls distinguish fake quote/class headers, unnamed directives and a real
zero-repeated capture. Presence is recorded during the existing validation pass,
before HIR optimization can erase the last capture under `{0}`. This preserves
admission, not full erased-capture extraction parity. These controls are not
additional upstream test rows.

Upgrade matching log app/native artifacts to capability tuple `{1,1,11}`.
Trace/metric tuples, storage/keyed bytes, thread pools and configured resource
ceilings are unchanged. Numeric/repeated selector names, flag-separated nested
repetition, exact diagnostics and full regex/client/provider/capacity acceptance
remain open. Evidence is under `.amp/in/artifacts/regex-parser-flags-*`.

## Unicode property caret negation

`unicode-controls.json` records 37 executed Go 1.27.3 admission decisions:
30 accepted and seven rejected. Each accepted case has 53 compact inputs,
with 1,590 substring and 1,590 whole-label answers, plus exact indexed and
unanchored named-capture maps. The first nine complete
patterns are the Unicode/complement/double-negation section of Go's
[`regexp/syntax/parse_test.go:99–107`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse_test.go#L99-L107).
Private AST expectations are not output oracles; Go executes the matching
answers. The other patterns and all inputs are local controls. Existing Go
attribution/license applies.

| Go 1.27.3 source selection | SHA-256 (including final newline) |
| --- | --- |
| Complete `regexp/syntax/parse_test.go` | `4cd14979742f9b43d287c0c27f62bacead4b1e4e6fe56f8d47570cfff9481d2b` |
| Lines 99–107 | `8b59fdc9e33ee33d406d4f7a6627b45ff033a8d422f2979518f3ab12490af67e` |

Regenerate with `produce.go.txt unicode`. All six earlier modes remain
byte-identical; this fixture also matches Loki's pinned regexp fork byte-for-byte.
Controls cover property negation and double negation, class unions/negation,
case folding, quantifiers, literal quoting/backslashes, a named capture,
Braille boundaries, Latin/Greek/case/Any properties, malformed names and range
endpoints. Full property-name/Unicode-version admission parity remains open.

The existing shared test and three `:regex_admission_batch` HTTP/S3 wrappers
replay this fixture. HTTP keeps its original eight stored ASCII/repetition
values; shared matcher replay additionally covers the Unicode/boundary values.
The named-parser HTTP wrapper also replays its Latin-property capture over the
existing eleven inputs, including the Kelvin sign, with exact extracted labels
and metric filtering. Its original eight flag cases remain intact.
All three HTTP wrappers reject valid `\p{^Braille}` before the implementation
(seed693); the shared matcher fails too (seed692). Native normalization toggles
`p`/`P` and removes one leading caret in its existing output buffer, only at
an actual rewrite. No per-input conversion, new threads, cache, program/work
limits, storage/keyed formats or further capability changes are introduced.
Evidence is under `.amp/in/artifacts/regex-unicode-*`.

## Captures erased by optimization

`erased-capture-controls.json` records 28 accepted Go 1.27.3 patterns over
21 inputs each: 588 substring and 588 whole-label decisions, plus exact
unanchored named maps and anchored numeric/named maps, including nonmatches.
Regenerate with `produce.go.txt erased`; ordinary replay needs no Go or network.
All eight producer modes also match Loki's pinned
`github.com/grafana/regexp v0.0.0-20250905093917-f7b3be9d1853` byte-for-byte.
Earlier fixture outputs remain unchanged.

The first four complete patterns come from Go's zero-repetition substitution
rows in [`regexp/all_test.go:232–235`](https://github.com/golang/go/blob/go1.27.3/src/regexp/all_test.go#L232-L235).
These are executed matching/capture oracles, not copies of the replacement
expectations or additional Loki integration rows. The other patterns and inputs
are local controls. Existing Go copyright/license attribution applies.

| Go 1.27.3 source selection | SHA-256 (including final newline) |
| --- | --- |
| Complete `regexp/all_test.go` | `caffaf144a8db14a7fd0476f8cc4ba51dba750f3b3f32e26cfee6629ee33057c` |
| Lines 232–235 | `f2a3ec2f2042454beebb51738e519ede5474855281e557eaf437b26d466464ba` |

Controls distinguish trailing erased groups from middle holes with live groups
after them; nested/empty captures, `{0}`/`{0,0}`, impossible classes and branches,
optional live groups, both named-header spellings, fake quote/class headers and
UTF-8 byte boundaries are covered. Before the fix, shared replay loses the last
three numeric groups of `(a)(((b))){0}c` (seed698). An ownership regression also
fails: an erased capture must publish an empty value, so a later parser cannot
claim it. This is distinct from a nonmatching parser, which publishes no labels.

The `:regex_erased_capture_batch` HTTP wrapper replays all 23 named cases over
ten persisted inputs, checking exact labels before and after a second parser,
both empty/nonempty metric filters, empty metric results, GET/form POST and
actual Parquet codecs over a local S3-compatible HTTP store. Shared replay covers
the complete 21-input fixture;
the tail/stream regression also checks earlier parser ownership. The independent
source schema is recorded during existing validation, once per compilation.
Boolean compiler paths allocate no capture-name metadata. Named log values
remain borrowed sub-binaries; indexed/named metric aliases share one detached
BEAM value, and native metric pipelines do not copy already-owned captures.

Predicate and regexp/indexed-extraction schemas have an independent 1 MiB logical
ceiling, charging 32 bytes per original group plus raw name bytes even if HIR
erases the entire program. Template named-alias preparation remains separate.
Public compiler tests cover exactly 32,768 anonymous groups versus 32,769,
and a one-group schema at exactly 1 MiB versus one extra name byte. Existing
program, query-work, scan, result and heap limits still apply. This is logical
schema accounting, not a claim about total native memory or throughput.

This checkpoint required log app/native tuple `{1,1,12}`, superseding the
capability-11 snapshots above. Trace/metric tuples and storage/keyed bytes are
unchanged. Full Unicode property-name/version admission, numeric/repeated
selector names, flag-separated nested repetition, exact errors and full
regex/client/provider/capacity acceptance remain open. Evidence is under
`.amp/in/artifacts/regex-erased-*`.

## Flag-separated nested repetitions

`nested-repetition-controls.json` freezes 57 local Go 1.27.3 cases: 46 accepted
and 11 rejected. Each accepted case has 40 inputs with independently executed
substring/full-label matching, unanchored named captures, anchored numeric/named
captures, match counts and expanding/literal replacement answers. This is 1,840
answers for each operation. The replacement text is `<$0:${piece}:${tail}>`.
Normal Elixir replay needs no Go or network; regenerate with `produce.go.txt nested`.
All nine producer modes agree byte-for-byte with Loki's pinned regexp fork,
and all eight earlier frozen fixtures remain unchanged.

These are source-derived controls, not copied upstream test-table or
service-integration rows. Go's
[`repeat`](https://github.com/golang/go/blob/go1.27.3/src/regexp/syntax/parse.go#L400-L447)
rejects immediately adjacent repetition, while the parse loop clears
`lastRepeat` at a flag directive without adding an atom. Thus `x*(?)?` means
`(?:x*)?`, not lazy `x*?`. Complete Go 1.27.3 `regexp/syntax/parse.go` SHA-256:
`f93b85f4b63a6f6ecb5c1452a6c0ded1fef5953f9c73e5d814dfc08207e7d1b6`.
The existing Go copyright/license attribution applies.

Controls distinguish the preceding atom from an entire concatenation, prior
literal flags from subsequent scope, and inner/outer `U`/lazy choices. They also
cover repeated directive chains, named/nested captures, groups, UTF-8 literals,
quotes, escapes, classes, zero erasure, 1,000-copy nested products and adjacent
invalid quantifiers. Canonical Go AST text is only the independent PCRE replay
form; Pulse always receives the original pattern.

The shared regression failed before the change (seed704). The three existing
`:regex_admission_batch` wrappers additionally replay this fixture through
remote write/log/OTLP ingestion, Mimir/Loki/Tempo queries and native Parquet over
local S3-compatible HTTP stores. Rejected patterns cause no storage requests.
The `:regex_parser_flags_batch` now covers 24 named cases, including 15 new
patterns over eleven persisted inputs, exact labels, GET/form POST and metric
filters, including no-series outcomes (seed706).

An independent 5,400-pattern/21-input matrix agrees byte-for-byte between Go
and the pinned Loki fork; all 453,600 native matching/capture checks agree.
Compilation defers synthetic noncapturing opens, sorts their offsets and merges
them once, rather than repeatedly inserting and copying a growing prefix.
Only patterns needing these wrappers pay the additional normalized-pattern copy.
No input-line copy, new capture, match loop, cache or thread pool is introduced.
Existing program/schema/query-work/output ceilings remain; native tests also
check exact template-count work exhaustion. These are not total-memory,
throughput, deployed-provider or capacity guarantees.

This checkpoint required log app/native tuple `{1,1,13}`. Trace/metric tuples and
storage/keyed bytes are unchanged. Full Unicode property-name/version admission,
numeric/repeated selector names, exact errors and full Go regex/client/provider/
capacity acceptance remain open. Evidence is under
`.amp/in/artifacts/regex-nested-*`.

## Numeric and repeated selector capture names

`selector-name-controls.json` freezes 35 Go 1.27.3 cases: 28 accepted and seven
rejected. Twenty-five inputs per accepted pattern provide 700 independent
substring/full-label answers, indexed/named expansion maps and whole-match
`ExpandString` results. Expected alias values come from actual `ExpandString`,
not a map assignment over `SubexpNames`: repeated aliases choose the first
participating capture, including empty matches. Decimal references below one
billion without leading zeros take index precedence over same-spelled names.

The corpus includes the pattern shared by Go's five replacement rows at
[`regexp/all_test.go:218–222`](https://github.com/golang/go/blob/go1.27.3/src/regexp/all_test.go#L218-L222)
and the complete repeated-name `SubexpNames` pattern at
[line 455](https://github.com/golang/go/blob/go1.27.3/src/regexp/all_test.go#L455).
Their original replacement/schema tables remain distinct from this corpus's
locally selected inputs and executed expansion oracles. The existing Go BSD
copyright/license applies. Complete source SHA-256 is
`caffaf144a8db14a7fd0476f8cc4ba51dba750f3b3f32e26cfee6629ee33057c`;
selected-range hashes are `f6040dc1f2833289dadda43c4c908852e4da0a7c0ed7c4226f3d856e3d26eff1`
and `8349c3e17804c3c71b9aa6504c8081eddb5f89d0c4b6620c5584a58294242797`.

Parser admission and the 350 normalized named-capture maps are separate,
source-derived Loki controls, not Go regexp or copied engine-table oracles.
At Loki `5aa4b9212d64d723f63b2770452054aa23df114d`,
`pkg/logql/log/parser.go:303–335` requires unique raw names but validates them
as UTF-8 label names; `util.go:22–39` prefixes numeric names with `_`. Process
capture order keeps the first normalized destination, including unmatched or
erased captures on a matching line. The extracted original constructor executes
all 35 admission decisions independently; the original sanitizer plus an adapted
ordered capture loop agrees with all 350 maps. This does not execute Loki's
whole pipeline. Existing Loki AGPL attribution/license applies to those rules.
Complete parser/util hashes are `e844f4036afcb11d8e84235a77b837a82f21d6c3819a05d3c150eb7812786bfd`
and `50c291848f8db80618b711e1def54ec6e0875c7ef0590afdf6ad809c712cbf24`;
selected ranges hash to `f83974105f9490ca2e5b56581cf8355d98cbf4b81fa73802cdaa50bad9d9e0a3`
and `5a41071095905975f933ae2f06336d501dce8ed8bb237f64d0ec84e8a182d842`.

Regenerate with `produce.go.txt selector-names`. All ten producer modes agree
byte-for-byte with the pinned Loki regex fork; the nine earlier fixtures are
unchanged. Ordinary replay uses only Elixir/Rust, without Go or network.
Native matching/extraction and tail tests replay the complete corpus. The
existing Mimir/Loki/Tempo admission wrappers replay selectors through real
Parquet over local S3-compatible stores; invalid patterns spend no storage
requests. Two additional HTTP wrappers check replacement expansion, numeric
parser labels, normalized/stream collisions and rejection of repeated parser
destinations. The original Loki constructor table remains intact.

An independent 1,694-pattern/ten-input matrix agrees between Go and the pinned
fork; all 50,820 native Boolean/capture comparisons agree. A direct native
Parquet scan answers for all 14 admitted parser patterns with exact labels and
packed samples; exhausted sample budgets fail whole. Preparation strips capture
headers once and retains original indices, groups replacement aliases at compile
time and reuses detached metric values; log captures still borrow input bytes.
Template count/replacement now share the 1 MiB logical schema admission;
counting allocates no name metadata. These are not RSS, throughput or capacity
guarantees. Required log app/native tuple is now `{1,1,14}`; trace/metric tuples
and storage/keyed bytes are unchanged. Full Unicode property-name/version
admission, exact diagnostics and full Go regex/client/provider/capacity parity
remain open. Evidence is under `.amp/in/artifacts/regex-selector-names-*`.

## Unicode property names and Unicode 17 membership

`unicode-property-controls.json` freezes 973 admission decisions (953 accepted,
20 rejected), with 54 inputs and 51,462 executed answers for each of substring
and whole-label matching. Capturing patterns also retain 108 full-match capture
maps. All 215 canonical categories/scripts/special properties, both signs,
both folding states and every category alias are covered. The complete 22
property patterns at Go 1.27.3's `regexp/syntax/parse_test.go:99–120` are present;
private AST expectations are not matching oracles. Other patterns and all inputs
are local executed controls, not additional upstream integration-test rows.

The separate BSD-3-Clause `unicode-properties-producer.go.txt` executes Loki's
pinned `github.com/grafana/regexp v0.0.0-20250905093917-f7b3be9d1853` under
Go 1.27.3 / Unicode 17. Its root `regexp.go` imports standard-library
`regexp/syntax`, **not** the fork's older, unused `syntax` directory. Thus aliases,
loose ASCII name spelling and Unicode membership follow the current standard
parser. A separate standard-library execution agrees on all 973 decisions and
102,924 Boolean answers. Normal Elixir replay needs no Go or network.

The producer's `tables` mode exports native scalar interval pairs and the exact
property-specific `FoldCategory`/`FoldScript` additions. Surrogates are excluded;
intervals adjacent across their hole coalesce without surrogate endpoints.
`LC` deliberately does not acquire Rust's additional U+0345 fold. Class members
are folded separately, then unioned and negated, before disabling another fold
pass on the emitted atom. Named/numeric capture positions remain unchanged.
Controls include newly assigned Unicode 17 letters/scripts, category aliases,
unassigned boundaries, LC unions/negation, surrogate-adjacent scalars, scoped
flags, repeated properties, erased captures and invalid properties under `{0}`.

Elixir tests replay every native Boolean/capture answer and reject oversized
expansions before union or zero-repeat optimization can hide them. Three local
Mimir/Loki/Tempo HTTP/Parquet/S3 wrappers replay 49 accepted and 20 rejected rows
over 15 stored values: 966 request evaluations, including GET/form POST, positive/
negative log and metric filters, and resource/span trace predicates. Rejections
perform no storage requests. These are local provider/consumer controls, not
tests against deployed upstream services or SDK/client/capacity acceptance.

Separate scratch validation compares all 1,112,064 Unicode scalars for 860
canonical property/sign/folding patterns. Both native string and byte engines
agree exactly with the actual pinned Go dependency. This is exhaustive property
membership evidence, not exhaustive regex grammar or literal/class case folding.

Preparation uses static native interval data and a 32-byte lookup key, without
copying input values or adding caches, dependencies or threads. Its independent
1 MiB logical expansion charge reserves 21 bytes per source range plus 24 per
property before simplification; emitted text also reserves a bounded maximum
before each write. Program/DFA/schema/query-work limits remain independent.
Large repeated-property expressions can intentionally reject before upstream.
Required log app/native tuple is `{1,1,15}`; trace/metric tuples, stored and keyed
bytes are unchanged. Full Go regex/case-fold/diagnostic/capacity parity remains
open. Evidence is under `.amp/in/artifacts/regex-properties-*`.

Regenerate deliberately in a temporary Go module requiring the exact fork above,
using Go 1.27.3 with `GOTOOLCHAIN=local`. Copy the producer to `main.go`, then
run `go run main.go fixtures` for the JSON and `go run main.go tables` for
`native/pulse_codec/src/query_regex_unicode.rs`; run `rustfmt` on the latter.
Both modes regenerate byte-identically with module downloads disabled when
the pinned dependency is cached. Existing producers/fixtures remain unchanged.

| Source/artifact | SHA-256 (including final newline) |
| --- | --- |
| Go `regexp/syntax/parse.go` | `f93b85f4b63a6f6ecb5c1452a6c0ded1fef5953f9c73e5d814dfc08207e7d1b6` |
| Go `regexp/syntax/parse_test.go` | `4cd14979742f9b43d287c0c27f62bacead4b1e4e6fe56f8d47570cfff9481d2b` |
| Go `parse_test.go:99–120` | `044d298f483221e574373b1d662b3c39282ed30ff86c52322548d10e5494f08d` |
| Go `unicode/tables.go` | `ac0e5d5d1b58ed4b02d7cb4a0085bdefbdb4f7aae6fadddbc9477f8463da8bd8` |
| `unicode-property-controls.json` | `55fe01f58e13149dee54dcc3ef5b89e281b37c9dc8e44d68095684b2afef8c19` |
| `unicode-properties-producer.go.txt` | `27fca4ca6f1777b49eb7874063f7229819581416632fc63845cc87c1b43f4f01` |
| Formatted `query_regex_unicode.rs` | `3f30bb408a2254d2aaf551b4181d135c66c97dc28539960f7eb4ce2c98fd1ce9` |

Go attribution is Copyright 2009 The Go Authors, BSD-3-Clause; see the adjacent
linked Go license above. No Go/fork matching implementation is copied.

## Scalar class complements across the surrogate hole

`scalar-complement-controls.json` freezes 99 local executed patterns (94
accepted, five rejected) over 34 inputs, with 6,392 substring/whole-label
Boolean answers, full and named capture results, 3,196 counts and 6,392
expanded/literal replacement results. These are independent Go 1.27.3 runtime
oracles, not copied upstream integration-table rows. Regenerate with
`produce.go.txt scalar-complements`; executing the pinned Loki regex fork
above gives byte-identical output. Normal replay needs only Elixir/Rust.

Controls cover both orders of raw/hex U+D7FF and U+E000, mixed/padded hex,
range endpoints, positive/negative/folded classes, one-sided exclusions,
literal brackets/hyphens, POSIX/Perl/property unions, captures, zero/flag-separated
repetitions, class-state reset, quotes/backslashes and invalid grammar. The
regression rejects U+D7FF/U+E000 while retaining U+D7FE/U+E001. Canonical Go AST
strings remain provenance: Go can print surrogate endpoints that PCRE/Rust
cannot parse, so these controls compare native results directly to the executed
Go answers, not to that printed text as a second regex dialect.

The three existing Mimir/Loki/Tempo HTTP/Parquet/S3 wrappers replay every new
pattern over 17 persisted values, adding 1,386 request evaluations. They cover
positive/negative metric/log selectors, log pipelines, GET/form POST and
resource/span trace predicates. Invalid patterns perform no storage requests.
Separate scratch execution checks all 1,112,064 Unicode scalars against the
actual pinned Go dependency for 84 single-class variants; both native string
and byte engines agree on every scalar, without hash-only comparisons.

Preparation tracks two endpoints in the existing normalization scan and joins
only endpoints already present in a negated class. No Unicode scalar is added
to the positive set. Ordinary classes stay borrowed; there is no extra class
parse/expansion, retained input copy, cache, matching loop or thread pool.
Existing admission/program/schema/work limits remain. Required log app/native
tuple is `{1,1,16}`; trace/metric tuples and storage/keyed bytes are unchanged.
Literal/class-range Unicode-version folding and full regex/diagnostic/client/
capacity parity remain open. Evidence is under
`.amp/in/artifacts/regex-scalar-complements-*`.

Fixture SHA-256: `68a335c73f0c75b45cff6ade2d2a6b5f2e08f5b11e2ad78d5f2aaa562156dffa`.
Producer SHA-256: `f640e947e799a8c0e83391bd8f91218e3c6782137d6be4a3475022a39f463f99`.
