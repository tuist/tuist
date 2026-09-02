# Autoresearch: Kura bounded-resource throughput

## Objective

Increase Kura's cache throughput and reduce tail latency without weakening its hard memory, file descriptor, temporary disk, or background-work bounds. Prefer removing copies, allocations, system calls, and serialization points over raising limits.

## Metrics

- Primary: paired accelerated-transfer setup speedup from moving the classified request's owned fields into their final consumers (ratio, higher is better)
- Secondary: deterministic pointer identity, retained request fields, functional correctness, compile and lint status

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
- [Tokio implements ordinary file operations on its blocking pool](https://docs.rs/tokio/latest/tokio/fs/index.html). Kura's `SegmentReader` likewise performs positional reads there, but previously returned a private vector and then copied it into the caller's asynchronous read buffer. Returning that owned vector directly removes the copy without changing runtimes.
- The separate [`tokio-uring` runtime](https://github.com/tokio-rs/tokio-uring) accepts owned buffers, but requires a ring-specific runtime and file resources. Measure the remaining blocking-pool dispatch cost after removing Kura's copy before considering that operationally larger change.
- Production Kura nodes advertise 1- or 3-gigabit-per-second public egress budgets. At the fastest rate, one 512-kibibyte chunk occupies the wire for 1.398 milliseconds; slower nodes give each handoff more time.

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
- Tonic consumes each response vector while encoding it, then yields an owned encoded frame. Hyper can retain up to its configured 512 kibibyte per-stream send buffer while the next frame is encoded. The new peak therefore has three charged owners instead of the old path's four: response vector, encoded frame, and transport buffer. At this stage, reduce only ByteStream's admission multiplier from four to three; ordinary file streams still retain their existing four-buffer model.
- Owned segment chunks now feed ByteStream, public artifact responses, and single-artifact backfill responses directly. The paired disk-backed benchmark measured a 1.419 times median speedup, and each stream's response reservation fell from four chunks to three. Spool-file responses still retain four at this point and move to owned positional reads in the later experiment below.
- Rustix now passes vector spare capacity directly to the positional read and safely extends the vector by the returned byte count. The paired low-level benchmark measured a 1.162 times median speedup over zero-initializing the same bounded allocation before the read.
- Replication upload bodies now consume the same owned chunks while preserving bandwidth reservations and forward-progress marks. The paired full body-adapter benchmark measured a 1.200 times median speedup over the copied asynchronous-reader path.
- Batched backfill spooling now writes each owned segment chunk directly into the temporary file while retaining exact-length validation. The paired reader-to-sink benchmark measured a 1.216 times median speedup over Tokio's generic copy path.
- Backfill spool responses now use the same owned positional-read stream and reserve three live chunks instead of four. The paired spool-reader benchmark measured a 1.233 times median speedup over Tokio's file stream adapter.
- Inline byte-stream consumers now yield slices of the existing reference-counted value. Pointer identity proves no byte allocation or copy; the synthetic materialization benchmark measured 372.308 times the copied path because the candidate moves no payload bytes.
- A paced benchmark staggers 32 concurrent streams across the fastest production node's 3-gigabit-per-second aggregate egress budget. Across three runs, the 95th-percentile Tokio blocking handoff was 31.083, 48.625, and 43.750 microseconds, with a median of 43.750 microseconds. That is 3.129 percent of a single chunk's 1.398-millisecond wire time; the complete cached positional read's median 95th percentile was 92.625 microseconds. Replacing Tokio would attack a small residual cost while introducing a second, Linux-specific runtime and file-resource model, so keep Tokio and optimize the remaining allocation work instead.
- Whole-artifact materialization still allocated a zero-filled result vector before the positional read overwrote every byte. On Unix, pass the vector's spare capacity to Rustix and let the operating system initialize it while preserving the exact allocation, admission bound, short-read error, and Windows fallback. Three paired 512-mebibyte runs measured 1.099118, 1.097661, and 1.103675 times speedups, a median of 1.099118 times.
- Accelerated requests previously built a complete owned authorization context even when authorization was disabled, then retained the full parsed artifact request through response admission and cloned the file handle, configured tenant, namespace, analytics key, route, and content type before transfer. Build the authorization context only when an engine exists, discard request-only fields after authorization and range resolution, move the remaining metadata and file into the transfer, borrow the configured tenant, and validate the file-owned content type inside the blocking closure. Pointer identity proves the namespace and analytics allocations move unchanged. Three paired setup runs measured 1.389168, 1.301090, and 1.386563 times speedups, a median of 1.386563 times.

## Next Segment

- Remove avoidable metric-label clones on the terminal accelerated response path.
- Audit manifest and handle cache key ownership for duplicate strings retained across indexes.
