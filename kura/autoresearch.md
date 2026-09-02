# Autoresearch: Kura bounded-resource throughput

## Objective

Increase Kura's cache throughput and reduce tail latency without weakening its hard memory, file descriptor, temporary disk, or background-work bounds. Prefer removing copies, allocations, system calls, and serialization points over raising limits.

## Metrics

- Primary: interleaved ByteStream candidate speedup over the original copying path (ratio, higher is better)
- Secondary: original and candidate throughput, functional correctness, peak live buffer count, compile and lint status

## How to Run

`./autoresearch.sh`

## Files in Scope

- `src/reapi/service.rs`: Remote Execution ByteStream and batch response materialization
- `src/segment/reader.rs`: bounded asynchronous file reads
- `src/store.rs`: append-only segment persistence and metadata access
- `src/accelerated_file_serving.rs`: Linux direct file serving and request classification
- `src/io/mod.rs`: bounded file descriptor operations
- `src/memory/`: admission and resource accounting affected by buffer ownership

## Off Limits

- On-disk segment, blob, or metadata formats
- Replication wire compatibility
- Unbounded queues, caches, buffers, or worker counts
- Raising resource limits to improve a benchmark
- `CHANGELOG.md` and translation files

## Constraints

- Preserve compatibility across a rolling update.
- Keep append-only files append-only and never truncate a mapped file.
- Keep exact response bytes, status codes, headers, authorization, usage, and analytics behavior.
- Keep the benchmark focused enough for repeated local runs.
- Bazel build, focused tests, formatting, and Clippy must pass before handoff.

## Research Notes

- Tokio's `ReaderStream` fills a reusable `BytesMut`, splits it into `Bytes`, and retains the remainder for reuse.
- The generated Google ByteStream `ReadResponse.data` field is a `Vec<u8>` because Prost uses that type for protocol `bytes` fields by default.
- Converting the yielded `Bytes` with `to_vec` performs a full chunk copy. Filling the final `Vec<u8>` directly can remove that pass without changing the protocol.
- Linux `sendfile` and `splice` already cover Kura's eligible plaintext artifact downloads. Remote Execution responses still require protocol framing, so the target there is one owned message buffer plus the encoder and transport buffers.

## What's Been Tried

- Added a release-mode, in-memory ByteStream chunk-materialization benchmark and a correctness test.
- Baseline: the unchanged `ReaderStream` plus `Bytes::to_vec` path reached 17,599.189 mebibytes per second. The cold optimized Bazel build took 1,142 seconds; subsequent experiments reuse its dependency cache, and build duration is not part of the throughput metric.
- Experiment: fill the generated response's final `Vec<u8>` directly through Tokio's `read_buf`, removing the intermediate `BytesMut` allocation and full-chunk copy while retaining the same chunk cap.
- The original 512 mebibyte samples completed in 0.11 to 0.23 seconds and varied from 17,185 to 29,797 mebibytes per second. Increased each sample to 8 gibibytes and the measured set to seven post-warm-up samples without increasing live memory.
- Absolute throughput still ranged from 5,926 to 16,631 mebibytes per second under unrelated host compilation. Replaced it with an interleaved original-versus-candidate speedup ratio, alternating execution order and retaining both absolute rates as secondary diagnostics.
- Identical-function calibration ranged from 0.934 to 1.067. Treat timing changes inside that band as noise and require a deterministic pointer-identity test proving that the response owns the allocation the reader filled.
- Candidate implementation fills the final response `Vec<u8>` through Tokio's uninitialized spare-capacity interface. The original copying helper remains test-only for paired measurements.
- Candidate runs: 2.747 and 4.389 times the original path. The warm confirmation measured median rates of 55,325 versus 12,238 mebibytes per second. Both exceed the identical-function calibration band by a wide margin.
- Follow-up copy audit: ByteStream writes cloned the request metadata and admission guard before consuming the stream, then cloned the resource name on every message. Unary authorization specs also owned duplicate key and hash strings, and batch reads cloned the complete digest list plus every response digest. Move these existing allocations into their consumers and keep authorization specs borrowed until an enabled policy engine builds its owned context.
- Extended request ownership through action-cache updates, missing-blob queries, and batch uploads: move decoded messages, digests, data buffers, metadata, and admission guards into their final consumers after authorization instead of cloning them to keep the request wrapper alive.
- The ownership rewrite compiled with the ByteStream candidate still at 4.467 times the original copy path. Focused ByteStream write, namespace authorization, action-cache transfer, batch transfer, and missing-empty-blob tests passed.
- Plaintext accelerator audit: one request allocated a 16 kibibyte peek buffer and a second exact-size vector merely to consume those same headers. Keep one fixed-capacity buffer per connection, reuse it across keep-alive peeks and consumption, and move denial headers instead of cloning their map.
- The connection-buffer change passed the socket-level peek/consume test, full and ranged accelerator tests, and capacity-shedding coverage. The paired ByteStream benchmark remained at 4.969 times the original copy path.
- Tonic consumes each response vector while encoding it, then yields an owned encoded frame. Hyper can retain up to its configured 512 kibibyte per-stream send buffer while the next frame is encoded. The new peak therefore has three charged owners instead of the old path's four: response vector, encoded frame, and transport buffer. Reduce only ByteStream's admission multiplier from four to three; ordinary file streams retain their existing four-buffer model.
