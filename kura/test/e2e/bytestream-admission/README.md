# ByteStream read admission

The regression uses the suite's ShellSpec and Docker Compose lifecycle from
`spec/e2e/support.sh`. The Compose override starts one isolated Kura node and
reuses the Go load-client image from `grpc-upload-throughput/client`. No native
binary paths, Python launcher, credentials, or peers are needed.

From `kura/`:

```sh
shellspec spec/e2e/bytestream_admission_spec.sh
```

As with the other Compose specs, local runs build Kura from source. To use an
already built image, set `KURA_IMAGE` and `KURA_E2E_SKIP_BUILD=1`. The CI
`bytestream-admission` shard uses the workflow's shared prebuilt Kura image and
runs the same ShellSpec command; the spec builds the small Go client image.

The test waits for `/ready`, seeds one 1 MiB CAS blob, and starts 32 concurrent
readers through a fixed 64 KiB HTTP/2 stream window. Readers consume at 2 MiB/s,
and every attempt is paced to at least 500 ms, including failures. ShellSpec
requires all 128 reads to succeed, the client verifies every digest, and metrics
sampling must observe a queued ByteStream reader. Teardown removes the Compose
containers, volumes, network, and suite temporary directory.

Kura has an isolated 1 GiB memory limit and 512/544 MiB soft/hard watermarks.
This preserves the small reproducer's 32 MiB transient budget and 16 MiB response
pool while leaving room for real Linux allocator accounting. The load client
runs in a separate container, so its memory is excluded from Kura's cgroup.

## Sustained comparisons

Build separate baseline and candidate images, then run them sequentially on the
same host with identical settings. A baseline failure is expected when reproducing
burst shedding. For example:

```sh
KURA_IMAGE=kura:baseline KURA_E2E_SKIP_BUILD=1 \
KURA_E2E_BYTESTREAM_REQUESTS=4096 \
KURA_E2E_BYTESTREAM_OUTPUT_DIR=/tmp/kura-before \
  shellspec spec/e2e/bytestream_admission_spec.sh

KURA_IMAGE=kura:candidate KURA_E2E_SKIP_BUILD=1 \
KURA_E2E_BYTESTREAM_REQUESTS=4096 \
KURA_E2E_BYTESTREAM_OUTPUT_DIR=/tmp/kura-after \
  shellspec spec/e2e/bytestream_admission_spec.sh
```

Each output directory must be new. Optional captures retain idle, load, completion,
and 15 seconds of recovery metrics, the client and server logs, cumulative cgroup
CPU counters, and allocated data-directory size. Ordinary CI runs only sample
queue depth and do not keep artifacts or wait through a benchmark recovery period.

Compare observed allocator peaks and settled residency, pressure, live reservations,
queue depth, rejection counts, disk allocation, and server/client byte counters.
Compute CPU seconds from the `usage_usec` difference between `completed.cpu.stat`
and `idle.cpu.stat`, divided by one million, then normalize by completed payload
GiB from the client's `LOAD_RESULT_JSON`. Include recovery when finding memory
peaks: allocator gauges update more slowly than the metrics scrapes. Missing
series mean unavailable data, not measured zeros.

The client's `received_grpc_bytes` includes protobuf payloads, gRPC envelopes,
and encoded response headers/trailers; it excludes HTTP/2 and TCP framing. This
single-node fixture does not measure peer replication or ring-eviction retention.
Keep measured results and their limitations in the PR description.

The Rust regression independently holds 32 ordinary or 24 zstd response bodies
until every request reaches admission and explicitly asserts nonzero waiting.
Memory-controller tests cover managed memory floors, pending-byte bounds, FIFO
ordering, cancellation, deadlines, retry backoff, and HTTP fallback with stalled
ByteStream readers. Sustained overload can still exhaust the bounded queue or
its five-second deadline.
