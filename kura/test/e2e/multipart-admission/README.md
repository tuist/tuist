# Multipart admission burst benchmark

This standard-library Python harness compares real Kura binaries on localhost.
It fills the active session budget, stages a 64 KiB part in every session, sends
another wave of upload-start requests, and begins completing the first wave
200 ms later. Every accepted second-wave upload sends its part, completes, and
is downloaded and checked byte for byte. A separate existing artifact is read
throughout the run to check that waiting starts do not block ordinary reads.

Each run starts its own server with fresh temporary data, no peers, no inherited
credentials, and no remote telemetry endpoint. It terminates that process and
removes its data on exit. Python 3.9+, `ps`, and a locally executable Kura binary
are required. Run comparisons sequentially to avoid CPU and disk interference.

From `kura/`, preserve a baseline binary before building the change:

```sh
bazel build //:kura
cp bazel-bin/kura /tmp/kura-before
# Build the changed tree, then:
bazel build //:kura
python3 test/e2e/multipart-admission/benchmark.py /tmp/kura-before
python3 test/e2e/multipart-admission/benchmark.py bazel-bin/kura
```

The JSON output includes start outcomes, start latency (including rejected
requests), completed upload counts, verified downloads, ordinary-read probes,
RSS samples, and sampled allocator/transient-budget metrics. Any unexpected HTTP
status, failed part/completion, corrupt download, or failed ordinary read fails
the run. Expected 429s are counted rather than treated as harness failures.

| Option | Default | Meaning |
| --- | --- | --- |
| `--headroom-mib` | 128 | Hard minus soft watermark, and automatic session cap at normal pressure |
| `--fixed-limit` | unset | Override the automatic session cap |
| `--burst` | 128 | Number of second-wave starts in each round |
| `--rounds` | 3 | Independent upload waves within one process |
| `--hold-ms` | 200 | Delay before completing the first wave |
| `--payload-kib` | 64 | Real part size per upload |

The soft watermark is 512 MiB, with the hard watermark derived from
`--headroom-mib`. RocksDB has a 16 MiB read cache and a 16 MiB write-buffer pool.
This isolates the headroom variable; it does not emulate a complete production
pod profile or its cgroup ceiling.

## Measured comparison, September 9, 2026

The baseline is the first version of this PR, commit `94d7538feb`, which already
scales the session cap with memory but rejects immediately when it fills. The
changed binary adds FIFO bounded waiting and cancellation-safe blocking record writes. Full outputs are in [results.json](results.json).

| Scenario | Baseline accepted / attempted | With waiting | Start p99 before → after | Ordinary-read p99 before → after |
| --- | ---: | ---: | ---: | ---: |
| 128 occupied slots; burst 128; 3 rounds | 0 / 384 | 384 / 384 | 34.4 → 685.3 ms | 3.2 → 17.9 ms |
| 256 occupied slots; burst 256; 3 rounds | 0 / 768 | 768 / 768 | 50.4 → 929.1 ms | 4.5 → 12.4 ms |

Every accepted second-wave upload completed and passed download verification.
The low baseline start latency measures fast rejection; it does not represent a
successful cache write. The earlier racing-waiter implementation admitted 767/768 starts in one run,
with one deadline rejection: the heavier case is near the one-second boundary,
and these results do not promise zero shedding across machines or runs.

Additional controls against the changed binary:

- **1,024 occupied slots, burst 128:** 128/128 starts succeeded, with start p99
  474.7 ms; all 1,152 uploads completed, exercising the larger automatic cap.
- **128 occupied slots, burst 256:** 128 starts succeeded and 128 were refused
  by the bounded queue. The queue intentionally caps pending work even when
  some overflow requests might also have completed inside the deadline.
- **128 occupied slots held for 1,500 ms:** all 128 new starts were refused;
  start p99 was 1,017.7 ms, including client and network overhead. Ordinary
  read p99 remained 2.4 ms. The wait did not become indefinite.

The comparison is not memory-neutral: the changed binary performs many more
writes. Maximum sampled RSS was 158.1 → 227.5 MiB at 128 slots and
212.9 → 332.3 MiB at 256 slots. RSS includes mapped file pages and is not the
pressure controller's signal. Allocator and reservation metrics in the JSON
are snapshots, not precise allocation high-water marks, and can miss short
spikes. The stalled control's maximum sampled jemalloc resident size was
10.6 MiB; pending starts do not acquire payload reservations.

On macOS the process pressure sampler is unavailable, so these runs exercise
normal pressure only. Unit tests cover pressure reduction/recovery, critical
pressure with fixed overrides, cancellation, absolute timeout across wakeups,
queue overflow, FIFO ordering, head cancellation, wakeup isolation, off-runtime persistence cleanup, and completion/abort wakeups. The one-slot-per-MiB ratio remains
a concurrency heuristic, not proof of a worst-case per-session memory bound;
payload memory, staging disk, and descriptor budgets remain independently
required. Linux cgroup pressure and larger production payloads need separate
load validation.

The Docker ShellSpec at `spec/e2e/multipart_admission_spec.sh` also checks the
256-slot automatic cap, timeout response, metrics, and a queued HTTP start waking
when another upload completes. It passed against the isolated native server
(1 example, 0 failures). Run the same test body without Docker:

```sh
python3 test/e2e/multipart-admission/benchmark.py bazel-bin/kura \
  --headroom-mib 256 --shellspec "$(command -v shellspec)"
```

The container fixture uses a 2 GiB limit, a 1 GiB soft watermark, and a 1.25 GiB
hard watermark so its normal-pressure 256-slot assertion has ample headroom.
Docker execution remains unverified locally because the engine did not respond.
Metrics are matched by exact series and value, not substring. The native route
uses a fresh server owned and cleaned up by the harness.
