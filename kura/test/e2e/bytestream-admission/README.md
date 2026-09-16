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
`LOAD_READ_BYTES_PER_SECOND`, `LOAD_CONNECTIONS`, and `LOAD_MIN_REQUEST_MS` settings control transport
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

The deterministic reproducer holds 32 ordinary reads or 24 zstd reads, enough
to force waiting while fitting the new pending-work bound. The test explicitly
asserts that readers queued. Queued demand is limited to two batches of effective
serving bytes plus a separate bookkeeping cap; cancellation releases both.
Live response reservations and buffers are unchanged. Stalled readers can still
cause queue overflow or admission timeout, and HTTP retains its 250 ms wait and
bounded degraded fallback. Memory-controller tests cover these paths, the
published Air/Pro/Enterprise floors, and the unchanged retry-backoff scale.

For a floor-aware native load, pass
`--profile pro-floor --concurrency 512 --connections 4`. Four connections are
needed to exceed the server’s 128 concurrent streams per connection.
This publishes the 512 MiB floor, managed cache budgets, and Pro soft/hard
watermarks. The native host still supplies the runtime ceiling, so this exercises
the floor clamp but does not reproduce a 3 GiB cgroup. The Rust profile tests use
the exact managed runtime ceilings. Use enough requests to sustain contention
(e.g. `--requests 16384`) and apply identical settings to both builds.

The CI `bytestream-admission` shard builds the Go client and runs the 128-read
ShellSpec inside the prebuilt Linux image with an isolated 1 GiB cgroup. Its
`ci-small` profile raises soft/hard watermarks to 512/544 MiB, preserving the
32 MiB transient budget and 16 MiB response pool while allowing real Linux
anonymous memory accounting for the server and test processes. The spec
removes its temporary directory on exit; direct runner invocations deliberately
retain output for comparisons. Both admission runners share `native_server.py`
for the isolated environment, readiness, and process teardown.

Keep measured before/after results and their limitations in the pull request
description rather than committing dated benchmark tables here.
