# Exponential histogram boundary controls

File-only optional producer, pinned to **Go1.26.5 darwin/arm64**, public OTLP
**v1.11.0**, Google protobuf **v1.36.12**, Prometheus **v0.315.0**. Ordinary replay
uses only the native project toolchain; no Go, network, SDK, Collector or backend
build/probe is performed by tests.

## What was actually executed

`produce.go.txt` constructs **1,160** synthetic single-bucket source points,
serializes with actual public protobuf and numeric-enum ProtoJSON, and checks an
actual public JSON round trip. It captures boundary bits for supported Pulse
scales -10..3 around zero, subnormals, the normal/subnormal transition, very large
finite numbers and infinity. Negative bucket indexing uses OTLP's magnitude grid.
The complete request retains typed resource/scope owners, schemas, drops, case
attributes and exact nanoseconds. No nonempty context IDs need a generic-Google
base64 to OTLP-hex adaptation.

`geometry.json` keeps three separate observations:

- **Mathematical grid reference:** decompose exponent into integral/fractional
  parts, compute `Ldexp(Exp2(fraction), integral)` with actual Go math functions.
  This independent computation does not call Pulse.
- **Direct Exp2:** retain the actual result too. On this pinned toolchain,
  direct `Exp2(-1074.5)` underflows to zero while the decomposed computation and
  actual public histogram iterator retain the nearest subnormal. Do not hide
  that counterexample by silently changing expectations or asserting agreement.
- **Actual Prometheus FloatHistogram bucket iterators** for its supported
  schemas -4..3, capturing upper bounds and inclusivity. Prometheus substitutes
  maximum finite at its last finite boundary; Pulse's classic projection uses
  the mathematical infinity instead. Negative upper endpoints are exclusive
  (and rounded-zero endpoint flags are separately captured). This is not exact
  Prometheus native-histogram conversion parity.

Finite geometry comparisons allow relative `1e-14` for independently
rounded libm/precomputed-grid values. Zero/infinity classes and minimum-subnormal
results are exact; cumulative count accounting, source metadata and source float bits
are exact. The controls include mathematically extreme bins that need not be
populatable by real finite-double observations. Public serialization acceptance
is not semantic validation of every such population or full client acceptance.

Additional owned tests cover rounded-boundary mass coalescing with randomized
counts, signed-zero source thresholds, contradictory/partial zero overlaps,
staleness, fixed raw/minimum-scale ceilings, valid-neighbor whole-request 413,
native Parquet and gzip HTTP exact-key replay across independent S3-stub runtime
instances. Neither a reference backend server nor a real provider was queried.
No capacity, separate-node, deployed SDK, default batching or full conformance
claim follows. Prepared tools/dependencies remain trusted, not attested.

`checksums.json` indexes six producer/capture files. The first direct-Exp2 capture
was retained separately during development and replaced only after the observed
subnormal discrepancy was explained and both results were added to the final
capture. Existing numeric/wire/distribution corpora were not refreshed.

## Optional offline reproduction

Prepare pinned tools/cache separately, then run from the repository root:

```sh
producer=$(mktemp -d)
cp test/fixtures/otlp/exponential_boundaries/produce.go.txt "$producer/main.go"
cp test/fixtures/otlp/exponential_boundaries/producer.go.mod.txt "$producer/go.mod"
cp test/fixtures/otlp/exponential_boundaries/producer.go.sum.txt "$producer/go.sum"
output=$(mktemp -d)
(cd "$producer" && GOPROXY=off GOSUMDB=off GOTOOLCHAIN=local GOMAXPROCS=2 \
  go run -mod=readonly . "$output")
```

Use matching Go1.26.5/GOROOT; a separately selected compiler with an inherited
older GOROOT is not a valid build. Missing prepared tools/cache must fail, not
skip. Do not silently refresh frozen outputs or weaken source budgets to fit
larger distributions. See [operator limits and upgrade rules](../../../../docs/metrics.md#exponential-histograms).
