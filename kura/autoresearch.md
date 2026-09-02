# Autoresearch: Kura bounded-resource handle concurrency

## Objective

Increase Kura's concurrent artifact-read throughput by avoiding redundant persistent-file handle cache locks. Do not weaken hard memory, file descriptor, temporary disk, or background-work bounds.

## Metrics

- Primary: concurrent hot persistent-file handle cache throughput (lookups per second, higher is better)
- Secondary: exact least-recently-used eviction, file descriptor capacity, removal and trimming correctness, compile and lint status

## How to Run

`./autoresearch.sh`

## Files in Scope

- `src/reapi/service.rs`: Remote Execution ByteStream and batch response materialization
- `src/runtime.rs`: request in-flight accounting and shutdown notifications
- `src/app.rs`: shutdown-drain waiter and its notification contract
- `src/segment/reader.rs`: bounded asynchronous file reads
- `src/store.rs`: append-only segment persistence and metadata access
- `src/artifact/manifest.rs`: manifest ownership and retained allocations
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
- Every request arrival and completion currently calls `Notify::notify_waiters`, although the only consumer waits for the in-flight count to reach zero during shutdown. An arrival can never make that condition true, and steady-state completions need no shutdown wake-up before draining begins.
- Manifest-cache hits currently clone all owned manifest strings while holding the cache's global lock. The clone is required by the public store interface, but it does not need to serialize independent allocator work across requests.
- Every chunk read from a popular segment currently takes the persistent-file handle cache's asynchronous mutex, mutates recency, and clones the same open handle. Repeated hits to the already most-recent handle do not change eviction order.
- Kura resolves [`arc-swap` 1.9.1](https://docs.rs/arc-swap/1.9.1/arc_swap/). Its primary documentation describes atomic concurrent loads and stores, says a loaded guard keeps the value alive, and records that version 1.9 corrected previously weak memory orderings. The manifest now declares 1.9.1 as the minimum version so this fast path cannot resolve to an older implementation.
- [Rust's standard library](https://doc.rust-lang.org/std/sync/struct.Arc.html) guarantees that an atomically reference-counted clone shares the same allocation and keeps the value alive until the final owner is dropped. The fast path therefore cannot expose a freed file object after a concurrent replacement or clear.
- The fast-path guard exists only long enough to compare the immutable key and clone the file owner. It is explicitly dropped before the fallback awaits the cache mutex, so there is no lock-order cycle and no guard is retained across a suspension point.
- Removal and trimming clear the fast path while holding the cache mutex that owns membership. A hot entry is published only when it remains in the bounded cache, including the zero-capacity case, so the front never owns an additional file descriptor outside the configured cache.
- A request that cloned a handle before concurrent removal may finish reading it, which matches the previous mutex path. The [Linux manual](https://man7.org/linux/man-pages/man2/unlink.2.html) specifies that unlinking the last pathname postpones file-content removal until open file descriptors are closed.
- [Tokio's mutex documentation](https://docs.rs/tokio/latest/tokio/sync/struct.Mutex.html) explains that its asynchronous mutex is more expensive than a blocking data mutex and is intended when a guard must span a suspension point. Kura still uses it for exact cache membership and recency mutations, but the atomic front is a better fit for the immutable, read-mostly hottest entry because no guard spans a suspension point.

## What's Been Tried

- Baseline repeated hits to one open persistent-file handle sustained 2,712,133.322 lookups per second across eight Tokio workers. The benchmark fixture initially proved the storage-root guard rejects paths outside configured roots; moving the synthetic handle under the configured data directory preserved that guard and measured the intended cache path.
- Added one atomic, single-entry front for the already most-recent persistent-file handle. Initial hot-key runs sustained 31,094,326.739 and 36,970,712.264 lookups per second, at least 11.464 times the mutex-only baseline. Exact recency, capacity-two eviction, trimming, removal, and zero-capacity behavior are covered by focused tests.
- An adversarial paired benchmark caught the first design republishing the front on every alternating-key miss: two cached keys fell to 0.331165 times the mutex-only path. Added a bounded 64-hit promotion threshold so new handles seed the front but cached replacements must demonstrate sustained demand. Two alternating-key runs then improved to 1.587395 and 1.542646 times the mutex-only path, while the confirmed hot-key run reached 40,070,961.666 lookups per second, 14.775 times the original baseline.
- Baseline same-hot-artifact manifest-cache hits sustained 1,423,779.733 lookups per second across eight concurrent workers while cloning all manifest strings under the global lock.
- Retained cached manifests behind one shared allocation, cloned only that reference under the lock, and moved the required owned-string clone after unlock. Paired same-process runs measured 1.126040 and 1.140262 times speedups while pointer identity proved allocation reuse and retained-byte accounting includes the two reference counters.
- Baseline request accounting, with every arrival and completion notifying the shutdown waiter, sustained 279,259.648 requests per second across eight concurrent workers.
- Removed arrival notifications and limited completion notifications to the draining state. Two candidate runs sustained 349,744.257 and 360,105.299 requests per second, improving the confirmed result by 28.954 percent while focused in-flight and shutdown-drain checks passed.
- In-flight guards cloned the complete `Metrics` value even though their drop path updates only three gauges. Replaced that broad clone, which touched every shared metric family's reference count, with one shared in-flight metrics handle. Two candidate runs sustained 3,929,250.582 and 4,643,989.770 requests per second. The confirmed result is 12.896 times the notification-only result and 16.629 times the original baseline, with identical gauge updates.
- Total and public web request counts previously updated two adjacent sequentially consistent atomics on arrival and completion. Packed the two exact 32-bit counts into one 64-bit atomic, halving counter updates for public web traffic while retaining separate gauges. Two candidate runs sustained 5,222,378.062 and 7,155,864.460 requests per second; even the lower run is 12.455 percent above the previous best confirmed result.
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
- Hypertext Transfer Protocol metric recording took an owned route from the ordinary middleware but cloned it for every request's label lookup. Accelerated responses first allocated their static route and then cloned that allocation. Store metric routes as borrowed-or-owned text, move dynamic routes into the primary label lookup, and borrow accelerated route templates. Internal backfill and server-error routes still clone only when a second metric family needs the same dynamic label. Three paired steady-state runs measured 2.314626, 2.321335, and 2.286898 times speedups, a median of 2.314626 times, while keeping identical route and status label values.
- The manifest, existence, and persistent-file handle caches duplicated every key between their hash lookup and least-recently-used ordering tree. Worse, every cache hit allocated another string when it refreshed recency. Use one immutable reference-counted string allocation as both indexes' key and clone only the reference on a touch. Existence entries now retain one key allocation instead of two; manifest entries retain the identifier inside the manifest plus one shared index key instead of three copies. Three paired cache-hit runs measured 1.113830, 1.131098, and 1.119967 times speedups, a median of 1.119967 times.
- Final validation after the Tokio dispatch measurement and four kept optimizations: production compilation, formatting, and Clippy passed; the complete unit suite passed 821 tests with 0 failures and 13 intentionally ignored performance benchmarks.
- Final validation after the request-accounting synchronization pass: production compilation, formatting, and Clippy passed; the complete unit suite passed 822 tests with 0 failures and 14 intentionally ignored performance benchmarks.
- Final validation after shared manifest retention and the first hot-handle candidate: production compilation, formatting, and Clippy passed; the complete unit suite passed 825 tests with 0 failures and 16 intentionally ignored performance benchmarks.

## Next Segment

- Profile the next most-contended serving lock under a production-shaped mix of artifact sizes and keys.
- Keep both hot-key and alternating-key benchmarks when changing handle-cache publication behavior.
