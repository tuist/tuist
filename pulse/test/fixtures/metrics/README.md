# Metric Parquet compatibility fixtures

`non_finite.parquet` is a historical independent six-column PyArrow fixture:
it contains a finite sample and the exact Prometheus stale NaN payload. Its
original bytes remain pinned; no Python/PyArrow tooling is required or invoked.
To generate equivalent logical rows with the existing Rust dependencies:

```sh
cargo run --manifest-path native/pulse_codec/Cargo.toml \
  --example metric_non_finite_fixture -- /tmp/non_finite.parquet
```

Different Parquet writers need not produce identical bytes. Do not replace the
historical independent artifact just to make its checksum match a Rust writer.

The three compatibility files below are synthetic reader fixtures produced independently of the NIF
using the pinned Arrow/Parquet 54 dependencies:

```sh
cargo run --manifest-path native/pulse_codec/Cargo.toml \
  --example metric_compatibility_fixtures -- test/fixtures/metrics
```

- `legacy_metric.parquet`: historical six-column schema, signed zero and an
  explicitly supplied series ID. Labels, not hashes, remain sample identity.
  New readers must return `otlp: nil`.
- `invalid_otlp_type.parquet`: present integer `otlp` column, not nullable UTF-8
  JSON. Readers must fail, not classify it as legacy absence.
- `invalid_otlp_value.parquet`: UTF-8 array rather than an envelope map. Readers
  must fail, not discard metadata.

These are codec fixtures, not SDK traffic, throughput or migration evidence.

SHA-256:

| Fixture | SHA-256 |
| --- | --- |
| Nonfinite | `c142d4c7c08aebb38f5f5c69d51c64f7fc39a1e6874eb4e9f17ca9eed140a81b` |
| Legacy | `15b9440ff38279d1d9cfe8043391d80f5ad82208ace3a4cf2755eef274828d5d` |
| Invalid type | `03e4e878c97cfcb03f9fe1efbc18e6bcea809d43e94d94ae235d423a22cab692` |
| Invalid value | `1ea7faa069e10effde494dbbadbf4d681462235eef1b128fae29e7d9fe8574a5` |
| Keyed v2 baseline | `1293718ff4c8e0816ded0407022b6f094683295f3fb2e9e67f086273527134d9` |

## Frozen keyed-writer baseline

`keyed_metric_v2.parquet` is a **first-party byte-regression golden**, not an
independent producer or a historical released artifact. It was captured from
the preserved `encode_metric_segment_parquet_v2` branch while adding optional
footer postings. That branch is source-equivalent to the pre-postings writer
and does not emit the new footer key. Capture: Darwin arm64, pinned Arrow/Parquet
54.3.1, 2058 bytes; the SHA above pins the actual artifact, not all producers.

Inputs are two `%Pulse.Record.MetricSample{}` records, in order: timestamp_ns 1 / 2,
value 1.0 / 2.0, labels `%{"__name__" => "requests", "host" => "a"}` / host `"b"`,
default nil `series_id` / `otlp`. The S3 compactor regression requires the v2
encoder and keyed append/retry objects to match these bytes exactly, then checks
fresh unkeyed/compacted objects can acquire postings without losing samples.

To inspect/reproduce outside the test (do not blindly overwrite the golden):

```sh
MIX_ENV=test mix run -e 'alias Pulse.Record.MetricSample; records = for {ts, host} <- [{1, "a"}, {2, "b"}], do: %MetricSample{timestamp_ns: ts, value: ts / 1, labels: %{"__name__" => "requests", "host" => host}}; {:ok, blob, _, _, _} = Pulse.Codec.NIF.encode_metric_segment_parquet_v2(records); File.write!("/tmp/keyed_metric_v2.parquet", blob)'
```

A dependency/platform/encoder change that changes bytes needs an explicit keyed
publication compatibility decision, not an automatic fixture refresh. The exact
assertion also runs on Linux CI: a cross-platform byte difference is a genuine
keyed-stability signal to investigate, not a reason to skip the test or refresh
the fixture. This capture is not independent evidence that every platform agrees.
Keyed PUTs now use conditional creation plus exact-byte verification. This golden
guards against future permanent byte-conflict responses as well as documenting
the earlier overwrite hazard; automatic semantic cross-encoder recovery is not
implemented.
This golden cannot prove all historical writers or deployments are byte-compatible.

## Large footer snapshot fixture

`large_footer.parquet` is a first-party Arrow/Parquet 54.3.1 fixture, not an
independent upstream oracle or deployed-provider evidence. SHA-256:
`ac90d352fddfe221d6d5e865d49f19b42bcd3c12b115d16094aa6a8323724972`.
It contains two scalar samples at nanoseconds 1/2, values 1.0/2.0, canonical
`__name__=m,host=a`, caller hash 7, and one row per group. Unknown footer metadata
contains exactly 70,000 `p` bytes. The six-column file has no postings or OTLP
metadata; a complete footer requires more than the initial 64 KiB probe.

Reproduce with the ordinary Rust toolchain (no Python, network or service):

```sh
cargo run --manifest-path native/pulse_codec/Cargo.toml --example metric_footer_fixture -- /tmp/large_footer.parquet
```

Snapshot tests use the real native S3 client against an owned local HTTP store,
verify one bounded expanded suffix and matching ETag, and expand only this
unknown padding string in memory to exercise a footer exceeding 1 MiB. Compact
Thrift string/footer lengths are updated, so normal full decoding remains valid.
A damaged final magic must fail, not be mistaken for an empty time window.
These are bounded local protocol fixtures, not authentication, capacity or
separate-node acceptance. The keyed golden above is unchanged.
