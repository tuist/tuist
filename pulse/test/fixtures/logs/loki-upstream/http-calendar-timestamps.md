# HTTP calendar timestamps: pinned Go helper oracles

`http-calendar-timestamps.json` freezes **105 cases**: all **16 original rows**
of Go 1.27.3's `longFractionalDigitsTests`, followed by **89 authored controls**.
All 16 source rows succeed and retain their original fractional-nanosecond
assertions. The controls yield 45 Go successes and 44 Go rejections. There are
61 Go successes in total, five outside signed-int64 Unix nanoseconds. Controls
are supplementary executed helper oracles, never additional upstream table rows.
Every input is at most 51 bytes; no optional oversized ceiling control is included.

## Sources and scope

- Go [`src/time/format_test.go:952–993`](https://github.com/golang/go/blob/go1.27.3/src/time/format_test.go#L952-L993):
  the complete table (952–977) and complete
  `TestParseFractionalSecondsLongerThanNineDigits` (980–993). Standard-library
  AST extraction preserves all 16 inputs in source order and every original
  `want`, including zeros. The source test checks both RFC3339 and RFC3339Nano;
  this fixture executes **RFC3339Nano only**, the helper used by Loki. The source
  comment says “15 digits” for its final input, which actually has 16 fractional
  digits; neither the input nor the comment is corrected.
- Loki [`pkg/loghttp/params.go:175–198`](https://github.com/grafana/loki/blob/5aa4b9212d64d723f63b2770452054aa23df114d/pkg/loghttp/params.go#L175-L198),
  revision `5aa4b9212d64d723f63b2770452054aa23df114d`: `parseTimestamp`
  delegates inputs that fail numeric parsing to `time.Parse(time.RFC3339Nano, value)`.
  Its full function is preserved as provenance. This fixture executes that
  **actual Go helper**, not Loki HTTP or Pulse. Numeric timestamps, defaults,
  request error selection/text, HTTP status, storage and query execution are
  outside its scope. Rejected calendar strings can produce a different outer
  Loki diagnostic because `parseTimestamp` returns its integer-parse error.

The original Go table/test are copyright The Go Authors, BSD-3-Clause, under
the adjacent `Go-LICENSE`. The embedded Loki function is copyright Grafana Labs
contributors, AGPL-3.0-only, under the adjacent `LICENSE`. Authored controls are
explicitly distinguished from both sources. No additional license file is needed.

## Exact schema, version 1

The envelope has exactly:

- `schema_version`: integer `1`.
- `go_version`: string `"go1.27.3"`, checked against `runtime.Version()`.
- `sources`: ordered Go/Loki provenance objects, each with `repository`, `path`,
  full-file `sha256`, and `selections`. Go has `version`; Loki has `revision`.
  Each selection has `name`, inclusive `[start, end]` `lines`, `original_go`
  (AST node bytes plus one final newline), and its `sha256`. Original intervening
  comments inside the selected declaration/function remain verbatim.
- `rows`: ordered objects described below.

Every row has exactly these required fields:

- `id`: stable unique string. Original rows are `go-long-fraction-01` through
  `go-long-fraction-16`; controls use descriptive `control-...` identifiers.
- `input`: original or authored string, never normalized before parsing.
- `source_kind`: `"upstream_table"` or `"authored_control"`.
- `expected_ns`: exact signed decimal Unix-nanosecond **string** on Go success,
  JSON `null` on Go rejection. This is an executed Go-helper result, not an
  original upstream absolute-time assertion.
- `reject`: Boolean indicating **Go helper rejection only**.

Only upstream rows additionally have `original_fractional_ns`: the original
integer `want` in the range 0–999999999, including explicit zero. The producer
asserts successful parsing and equality of `time.Time.Nanosecond()` to each
original value. Controls never acquire invented original assertions.

Exact conversion is `big.Int(Unix seconds) * 1000000000 + Nanosecond()`; there
is no float or overflowing `UnixNano()` conversion. Four-digit parsed years
have int64-safe Unix seconds, even though their nanosecond totals can overflow.
Negative fractional instants use floor seconds plus positive nanoseconds, so
`1969-12-31T23:59:59.999999999Z` is exactly `"-1"`.

### Go grammar is not Pulse range policy

Five Go-success rows are intentionally preserved outside signed-int64
nanoseconds: `control-year-zero`, `control-year-one`, `control-year-9999`,
`control-int64-min-outside` and `control-int64-max-outside`. Their `reject`
remains **false** and their exact large `expected_ns` remains present. Pulse's
required signed-int64 admission must reject these separately; the fixture does
not relabel that range policy as Go rejection or contain Pulse expectations.
The exact endpoints are `-9223372036854775808` and `9223372036854775807`;
controls include each endpoint, one nanosecond inside/outside, equivalent
nonzero-zone forms and extra fractional digits truncated back to the endpoint.

## Observed grammar

Executed controls show these potentially surprising Go 1.27.3 behaviors:

- Single-digit clock hours `0` and `1` succeed, as do their zero-padded forms;
  minutes/seconds still require two digits. Clock hour `24` rejects.
- Both dot and comma fractions work, with 1, 6, 9, 10 and 30 digits. Digits
  beyond nine **truncate**, never round. An omitted fraction succeeds; a dot
  or comma with zero following digits rejects. Mixed separators reject.
- Both zone signs accept `23:59`, **`24:00`, `00:60` and `24:60`**. These are
  offsets, not clock hours/minutes: `+24:60` means minus 25 hours from the
  supplied local time. Zone hour `25` and zone minute `61` reject, including
  mixed boundary combinations. `+00:00` and `-00:00` both yield epoch zero.
- Year zero, year one and year 9999 parse successfully. Invalid leap days,
  invalid month/day values and leap seconds reject. Negative/five-digit years,
  missing/named/malformed zones, lowercase `t`/`z`, space/date/time separator
  substitutions and leading/trailing whitespace/data/NUL reject in this set.

This is a bounded grammar selection, not exhaustive RFC3339 or Loki HTTP parity,
parser-error parity, client acceptance or capacity evidence. No production or
HTTP replay is claimed by this fixture-only change. Checked-in JSON replay
requires no Go, network, Python or downloaded module.

## Offline regeneration and validation

Run from the repository root, with the existing pinned Loki checkout:

```sh
export GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOWORK=off GO111MODULE=off
GO_HOME=/Users/pepicrft/.local/share/mise/installs/go/1.27.3
scratch=$(mktemp -d .amp/in/http-calendar-regenerate.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cp test/fixtures/logs/loki-upstream/http-calendar-timestamps-producer.go.txt "$scratch/main.go"
"$GO_HOME/bin/go" version
test -z "$("$GO_HOME/bin/gofmt" -l "$scratch/main.go")"
"$GO_HOME/bin/go" vet "$scratch/main.go"
"$GO_HOME/bin/go" build -o "$scratch/producer" "$scratch/main.go"
"$scratch/producer" "$GO_HOME/src/time/format_test.go" \
  /tmp/amp-librarian/grafana__loki/pkg/loghttp/params.go > "$scratch/first.json"
"$scratch/producer" "$GO_HOME/src/time/format_test.go" \
  /tmp/amp-librarian/grafana__loki/pkg/loghttp/params.go > "$scratch/second.json"
cmp "$scratch/first.json" "$scratch/second.json"
cmp "$scratch/first.json" test/fixtures/logs/loki-upstream/http-calendar-timestamps.json
```

Ensure `/.amp/in/` is in the repository-local exclude file before creating
scratch. The producer hash-guards both complete source files before output,
checks complete selection counts, unique IDs, input lengths and all original
fractional assertions. Changed-byte negative controls for **both** files fail
with source-hash mismatch and empty stdout. Runtime versions other than
`go1.27.3` reject; toolchain auto-download is disabled.

Validation performed: pinned offline build, `go vet`, clean `gofmt -d`, two
byte-identical invocations, both changed-source guards, and independent Elixir
`JSON.decode!` checks of counts/IDs, input lengths, null/reject equivalence,
canonical exact integers, all 16 fractional assertions, embedded selection
hashes and the five out-of-range successes. No application compilation or
production tests were run for these independently owned fixtures.

| Complete file, including final newline | SHA-256 |
| --- | --- |
| Go `src/time/format_test.go` | `f8646ea90208c0904b5988685c2d78a5f90535ef98a2b4dcd8d53fbb45f0d9a4` |
| Loki `pkg/loghttp/params.go` | `dc0de59305ac3be3577395fe984a37bd75bdd290a3a23e15c6d206139a928f6d` |
| `http-calendar-timestamps.json` | `90f5f41d1fbac7cbf4012e48be92da682a305d9be7ea432976a1870e44ad00cc` |
| `http-calendar-timestamps-producer.go.txt` | `d98343f065f4460fbf9eee88d922c7ea3a7a76cf93216135e063688e4867ea1a` |

## Pulse replay continuation

`test/pulse/loki/http_params_test.exs` replays all 105 frozen inputs against the
public timestamp parser. Go-success values outside signed-int64 nanoseconds
remain explicit policy rejections, never relabeled Go errors. Calendar conversion
uses exact integer offset/fraction arithmetic; numeric timestamp handling and
the 128-byte admission ceiling are unchanged.

The `http_calendar_batch` test in `loki_upstream_integration_test.exs` uses six
independent Go-oracle spellings, including single-digit hours, timezone `24:00`,
`00:60` and `-24:60`, comma fractions and ten-digit truncation. Three neighboring
samples per stream prove exact inclusive log bounds and instant range-function
endpoints through GET/form POST and native Parquet/owned-loopback S3. Six
malformed/range/length controls reject before provider requests. There are
36 successful read attempts and 36 rejections, not 72 upstream source rows.
The same HTTP scenario failed on the unchanged parser and passes with the fix.

```sh
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse/loki/http_params_test.exs
ERL_FLAGS='+S 4:4' PULSE_NIF_FORCE_BUILD=1 mise exec -- mix test \
  test/pulse_web/controllers/loki_upstream_integration_test.exs \
  --only http_calendar_batch --warnings-as-errors --seed 739
```

Upgrade query-serving applications for the changed grammar. No native tuple,
storage/keyed bytes or resource ceilings change. This replay does not establish
exhaustive calendar grammar, exact diagnostics or deployed/client acceptance.
