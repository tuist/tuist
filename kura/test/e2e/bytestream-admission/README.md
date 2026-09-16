# ByteStream read admission

This local-only harness seeds one 1 MiB CAS blob, then downloads it with 32
concurrent readers. Each reader consumes at 2 MiB/s through a fixed 64 KiB
HTTP/2 stream window. Attempts are paced to at least 500 ms, including failures,
so rejected requests do not turn into an uncontrolled retry loop. Every completed
read must match the stored digest. No credentials, peers, or production endpoints
are required.

Build the server and the existing Go load client from `kura/`:

```sh
bazel build //:kura
(cd test/e2e/grpc-upload-throughput/client && GOWORK=off go build -o /tmp/kura-read-client .)
KURA_BYTESTREAM_BINARY="$PWD/bazel-bin/kura" \
KURA_BYTESTREAM_CLIENT=/tmp/kura-read-client \
  shellspec spec/e2e/bytestream_admission_spec.sh
```

The ShellSpec runs 128 requests. For a sustained comparison, copy the merge-base
binary before building the candidate, then run the same harness sequentially
against each binary with fresh output directories:

```sh
python3 test/e2e/bytestream-admission/run.py \
  /tmp/kura-baseline /tmp/kura-read-client /tmp/kura-reads-before --requests 4096
python3 test/e2e/bytestream-admission/run.py \
  "$PWD/bazel-bin/kura" /tmp/kura-read-client /tmp/kura-reads-after --requests 4096
python3 test/e2e/bytestream-admission/summarize.py \
  /tmp/kura-reads-before /tmp/kura-reads-after
```

The runner waits for `/ready`, samples `/metrics` through idle, load, and a
15-second recovery period, and preserves the samples, server/client logs, CPU
time from `ps`, and allocated data-directory size from `du`. A nonzero read exit
means at least one read failed; baseline failures are expected when reproducing
the admission bug. Compare memory peaks and settled allocator residency, pressure,
reservations, admission outcomes, CPU per completed byte, storage growth, and
bytes served per successful read. macOS does not expose Linux cgroup or anonymous
RSS metrics; allocator accounting remains available. This single-node test does
not exercise peer replication or identify a production build's concurrency.
The summarizer includes recovery in the reported peak because allocator samples
can lag the final response, and measures process CPU from the last idle sample
through the first recovery sample. Missing counter series are omitted, not
reported as measured zeros.

The harness sets 64 MiB / 96 MiB soft and hard memory watermarks to reproduce
pool contention at a small scale. These are application settings, not an OS
memory limit. The host's detected runtime limit remains unchanged.

The load client's optional `LOAD_STREAM_WINDOW_BYTES`,
`LOAD_READ_BYTES_PER_SECOND`, and `LOAD_MIN_REQUEST_MS` settings control transport
buffering, reader pacing, and the minimum interval between attempts. Its
`received_grpc_bytes` result includes protobuf payloads, gRPC envelopes, and
encoded response headers/trailers; it excludes HTTP/2 and TCP framing. Compare
it per successful read alongside the server's artifact byte counter, rather
than treating more successful downloads as egress amplification.

The Rust regression test `bytestream_read_burst_waits_without_shedding` also
holds admitted response bodies until every request has reached admission. It
checks ordinary and zstd reads independently of network timing.

Admission remains deliberately bounded. A sustained offered load beyond the
node's serving capacity can still exhaust the queue or its five-second deadline;
the regression covers avoidable burst rejection while the node can make progress.

The deterministic reproducer exposed the old queue limit: with these limits,
16 ordinary reads could hold byte permits and only eight more could wait, so a
32-read burst rejected eight requests before any reader was released. Waiting
requests do not hold response buffers. The queue now has its own bounded sizing
rule, one slot per MiB of floor-derived transient capacity, capped at 1,024.
This profile gets 32 waiting slots while every admitted read retains its original
byte reservation and buffer size. FIFO order, cancellation cleanup, and the
five-second admission deadline remain in force.

## Local validation — 2026-09-16

Baseline: `5efbfee44007dffec97f994cc552e38611d9b850` (the worktree's
merge base with `main`). Both binaries ran on the same Apple silicon macOS host
with the configuration and workload above, after compilation finished. Pair A
ran baseline then fix; pair B reversed the order. Each run used a fresh data
directory, 4,096 requests, and 15 seconds of recovery sampling.

| Measurement | Baseline A | Fix A | Baseline B | Fix B |
| --- | ---: | ---: | ---: | ---: |
| Successful reads / 4,096 | 3256 | 4096 | 3423 | 4096 |
| RESOURCE_EXHAUSTED | 840 | 0 | 673 | 0 |
| CPU seconds / completed GiB | 2.233 | 2.520 | 2.079 | 1.930 |
| Allocator allocated peak / settled (MiB) | 28.79 / 4.99 | 24.62 / 4.08 | 28.90 / 4.47 | 27.84 / 4.05 |
| Allocator resident peak / settled (MiB) | 191.39 / 90.58 | 149.53 / 78.58 | 194.31 / 108.95 | 182.77 / 98.39 |
| Response reservation peak / settled (MiB) | 17.25 / 0.00 | 17.25 / 0.00 | 17.25 / 0.00 | 17.25 / 0.00 |
| Waiters peak / settled | 8 / 0 | 16 / 0 | 8 / 0 | 16 / 0 |
| Allocated data directory (KiB) | 2316 | 2320 | 2316 | 2316 |
| Received gRPC bytes / completed payload byte | 1.000023 | 1.000022 | 1.000022 | 1.000021 |
| Wall time (seconds) | 73.46 | 97.25 | 67.54 | 70.89 |
| p95 attempt duration (ms) | 895 | 1114 | 692 | 924 |

Every successful read matched its digest. Both fixed runs had zero admission
rejections or timeouts. Both versions stayed at the normal pressure gauge and
returned all stream reservations and waiters to zero. macOS does not supply the
Linux pressure/RSS observations, so this is not validation of cgroup enforcement.
The fixed runs' allocator peaks and recovery residency were lower than their
paired baselines.

CPU did not show a repeatable direction: the fix was about 13% higher per GiB in
pair A and 7% lower in pair B. Do not treat this small local comparison as proof
of a CPU improvement or a precise fleet performance estimate. The final change
preserves the original streaming buffers and encoding; smaller-buffer prototypes
were discarded after their initial comparisons showed higher CPU per completed
byte. Queueing also changes the latency tradeoff: failed baseline attempts can
return immediately, whereas accepted requests may wait. The percentile above
includes failed attempts and is not a comparison of successful-read latency alone.

The artifact segment occupied exactly 1,056,768 bytes in both pair-A runs.
The additional 4 KiB of allocated directory space in fix A was a RocksDB WAL
crossing one filesystem-block boundary (3,873 to 4,198 logical bytes), not another
artifact copy. Each read phase's warmup wrote 4,096 artifact bytes in both builds.
Received gRPC bytes were effectively unchanged per completed payload byte;
HTTP/2/TCP framing and peer replication are outside this isolated test.

Validation also passed:

- The new deterministic burst test failed on the original runtime with eight
  rejected ordinary reads out of 32, and passed with the fix for ordinary and
  zstd reads.
- Bazel server/test-binary builds and Clippy across `//...`.
- 20 ByteStream tests and 61 memory tests, including FIFO, queue overflow,
  cancellation, timeout, and transport-lifetime accounting.
- The response-stream, splice, replicated-recipe, and HTTP fallback test filters.
- The native ShellSpec regression: 128 successful, digest-verified reads.
- Go build/vet, Rust/Go formatting, Python syntax, ShellSpec shell syntax, dashboard
  JSON parsing, and `git diff --check`.

The ignored Rust tests were existing opt-in benchmarks; the full E2E suite was
not run. Production rollout and sustained overload beyond the five-second
admission deadline were not exercised. The existing deadline and overflow errors
remain necessary bounds.
