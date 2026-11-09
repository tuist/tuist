# Log Parquet compatibility fixtures

These synthetic Arrow/Parquet files were generated independently of the NIF by
`native/pulse_codec/examples/log_compatibility_fixtures.rs`, using the project's
pinned Arrow/Parquet 54 dependencies. They test reader compatibility, not SDK
traffic, provider durability or migration acceptance.

- `legacy_log.parquet`: ten historical log columns, no `otlp` column. New readers
  return `otlp: nil` while preserving the historical projected fields.
- `legacy_expanded_log.parquet`: 32 historical ten-column rows with one repeated
  JSON-escaped body larger than 3 MB. Dictionary compression keeps the file below
  3 KiB, but decoding its body column expands beyond 96 MB. Bounded readers must
  charge that expansion even when filters reject every row. This historical
  fixture does not relax the current 16 MiB normalized write ceiling.
- `invalid_otlp_type.parquet`: a present `otlp` column with an integer Arrow type.
  Readers must fail rather than treating it as absent legacy metadata.
- `invalid_otlp_value.parquet`: a UTF-8 `otlp` column containing an array rather
  than an envelope map. Readers must fail rather than discarding the value.

Reproduce from the repository root:

```sh
cargo run --manifest-path native/pulse_codec/Cargo.toml \
  --example log_compatibility_fixtures -- test/fixtures/logs
```

SHA-256:

| Fixture | SHA-256 |
| --- | --- |
| Legacy | `98e5d3689b0f83f38dc2bd1e20f9bfbff586113241baa3db0f8495c7392bfa06` |
| Legacy expanded | `1f8cdad5d5234195dad62e01d7a1dd02c246474a7645f12cd6b8bf918d2f4c1d` |
| Invalid type | `797f38630eb076e418849441f9f10a932ba69c4f04f011921dc401b2fd7e9326` |
| Invalid value | `fe74b7b1d42e704f1e98345d82ee6a2c056e8815bb1638f9cb7d9693b7f0b626` |

## Exact upstream Loki volume cases

`volume-upstream.json` extracts the three input streams, six chunk sizes and
all ten leaf cases from Grafana Loki v3.5.0's
[`TestTSDBIndex_Volume/aggregate by labels`](https://github.com/grafana/loki/blob/4b16bc4fa823f7ec6e865ebf51fad89d98a2371c/pkg/storage/stores/shipper/indexshipper/tsdb/single_file_index_test.go#L593).
The authored `extract_volume.go.txt` reads Go syntax and evaluates the original
integer expectations. It never derives expected results from Pulse or rescales
the expected volumes. It refuses a source file with a different SHA-256.

Eight portable cases replay through both volume HTTP endpoints and GET/form
POST, using real ingestion, native Parquet and the native S3 client against an
owned local S3-compatible server. Each upstream chunk becomes one ASCII line of
exactly `KB * 1024` bytes. Fixed timestamps place all six lines inside the query
window and one range bucket. Loki's match-all sentinel becomes `{}`. Its explicit
`__loki_tenant__="fake"` matcher stays in the copied selector, in addition to
authenticated `X-Scope-OrgID: fake`; the internal name must never appear in the
result. Stream label names/values, targets, limit, expected byte totals and
ordering are unchanged.

Two upstream-only cases remain in the fixture with explicit exclusions, not
modified expectations: an internal chunk-filter callback with no public Pulse
equivalent, and proportional partial-chunk estimates, which differ from Pulse's
exact row selection. Separate Pulse tests cover exact time boundaries, multiple
buckets, empty/missing labels, tenant isolation and resource limits. This is
aggregation conformance, not chunk-index cost or complete Loki parity.

The unmodified upstream label-volume, response-conversion and volume-middleware
tests were also executed successfully in the pinned checkout. No Loki Go source
is vendored or relicensed; its external checkout retains its AGPL-3.0 license.
Normal fixture replay uses Elixir/Rust only, without Go or network access.

Optional regeneration from the Pulse repository root (requires Go and Git):

```sh
REFERENCE="$(mktemp -d)/loki"
git clone --depth 1 --branch v3.5.0 https://github.com/grafana/loki.git "$REFERENCE"
test "$(git -C "$REFERENCE" rev-parse HEAD)" = 4b16bc4fa823f7ec6e865ebf51fad89d98a2371c
go test -C "$REFERENCE" -mod=vendor ./pkg/storage/stores/shipper/indexshipper/tsdb \
  -run '^TestTSDBIndex_Volume$/aggregate_by_labels' -count=1
go test -C "$REFERENCE" -mod=vendor ./pkg/querier/queryrange \
  -run '^(Test_toPrometheusResponse|Test_VolumeMiddleware)$' -count=1
cp test/fixtures/logs/extract_volume.go.txt "${REFERENCE%/loki}/extract_volume.go"
go run "${REFERENCE%/loki}/extract_volume.go" "$REFERENCE" > "${REFERENCE%/loki}/volume-upstream.json"
cmp test/fixtures/logs/volume-upstream.json "${REFERENCE%/loki}/volume-upstream.json"
```

SHA-256:

| File | SHA-256 |
| --- | --- |
| Upstream test source | `39503947f978f862aeb8e5db5879831f95acf7d03092ce75952ccdc2b8940b30` |
| Extracted fixture | `1e7aa4afbb20f3e1d26fd94fd5da9ea66716e527260c4ae3933d11ada1b126fd` |
| Authored extractor | `a96e2bdc8880a0800681d3d2f260ac4da12e216206d1d839bf09f5d6ea53cfd8` |

## Pinned upstream Loki public integration cases

[`loki-upstream/README.md`](loki-upstream/README.md) maps the Elixir HTTP/S3
integration checks to Loki revision `5aa4b9212d64d723f63b2770452054aa23df114d`,
including attribution/license, original cases, source hashes, fixture/harness
adaptations, discovered protocol gaps and unported suite boundaries.
