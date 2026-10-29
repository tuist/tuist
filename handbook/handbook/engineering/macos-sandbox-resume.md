---
{
  "title": "macOS sandbox restoration",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Resident pause, eviction costs, performance evidence and next steps for macOS sandboxes sharing CI capacity."
}
---
# macOS sandbox restoration

As of 29 October 2026, resident pause is the demonstrated fast path for macOS
sandboxes. Retain paused environments only within spare CI capacity, fully charging
their slots, vCPUs and configured RAM. When CI needs that capacity, save state and
wait for process exit before releasing the charge. Restoring after eviction remains
slower; the 1–2-second goal for that path is unresolved. The integrated account API
has passed staging acceptance; production admission remains disabled by default.

## Integrated staging acceptance, 29 October 2026

The authenticated staging account API exercised the real host service and Apple
VMs on `ber1-runner-b01`, with eight vCPUs per guest. Each environment held a
random nonce only in a detached Node.js process's heap. Five resident cycles and
one eviction/restore per shape preserved that nonce, and API deletion succeeded.
A cold boot cannot satisfy this proof. This workload does not include an Xcode
build or simulator; those were exercised separately in the prototype below.

| RAM | Resident cycles | Median resume through first command | Range | Evicted restore through first command, one sample | Prior admission retry wait |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8 GiB | 5 | 534 ms | 484–988 ms | 12.270 s | 95.207 s |
| 16 GiB | 5 | 788 ms | 689–1,154 ms | 6.907 s | 0 s |
| 24 GiB | 5 | 520 ms | 465–931 ms | 10.400 s | 0 s |

Timers cover the accepted resume HTTP request through the first successful heap
proof command, including host reservation, runtime readiness and API overhead.
Earlier HTTP 503 retries are recorded separately. These are not isolated Apple
restore timings or a matched snapshot-size comparison; one evicted sample per
shape cannot establish scaling, p95/p99 or a service SLO.

An abrupt kubelet restart retained the same resident execution Pod UID and heap;
resume through the first command took 804 ms. A separate checkpoint recovery
after restart also preserved the heap. During the real CI-priority test, one
[CI job](https://github.com/tuist/tuist/actions/runs/40881940662) ran while a
[second job](https://github.com/tuist/tuist/actions/runs/40881945502) queued and
revoked native admission. A 120-second guest command kept its reservation until
completion at 13:28:25.178 UTC; it was released by 13:28:27. The queued job started
at 13:31:05 after warm-runner turnover and boot. Both CI jobs passed. The evicted
environment subsequently restored its original heap through the updated server
in 11.467 seconds. All test environments, account flags and synthetic accounts
were removed, and no native execution reservations remained.
A [fresh CI smoke](https://github.com/tuist/tuist/actions/runs/40884720819) also
passed after cleanup and the final server rollout.

Live validation exposed and fixed three additional boundary failures: omitted
`resident: false` reports left stale server charges; a built-in guest readiness
command succeeded before the shared bridge was executable; and a host capacity
refusal after server admission incorrectly marked a saved environment failed.
Reports now send the boolean explicitly, readiness pings the actual bridge, and
the explicit capacity refusal returns HTTP 503 with a retryable paused checkpoint.
Joined cleanup errors still fail closed. The last case was reproduced after the
fix: admission retries retained the paused checkpoint and eventually restored it.

The final measurement stack used server `sha-86c2f762e331`, provider/kubelet image
`5656d80d`, controller `sha-af65a38d704c` and guest image
`macos-26-6-6abd89c8`. Component integration branches preserved other staging
rehearsals; this was not a deployment of one complete PR-head image set. Latest
main's account-quota integration was qualified locally. See the
[operation guide](https://github.com/tuist/tuist/blob/f686a49968d351b8fdafb59cf0ed7f65aa2c16dd/infra/tart-kubelet/macos-sandboxes.md)
for admission, recovery and rollback boundaries.

## Prototype measurements, 28 October 2026

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

The integrated implementation now provides durable ownership, authenticated
session routing, atomic reservations, serialized wake/eviction and restart
reconciliation. Failed saves retain their charge. Snapshots remain coupled to the
same host and runtime; host-loss recovery and cross-host migration are not provided.

Start with one concurrent internal sandbox, without a permanently reserved warm
pool. Extend the passing CI-eviction and 24-GiB acceptance checks to longer pauses,
host pressure and representative projects. Collect at least 30 runs per shape and track p50/p95 first
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
