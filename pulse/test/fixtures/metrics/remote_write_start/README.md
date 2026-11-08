# Public Remote Write 2.0 created/start timestamp evidence

Generated on 2026-10-25 using **public Prometheus Go schemas and actual public
Prometheus release receivers**, not Pulse encoders/expected-value helpers. Normal
Elixir/Rust test replay is offline; Go and Prometheus are needed only to regenerate.

| Fixture | Public Go module | Release receiver revision | Schema |
| --- | --- | --- | --- |
| `prometheus-3.5.0.json` | `github.com/prometheus/prometheus v0.305.0` | `8be3a9560fbdd18a94dedec4b747c35178177202` | rc.3 series `created_timestamp = 6` |
| `prometheus-3.8.0.json` | `github.com/prometheus/prometheus v0.308.0` | `e44ed351cdf0181f9fde56ba096f4d949f9e295d` | rc.4 sample `start_timestamp = 3`, histogram `start_timestamp = 17` |

Sources:

- [3.5.0 schema](https://github.com/prometheus/prometheus/blob/v3.5.0/prompb/io/prometheus/write/v2/types.proto)
  and [receiver](https://github.com/prometheus/prometheus/blob/v3.5.0/storage/remote/write_handler.go).
- [3.8.0 schema](https://github.com/prometheus/prometheus/blob/v3.8.0/prompb/io/prometheus/write/v2/types.proto)
  and [receiver](https://github.com/prometheus/prometheus/blob/v3.8.0/storage/remote/write_handler.go).
- [Current experimental spec](https://prometheus.io/docs/specs/prw/remote_write_spec_2_0/).
  This corpus does not establish all newer rc.6 modes or stateless validation.

The two receiver binaries are the official linux-amd64 release tarballs at
`https://github.com/prometheus/prometheus/releases/download/vVERSION/prometheus-VERSION.linux-amd64.tar.gz`.
Their archive SHA-256 values are:

```text
3.5.0 e811827af26d822afb09a4f28314f61b618b12cff5369835a67f674d8b46f39a
3.8.0 6f451d0331ceb4ae16aefbb2b28762142251fddd7caadd414d030ff55130b25b
```

## Cases and scope

Each release has 28 cases (56 total), each with two samples 15 seconds apart:
floats, integer exponential histograms, float exponential histograms and custom
histograms, crossed with absent/zero, earlier, equal, later, negative, minimum and
maximum signed-int64 millisecond starts. Modern samples deliberately have
different starts within a series. Zero on wire means unset. The producer sets
fields and independently decodes them using each release's generated public Go
protobuf implementation; `starts_ms` is that result, with unset recorded as null.

`snappy_base64` contains the exact public-produced request. `status` and `written`
are the real HTTP response and sample/histogram/exemplar written-count headers.
`query` is the real receiver's `/api/v1/query` range-selector response, containing
the actual stored sample times and float/histogram values, **not** a resampled
`query_range`. Pulse tests compare instant selectors at both stored times and
assert exactly two raw rows, independently checking the absence of extra zeros.

Both receivers run with **created-timestamp-zero-ingestion disabled (default)**.
The source code gates `AppendCTZeroSample`/`AppendHistogramCTZeroSample` on that
option. This evidence verifies ordinary receiver counts/values without injection;
Prometheus does not expose retained source starts in these query responses, so
source-retention expectations come from public schema round-trip, not TSDB reads.
Pulse's hybrid-layout precedence and preservation through immutable Parquet/CAS,
mixed-null compaction and independent runtime instances are separate regression
checks, not claims about an upstream hybrid schema or a real provider cluster.
No SDK/Alloy/client, full compliance-suite, separate-node, provider-load,
zero-injection, start-aware-rate or delta-conversion acceptance is claimed.

## Regeneration

Use Go 1.25.3. For each version copy `produce.go.txt` to `main.go`, and its
`legacy` (3.5.0) or `modern` (3.8.0) `go.mod.txt`/`go.sum.txt` to `go.mod`/`go.sum`
in an empty scratch directory. Run `go build -o produce .`. Run the corresponding
release receiver against a **fresh disposable TSDB**, with a config containing:

```yaml
global:
  scrape_interval: 1m
scrape_configs: []
```

For 3.5.0 (use port 19038 and the 3.8.0 binary for modern):

```sh
./prometheus --config.file=config.yml --storage.tsdb.path=isolated-data \
  --web.listen-address=127.0.0.1:19035 --web.enable-remote-write-receiver \
  --enable-feature=native-histograms
./produce -legacy -receiver http://localhost:19035 > prometheus-3.5.0.json
# Modern generator: omit -legacy and use http://localhost:19038.
```

Do not scrape anything: recent scraped samples in the same TSDB can reject the
fixed historical fixture timestamps. No receiver zero-injection flag is passed.
The producer sends the v2 Content-Type, Snappy and version headers. Regenerate
only against disposable local receivers. Replay the frozen corpus with:

```sh
mix test test/pulse_web/controllers/remote_write_v2_test.exs \
  test/pulse/storage/s3/keyed_publication_test.exs
```

## SHA-256

```text
740f0e90993ebaddd2241bde37c542fab3c11e17c5422a2b1d2551bbb0eafb73  legacy.go.mod.txt
673436e08ad6318264fc928c1fc7bbb28dc3becfb402726abfa1ed467f1cf242  legacy.go.sum.txt
4f4d61fd6ce58577b42a165cffa57b60a0a67b9376b9fc75fd6a7e895b0cc3c0  modern.go.mod.txt
79783ff2e3dc9c98f72ae17ce8409bace04ef164d688c7f9cfa9591da9386ae9  modern.go.sum.txt
4a1aad35d6400e516cf1849539d6d21d7a415fd4a6d733fb664976e9461414da  produce.go.txt
69925601b9ebdb131ab33e82a1c8511c2c2c12ae540865f16f909e4952c347ee  prometheus-3.5.0.json
993b19a38aaab5499f519e0b456be7d4c408575ad44ac7e2017982f321ce9ec5  prometheus-3.8.0.json
```
