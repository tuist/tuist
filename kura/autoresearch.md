# Autoresearch: Kura bounded-resource throughput

## Objective

Increase Kura's cache throughput and reduce tail latency without weakening its hard memory, file descriptor, temporary disk, or background-work bounds. Prefer removing copies, allocations, system calls, and serialization points over raising limits.

## Metrics

- Primary: ByteStream read materialization throughput (mebibytes per second, higher is better)
- Secondary: functional correctness, peak live buffer count, compile and lint status

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
