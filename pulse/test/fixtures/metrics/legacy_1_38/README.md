# Historical 1.38.0 storage fixtures

Generated from unmodified `tuist/pulso` revision
`1cb5d3e2bc9650617712ac2cc3222deeafd7295e` (release 1.38.0), not by
renaming metadata in Pulse output. The original `pulso_codec` was built with
`cargo build --release --offline` using its checked-in Cargo.lock and loaded
through the original `Pulso.Codec.NIF` exports. No live bucket was accessed.

- `indexed.parquet`: `encode_metric_segment_parquet_indexed_v1` with two
  MetricSamples, labels `__name__=work, host=a`, timestamp/value pairs
  `(1, 2.0), (2, 4.0)`, no optional metadata or caller series IDs.
- `metric_final.parquet`, `metric_rollup.parquet`: that indexed object passed
  through `metric_finalize_new(0, 3600000000000, 100, 2, {0, 1})`, add,
  `metric_finalize_finish(builder, 100, 100, 100)` and next until done.
- `logs.parquet`: `encode_log_segment_parquet_v2` of two Logs with timestamps
  1 and 2, service `api`, body `hello`, resource `namespace=tuist`, empty
  attributes, all other optional fields unset.
- `log_rollup.parquet`: those logs passed through
  `log_rollup_new(0, 60000000000, [60000000000])`, add as a segment, finish
  with source keys `["source-a", "source-b"]`.
- `keyed_*.parquet`: original v2 metric encoder, one sample at timestamp 1
  with the same labels; histogram count 2.0/sum 3.0 (other struct defaults),
  exemplar labels `trace_id=abc`, value 2.0/timestamp 1. Histogram sample value
  is nil, exemplar-only sample value 2.0. The three files exercise histogram,
  exemplar, and both together.
- `hashes.json`: original `S3.caller_content_hash(:metrics, records)` hashing
  functions executed unchanged against the original record structs. These
  pin the historical nested struct tags as well as Parquet bytes.

These are source-built artifacts, not downloaded release binaries or proof of
the exact bytes emitted by every historic compiler/dependency/platform build.
