---
{
  "title": "macOS sandbox restoration",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Resident pause, eviction costs, performance evidence and next steps for macOS sandboxes sharing CI capacity."
}
---
# macOS sandbox restoration

As of 28 October 2026, resident pause is the demonstrated fast path for macOS
sandboxes. Retain paused environments only within spare CI capacity, fully charging
their slots, vCPUs and configured RAM. When CI needs that capacity, save state and
wait for process exit before releasing the charge. Restoring after eviction remains
slower; the 1–2-second goal for that path is unresolved. Production admission is
not enabled by this prototype.

## Measurements

One Apple Silicon staging Mac (`Mac17,16`, 64 GiB, macOS 27.0 build 26A425) ran
Tart 2.41.1 with eight guest vCPUs and Xcode 26.6 build 17F113. The fixture builds a
small iOS framework and executes a command inside the original booted iPhone 16
simulator. First-command latency starts after capacity is granted; the following
build is additional. These small samples are acceptance evidence, not service SLOs.

| Resident guest / pause | Cycles | Median first command | Range |
| --- | ---: | ---: | ---: |
| 8 GiB / 1 second | 10 | 449 ms | 88–896 ms |
| 16 GiB / 1 second | 5 | 412 ms | 107–983 ms |
| 8 GiB / 30 seconds | 3 | 526 ms | 178–744 ms |

All 18 resident wakeups preserved memory and simulator state. This does not
establish performance under host pressure, concurrent CI, long idle times or at
24 GiB. Single post-resident eviction samples took 1.749 seconds to evict and
4.814 seconds to restore at 8 GiB, and 3.400 / 6.741 seconds at 16 GiB. Reclamation
is not instantaneous; protected CI headroom remains necessary.

Matched fully evicted restores used the same instrumented runtime and readiness
gate, with three cycles per shape:

| Guest | Snapshot, decimal GB | Median suspend | Median Apple restore | Median first command | Following build + simulator command |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 GiB | 3.56 | 1.704 s | 3.022 s | 3.812 s | 1.481 s |
| 16 GiB | 7.05 | 3.380 s | 5.813 s | 6.658 s | 1.843 s |
| 24 GiB | 9.66 | 4.871 s | 7.923 s | 8.790 s | 1.336 s |

The larger-shape penalty mostly occurs inside Apple's restore call. Larger guests
retain more file-backed memory and compress less anonymous memory for the same
workload. Those counters explain only part of snapshot growth: idle 16/24-GiB
guests had similar occupied categories but saved states differed by 1.34 GB.
Apple's saved-state format is opaque; file size is not a count of active guest pages.

A separate suspend → CI build → resume experiment demonstrated capacity reuse.
The compilation took 17.875 seconds in one baseline versus 18.089/19.896 seconds
in two intervening runs. The sandbox restored with memory intact. This is too
little evidence to establish CI performance equivalence or tail-latency impact.

## What helped, and what did not

- Waiting for a new control socket before the guest probe removed roughly one
  second in a matched 8-GiB comparison (5.008 → 3.929 seconds). Readiness still
  requires successful execution; socket existence alone is insufficient.
- Read-ahead and RAM-backed snapshots did not demonstrate a useful improvement.
  The RAM-disk median was 4.432 seconds, excluding copy work before the wake timer.
- A 4-GiB guest restored in about 2.43 seconds but subsequent builds took 38–96
  seconds with substantial swap. Shrinking shapes solely for restore speed is
  not a viable default on this evidence.
- Paired 24-GiB cache reclamation improved median first command only from 8.658
  to 8.407 seconds. Preparation grew from 0.200 to 2.925 seconds and the following
  build from 1.386 to 2.435 seconds. Do not purge caches on the normal suspend path.
- Three attempts to resume through the public API while Apple was restoring were
  rejected as invalid state transitions. Normal restoration then passed the
  memory/simulator checks. This tested an API boundary, not a lazy restore engine.
  The SDK 27.0 audit found no supported restore-time memory pager.

## Prior art and future work

[E2B's Linux runtime](https://github.com/e2b-dev/runtime/blob/main/docs/ARCHITECTURE.md)
uses demand-driven memory loading, and
[Modal describes prioritized background paging](https://modal.com/blog/mem-snapshots).
These suggest an architecture, not equivalent macOS/Xcode results.
[Anka's subsecond claim](https://veertu.com/technology/) is listed under Intel;
[Parallels' Apple Silicon macOS runtime](https://kb.parallels.com/en/128867) uses
Apple's framework. No supported demand-paged macOS alternative was verified in
this investigation. There was no direct Anka/Parallels benchmark; Anka on the Mac
mini requires an appropriate Build license or trial.

Next, connect the lifecycle to durable ownership, authenticated session routing,
atomic CI/sandbox reservations, same-host execution and restart reconciliation.
Serialize wake versus eviction, account for every Mac workload, and preserve
capacity charges on failed saves. Define snapshot retention, disk budgets and
host-loss/incompatible-state handling before rollout.

Start with one concurrent internal sandbox, without a permanently reserved warm
pool. Test real CI-driven eviction, longer pauses, 24-GiB guests, host pressure and
representative projects. Collect at least 30 runs per shape and track p50/p95 first
command/useful build, CI queue/build duration and eviction latency.

For future runtime qualification, require Apple Silicon at 8/16/24 GiB, the old
process gone, capacity reused, live memory preserved, and timing through useful
simulator/build work. Fast disk cloning, Intel claims and deferred page faults
alone do not satisfy the requirement.

## Evidence and reproduction

[Download the original report, raw JSONL/logs, SDK audit, scripts and patches](/engineering/macos-resume-2026-10-28.tar.gz).
The archive preserves the experiment tree from commit
`b4b3b7ac10c9d3f117d005031bc0775149fb3099`, including excluded exploratory runs,
runtime hashes and qualifications. Its historical commands predate the required
`--kubelet-home` safeguard; follow the current
[reproduction guide](https://github.com/tuist/tuist/blob/main/infra/tart-kubelet/macos-sandbox-resume.md)
for new runs. The archive's `README.md` contains the full research chronology;
raw run history is kept out of the runtime source tree.

The final memory matrix/reclamation experiment completed 24 full restores, all
preserving the live token; all 15 fixture restores passed the original simulator
and build checks. The staging host was cleaned up and both regular CI runners
returned Ready. No production fleet configuration changed.
