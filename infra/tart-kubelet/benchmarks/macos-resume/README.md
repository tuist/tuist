# Staging resume measurements — 2026-10-27–28

These are small acceptance experiments, not p95 estimates or a service SLO.
See [the experiment guide](../../macos-sandbox-resume.md) for lifecycle,
reservation and rollout requirements.

## Setup

- Staging rack host `ber1-runner-b01`, model `Mac17,16`, 64 GiB RAM,
  macOS 27.0, Tart 2.41.1. Its two idle runners were retired through the normal
  cordon/drain path before the experiment. No active CI job was interrupted.
- Eight vCPUs per sandbox; 8, 16 and 24 GiB tested separately. Headless,
  suspendable Tart configuration, cached root disk, local APFS saved state.
- Isolated APFS clones of the existing Xcode 26.6 runner image (17F113), with
  the CI dispatch LaunchAgent removed inside a private preparation clone.
  No production service or runner credential was used.
- The existing `cli/Tests/Fixtures/Frameworks` iOS framework was built with
  `xcodebuild`. An iPhone 16 simulator was booted before the initial build.
  Every post-resume build also executed a command inside that same simulator.
- Every cycle required the same in-memory challenge-response token from a
  guest process that was never configured to restart at boot.

`make-fixture-prepare.sh` emits the guest setup script, embedding that existing
fixture. `build-fixture.sh` is the repeated Xcode/simulator command.

## Immediate restores

| Guest memory | Cycles | First command, range | Median | Median suspension | Median incremental build |
| --- | --- | --- | --- | --- | --- |
| 8 GiB | 3 | 4.898–5.051 s | 4.985 s | 1.711 s | 1.205 s |
| 16 GiB | 3 | 6.920–7.684 s | 7.604 s | 3.319 s | 1.520 s |
| 24 GiB | 3 | 9.072–9.803 s | 9.683 s | 4.780 s | 1.327 s |

Raw samples: [8 GiB](immediate-8g.jsonl), [16 GiB](immediate-16384.jsonl),
[24 GiB](immediate-24576.jsonl). All nine cycles restored memory and passed
the build and simulator checks. The first 8-GiB post-resume build took 6.937 s;
the following two took 1.205 s and 1.060 s. Report that variability rather than
using the median alone as time to useful work.

The 16-GiB runs consumed saved state at 5.742–5.902 s; the 24-GiB runs at
7.932–8.032 s. Tart removes the state file after Apple's restore call returns,
before resuming the VM. These observations include launcher/setup/polling time,
but show that restoration is a substantial part of wakeup latency. The 8-GiB
immediate series preceded that instrumentation. Those three series also exclude
the final host-availability check from their timer; subsequent measurements
include it. This check was on an already reserved host, not a CI queue wait.

Snapshots were approximately 3.8 GB, 6.8–7.0 GB and 9.5–9.7 GB respectively,
despite running the same small fixture. This supports testing smaller guest
shapes first; it does not prove 8 GiB is sufficient for larger Xcode projects.

## Intervening CI workload

`prepare-ci.sh` pins public XcodeProj revision
`5d313c99fbb3871a6faeeca97ed13ee6f832ad06`; `build-ci.sh` compiles the package
and test bundle with eight jobs. Each run gets a fresh 24-GiB VM. Dependency
resolution is preparation time, separate from the build timer. `between-ci.sh`
is the host hook that waits for this guest to finish and exit before allowing
the sandbox to resume. Run a baseline with `--mode workload` before the series.

An initial attempt using `swift test` returned a failure, so it is excluded
from the successful build measurements. This experiment validates CI build
capacity reuse, not the upstream project's test suite.

The [baseline CI build](baseline-ci.jsonl) took **17.875 s**. The two
[intervening CI builds](intervening-ci.jsonl), each run while the sandbox was
saved to disk, took **18.089 s** and **19.896 s**. Each disposable CI VM exited
before the sandbox resumed. With one baseline and two comparisons, this does
not establish a CI performance regression or equivalence.

The [8-GiB post-CI resumes](after-ci-8g.jsonl) reached the first command in
**4.607 s** and **4.851 s**, then completed the incremental build and simulator
check in **1.871 s** and **2.100 s**. Both preserved the in-memory token.
State consumption was observed at **3.387 s** and **3.287 s**, leaving about
1.2–1.6 seconds for resumption and guest-command readiness. Commands issued
against the already-running guest just before suspension took **17 ms** and
**652 ms**. Those are warm execution measurements, not a production worker SLA.

All eleven measured suspend/resume cycles passed. These two CI compilations
do not prove the host evicted every snapshot page; longer pauses and workloads
with greater memory pressure are still needed.

After collecting the samples, the private experiment store was removed, the
staging node was uncordoned, and both ordinary warm runner VMs returned to
Running. Production infrastructure and sandbox admission were not changed.

## Interpretation and remaining gates

Removing the five-second launcher delay prevents an artificial floor; it does
not eliminate the cost of Apple's restore. In these immediate runs, 16 and
24 GiB already exceeded the initial five-second target. Small guests and a
short, fully charged warm grace period are worth pursuing. Do not promise
subsecond cold resume or availability while CI owns the required host capacity.

Before production integration, collect at least 30 runs per shape after
representative CI workloads and longer idle intervals, with host memory and
disk telemetry. This small fixture and one host do not establish application
memory requirements, cache eviction, tail latency, CI queue impact or the effect
of concurrent builds. The shadow evaluator still needs a live observation
adapter and atomic admission; it currently changes no fleet allocations.

Code validation: Tart lifecycle, benchmark and shadow-policy race tests and
`go vet` passed. The required Pod-agent suite passed except
`TestCustomAPFSRealColdWarmIsolation`. Its write-back verification failure
reproduced on an untouched `HEAD` copy as well (roughly 50 MB verified versus
17–19 GB reported by the mounted filesystem); the rest of that suite passed
when the failing test was isolated. No APFS cache code was changed.

## Follow-up: isolating the two-second target

The target is first successful guest command within two seconds after capacity
is granted, preserving the existing processes and booted simulator. The follow-up
used the same reserved staging Mac, image, eight vCPUs and fixture. The source
and commands for reproducing it are in the experiment guide. These immediate,
same-host measurements do not model a cold filesystem cache or establish p95.

The profiling patch targets Tart 2.41.1, upstream commit
`543453404cd1b15c1338b6b70e162d000c8ba5e2`. The release-built, locally signed
instrumented executable had SHA-256
`230c379d40d5394c53f86877ee576f2bba1e1069fba8c600f90a534e43437367`.
It timestamps Apple's restore and resume calls directly. The installed Tart
[control](installed-control-8g.jsonl) took 5.147 s for one resume. The instrumented
control below is consistent with it; one installed control is not a statistical
instrumentation-overhead estimate. All clean eight-GiB series ran after the
profiler finished building, with no other VM running.

| Configuration | Cycles | First command, range | Median | Median Apple restore | Median Apple resume |
| --- | --- | --- | --- | --- | --- |
| [8 GiB control](native-8g.jsonl) | 3 | 4.935–5.094 s | 5.008 s | 3.090 s | 0.570 s |
| [8 GiB, readiness gate](native-gate-8g.jsonl) | 3 | 3.929–4.128 s | 3.929 s | 3.202 s | 0.547 s |
| [8 GiB, gate + read-ahead](native-read-ahead-8g.jsonl) | 3 | 3.810–4.050 s | 3.993 s | 3.037 s | 0.511 s |
| [8 GiB, gate + guest cache purge](native-purge-8g.jsonl) | 3 | 3.640–3.852 s | 3.738 s | 2.864 s | 0.561 s |

All twelve cycles preserved the live memory token, completed the framework
build and executed a command in the original simulator. The gate waits for the
new control-socket generation before attempting a guest command, avoiding an
early gRPC reconnect/backoff cycle. It still requires the command to succeed.
This removed roughly one second here. It is opt-in in the benchmark; fleet
runner readiness is unchanged.

The remaining time is predominantly inside Apple's restore call. For the gated
control, runtime setup took 37–41 ms, state-file removal 17–18 ms, and control
setup under 2 ms. Its snapshots were 3.76–3.89 GB (decimal). The event CPU and
fault counters cover Tart, not Apple's separate virtualization process; low
parent CPU is not evidence that the restore is disk-bound.

Read-ahead cost 106–120 ms, included in first-command time, and did not produce
a meaningful improvement in this small comparison. Guest cache purge reduced
the snapshot to 3.29–3.62 GB, but added 2.964–11.794 s before suspension. The
post-resume build took 2.280–3.533 s, versus 1.154–3.974 s with the readiness gate
alone. Moving work into suspension and evicting useful guest caches is not a
general solution to the latency target.

An exploratory [6-GiB series](gate-6g.jsonl) completed three resumes in
3.348–3.487 s (median 3.405 s), preserving memory and simulator state. It used the
installed runtime and an earlier gate that dialled the host socket before the
guest command, so it has no Apple API timings and is not a matched gate-version
comparison. Guest swap was 219–292 MiB; post-resume builds took 11.483–49.272 s.
That association warrants investigating pressure; it does not prove memory size
alone caused every build delay. A smaller snapshot cannot be judged independently
of time to useful work.

Initial development builds accidentally retained Tart's `SNAPSHOT` version.
Tart embeds its version in a console device, so this changed guest-agent discovery
and configuration compatibility; those boot/restore failures are excluded.
The patch explicitly retains `2.41.1`. Early exploratory eight-GiB runs overlapped
the compiler build and are also excluded from the clean table. The initial
four-GiB attempt failed simulator execution with an x86_64/arm64 dyld mismatch;
the fixture now explicitly uses `simctl spawn --arch=arm64`, and all clean series
above use that corrected command. That original failure is not evidence of OOM.

With the corrected fixture, [4 GiB](native-gate-4g.jsonl) completed two resumes
in 2.431 and 2.430 s. Apple's restore took 1.583–1.598 s and resume 0.497–0.507 s;
snapshots were 1.74–1.78 GB. Both preserved the memory token and simulator, but
post-resume builds took **38.157 and 96.331 s**, with about 1,060–1,114 MiB of guest
swap reported before suspension. See the extracted
[guest memory diagnostics](guest-memory-observations.txt). The second build's
final seconds overlapped creation of the unformatted RAM device for the next
experiment; neither restore overlapped it. Treat these as exploratory results,
not a precise memory-size/build-time causal estimate. Four GiB still missed the
two-second target and is not a viable default on this evidence.

### RAM-backed snapshot diagnostic

The [RAM-disk series](native-ram-8g.jsonl) used an eight-GiB guest and the same
readiness gate, moving the saved state to a verified six-GiB HFS+ RAM disk after
each suspension. The original pathname became a symlink to that copy. The VM
process had exited; this was a snapshot in RAM, not a resident paused VM. Three
restores completed in **4.316–4.445 s, median 4.432 s**, preserving the memory token
and simulator. Apple's restore call took 3.627–3.666 s and resume 0.528–0.535 s.
Snapshot copies took 330–434 ms, reported as `between_ms`; they were preparation
outside the wakeup timer. Post-resume builds took 1.377–4.018 s.

RAM storage did not improve the result. This comparison also changes filesystem
and path indirection, and the immediate SSD control may already benefit from
cached pages; it does not prove every storage path is irrelevant. It does rule
out claiming that this straightforward RAM-backed snapshot experiment meets the
target. A production RAM snapshot would consume CI memory headroom throughout
its retention, even though it frees the VM slot.

### Decision and next experiments

Keep the two-second goal, but do not present the current disk-restoration path
as meeting it. Retain the command-readiness improvement for sandbox integration;
do not default to four-GiB guests or guest cache purge on this evidence. Measure
larger projects and longer pauses before selecting a supported memory shape.

The next runtime comparison should run the same live-process/simulator and
post-resume-build checks on Anka on this host, measuring both fully released
capacity and any resident paused mode separately. [Anka describes instant
startup](https://docs.veertu.com/anka/), but gives no directly comparable number
there. Its [licensing documentation](https://docs.veertu.com/anka/licensing/)
limits the free Develop edition to laptops; the staging Mac mini needs a Build
license or trial. No license was supplied and no Anka benchmark was run. Its
marketing wording does not establish a one-second full-state restore for this
workload.

If a one-to-two-second path is required independently of a different runtime,
prototype **resident paused VMs** as a distinct tier. Apple's
[restore API](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/restoremachinestatefrom(url:completionhandler:))
returns a paused VM, so pre-restoring while spare capacity exists can move that
work before a turn arrives; an already resident VM can also be paused without
serializing it. This is a proposed latency experiment, not a measured result.
Such VMs retain their RAM and VM slots, must count fully against CI headroom,
and must yield to CI. A disk-suspended environment still needs the slower restore
after eviction. Keeping an eight-GiB guest resident must not be advertised as
reclaiming eight GiB or satisfying the fully evicted restoration target.

Profile the virtualization service itself before attributing the remaining cost
to decompression, memory allocation or device restoration. The current events
identify the slow API boundary but do not distinguish those internal causes.

The profiling follow-up passed `go test -race` for the benchmark, Tart lifecycle
and shadow admission packages, plus `go vet` for the benchmark, shell syntax
checks and `git diff --check`. The instrumented Swift release build also passed
and ran the successful live trials above. Profile parsing rejects missing,
duplicate, out-of-order or mixed-process events; readiness tests reject an old
socket generation and require an actual successful guest command.

After the follow-up, all experiment drivers and VMs had exited, the reservation
marker and private store/build were removed, and the RAM disk was detached.
The staging node was uncordoned and both ordinary warm runners returned to
`1/1 Running`. No profiling binary replaced the fleet's installed Tart, and
sandbox admission remains shadow-only.

## Resident pause and early resume — 2026-10-28

This follow-up tests retaining a paused VM in its existing process, then separately
tests whether the public API permits execution while a disk restore is still in
progress. It uses the same staging host, macOS 27.0 (26A425), Xcode 26.6 fixture,
eight vCPUs and pinned Tart 2.41.1 source. The two normal runners were retired
through operator drain after cordoning the host; their heartbeats were polling.
The experimental binary stayed in a private directory. Its SHA-256 was
`6e87bc391f36f658a426c8210bb93c89d2bc191e0566005517c382345a2b278f`.

The resident build adds public `VZVirtualMachine.pause()` and `resume()` calls,
with correlated host-file requests and five-millisecond polling. Each wake timer
includes request transport, Apple's resume call and a successful guest command.
Each cycle verifies the original in-memory token, the unchanged Tart PID, absence
of a saved-state file, a framework build and execution in the original simulator.
The reservation hook is rechecked but the VM's slot and configured memory remain
charged throughout the pause. These are short runs without concurrent CI or
deliberate host memory pressure, not production p95 measurements.

| Resident guest | Cycles | Pause interval | First command, range | Median | Post-resume build, range |
| --- | --- | --- | --- | --- | --- |
| [8 GiB](resident-8g.jsonl) | 10 | 1 s | 0.088–0.896 s | 0.449 s | 0.823–1.575 s |
| [16 GiB](resident-16g.jsonl) | 5 | 1 s | 0.107–0.983 s | 0.412 s | 0.919–1.505 s |
| [8 GiB, longer idle](resident-idle-8g.jsonl) | 3 | 30 s | 0.178–0.744 s | 0.526 s | 0.787–1.577 s |

Apple's resident resume call itself took 0.875–14.948 ms for eight GiB and
0.886–14.079 ms for sixteen GiB. Guest-command readiness accounts for most of
the end-to-end time. Resident pause took 4.755–16.139 ms and 8.524–15.403 ms
respectively at the API boundary. The observed fast path meets the one-to-two
second target without shrinking the guest or clearing its caches.

Each series ends by pausing, saving state and terminating its Tart process,
then restoring into a new process and checking the same guest memory and
simulator. The eight-GiB eviction took **1.749 s**, of which 1.607 s was saving;
the subsequent disk restore reached the first command in **4.814 s**. For sixteen
GiB, eviction took **3.400 s**, of which 3.244 s was saving; disk restoration took
**6.741 s**. These single-cycle results show the cost of yielding a resident VM,
not a CI job startup SLA. No CI job was dispatched between these checkpoints.
After the longer-idle series, eight-GiB eviction took **1.779 s** and the next
disk restore **4.684 s**. All eighteen resident cycles and all three subsequent
disk restores preserved the original guest memory and simulator.

### Demand-driven restoration: tested boundary

The installed public macOS 27 SDK exposes file-based restore and a separate
resume operation. The [API audit](public-api-audit.txt) records the SDK version,
header checksum, relevant declarations and a search for pager/restore options.
No public caller-provided pager or lazy-restore option was found. This is an
audit of the exposed interface, not a claim about Apple's internal paging.

The opt-in `EarlyResumeProbe.swift` starts a real restore, yields for ten
milliseconds, and attempts to resume before awaiting its completion. In all
three [probe records](early-resume-api-probes.jsonl), the VM was still in
`restoring` (state 9), `canResume` was false, and the call failed with
`VZErrorDomain` code **4**, an invalid transition from restoring to running.
The VM remained restoring. Awaiting normal completion then allowed the usual
resume and all guest checks to pass. The resulting [full restores](early-resume-8g.jsonl)
took **3.837–3.875 s**, median **3.839 s**. These are normal full restores after a
rejected early-resume attempt, not demand-paged restore measurements.

This matches Apple's [documented restore contract](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/restoremachinestatefrom%28url%3Acompletionhandler%3A%29):
restoration finishes in the paused state. Calling resume concurrently is not a
supported shortcut. E2B's [userfaultfd-driven approach](https://github.com/e2b-dev/runtime/blob/main/docs/ARCHITECTURE.md)
requires control of the guest memory pager that this interface does not expose.
Anka's [ARM CLI caveat](https://docs.veertu.com/anka/anka-virtualization-cli/getting-started/modifying-your-vm/)
also prevents assuming that its reported suspended state means preserved memory;
no Anka license or alternative supported macOS pager was available for a direct
runtime trial. No private APIs or guest-memory modifications were used.

### Result and capacity policy

Resident pause is the demonstrated fast path: all eighteen wakeups were below
one second, including thirty-second pauses, with fast incremental builds.
Retain it only within the existing bounded, fully charged idle grace while CI
headroom exists. Queued CI must trigger checkpoint-and-exit, with capacity held
until that operation completes. An evicted environment still has the measured
multi-second disk-restoration path; neither the retained fast path nor a reserved
slot makes that cold restoration meet the two-second goal. Host pressure, longer
idle periods, larger projects and tail latency remain unmeasured here.

Validation passed: the resident-enabled Swift release build and signing, Go race
tests for the benchmark/lifecycle/shadow-policy packages, benchmark `go vet`,
shell syntax and whitespace checks. New tests cover stale acknowledgements,
incorrect VM states/actions/PIDs, explicit runtime opt-in, refusal to run a
released-capacity CI hook during resident pause, deadlines and canceled requests.
The final cancellation guard was separately race-tested; it affects canceled
requests, not the successful measured path. The resident/API-probe code remains
benchmark-only and has not replaced the fleet runtime or enabled admission.

All four experiment cases completed successfully. Their processes exited and
the private store, runtime build and reservation marker were removed before
uncordoning. Both normal staging runners subsequently passed the Kubernetes
Ready check and returned to `1/1 Running`.

## Supported-runtime investigation — 2026-10-28

The relevant requirement is **an Apple Silicon macOS guest with live process
memory preserved after releasing its VM process and host capacity**. Linux on
an Apple host, disk-only snapshots and resident pause do not demonstrate this.
The sources checked do not establish a supported demand-paged macOS restore:

| Runtime/provider | Primary evidence | Implication |
| --- | --- | --- |
| Apple Virtualization / Tart | The SDK audit and three rejected overlapping-resume probes above; Apple's [save/restore explanation](https://developer.apple.com/videos/play/wwdc2023/10007/) | The exposed operation restores a saved machine before a separate resume. We found no supported caller-supplied memory pager. This does not prove how Apple implements every internal read. |
| Anka | [Technology comparison](https://veertu.com/technology/), [ARM suspend caveat](https://docs.veertu.com/anka/anka-virtualization-cli/getting-started/modifying-your-vm/) | The less-than-one-second claim is under **Intel**; Apple Silicon uses Virtualization.framework. The ARM CLI documentation warns that suspend stops the VM, while the GUI preserves state on the same host. Confirm actual version/semantics before treating a CLI launch benchmark as memory restoration. |
| Parallels | [Apple Silicon macOS support](https://kb.parallels.com/en/128867) | Supports macOS suspend/resume, including CLI, but explicitly uses Apple's framework for all macOS VM components. No documented lazy-memory API or matched latency-by-shape benchmark was found. It is a possible independent measurement, not evidence of a different restore engine. |
| UTM | [`_restoreSnapshot` in its Apple VM implementation](https://github.com/utmapp/UTM/blob/main/Services/UTMAppleVirtualMachine.swift) | Calls `restoreMachineStateFrom` and separately resumes. Its QEMU backend's features must not be attributed to its Apple macOS backend. |
| Daytona macOS | [v2 alpha lifecycle](https://www.daytona.io/docs/en/v2/macos-sandboxes/) | Saves memory on the reserved Mac and restores there; no disclosed pager or comparable timings. A reserved place on a Mac does not prove RAM remains resident. |

For contrast, [E2B's Linux runtime](https://github.com/e2b-dev/runtime/blob/main/docs/ARCHITECTURE.md)
exposes a userfaultfd-based memory fault handler. That is the capability we would
need to establish for macOS, rather than merely selecting a different CLI.
Apple's public balloon device is not evidence that macOS guests can be shrunk:
[UTM explicitly excludes macOS guests when attaching that device](https://github.com/utmapp/UTM/blob/main/Configuration/UTMAppleConfigurationVirtualization.swift).
We have not demonstrated a supported macOS balloon/dirty-page export path.

No Anka or Parallels measurement was performed in this investigation. Anka on
the staging Mac mini still needs an appropriate [Build license or trial](https://docs.veertu.com/anka/licensing/).
Before investing in another runtime, obtain a concrete demonstration of
Apple Silicon macOS process-memory restoration at 8/16/24 GiB, with the old
VM process gone, capacity reused, a live-memory sentinel and time to a successful
guest command. Also measure the first simulator/build operation so deferred page
faults cannot hide the cost. A vendor claim about Intel, cold boot or disk clones
does not satisfy that gate. No vendor has been contacted on the user's behalf.

## Snapshot growth by guest shape — 2026-10-28

The matched matrix uses the same staging host, eight vCPUs, Xcode 26.6 image
digest `41bace4ce9624b930d409b243a3a9b66424f3b879c291edd508690a1fd0f2670`,
and pinned Tart profiling source/patch as above. The profiling binary SHA-256 is
`2e4eb94e279d6a60399d9eb4671e3d208ce7a6edc1e27551455ead53aab17309`.
The ordinary fleet binary was not replaced. Each case starts with a fresh private
clone and completes three save/restore cycles. The idle case waits 30 seconds
after command readiness and starts no simulator/build workload; it still runs
the image's ordinary macOS services. The fixture case boots the simulator and
builds the same iOS framework as before. All eighteen restores preserve the live
memory token; all nine fixture restores also pass the simulator/build check.

`memory-shape-matrix.sh` reproduces the six cases after staging `benchmark`,
`fixture-prepare.sh`, `acquire.sh` and the prepared private store as described in
the experiment guide. `guest-memory-profile.sh` collects guest memory counters
immediately before each save, outside the measured suspension. Complete samples
and diagnostic logs are in [memory-shapes/](memory-shapes/).

Medians, three cycles per row; snapshot GB is decimal, guest shapes are GiB:

| Workload | Shape | Saved state | Suspension | Apple restore API | First successful command | Following workload |
| --- | --- | --- | --- | --- | --- | --- |
| Idle | 8 GiB | 3.09 GB | 1.590 s | 2.644 s | 3.341 s | 0.030 s |
| Idle | 16 GiB | 5.84 GB | 3.073 s | 4.949 s | 5.669 s | 0.017 s |
| Idle | 24 GiB | 7.18 GB | 4.522 s | 6.244 s | 6.992 s | 0.044 s |
| Simulator + build | 8 GiB | 3.56 GB | 1.704 s | 3.022 s | 3.812 s | 1.481 s |
| Simulator + build | 16 GiB | 7.05 GB | 3.380 s | 5.813 s | 6.658 s | 1.843 s |
| Simulator + build | 24 GiB | 9.66 GB | 4.871 s | 7.923 s | 8.790 s | 1.336 s |

The last column is `/usr/bin/true` for idle cases and the incremental build plus
simulator command for fixture cases. It is additional to first-command latency.
These measurements use the same readiness gate across all shapes; compare them
within this matrix rather than claiming an improvement over older readiness
implementations. They are small immediate-restore samples, not p95 or cold-cache
SLO measurements. No concurrent CI workload ran on the reserved host. Host swap
was 9.44 MiB when checked during the matrix; this was not a host-pressure test.

Guest memory immediately before cycle three, in GiB:

| Workload | Shape | Free | File-backed | Anonymous | Wired | Logical pages in compressor | Physical compressor footprint |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Idle | 8 | 0.07 | 3.17 | 3.69 | 0.89 | 0.53 | 0.16 |
| Idle | 16 | 4.21 | 5.91 | 4.85 | 1.01 | 0 | 0 |
| Idle | 24 | 12.05 | 5.93 | 4.93 | 1.08 | 0 | 0 |
| Simulator + build | 8 | 0.07 | 1.95 | 1.88 | 1.85 | 6.08 | 2.23 |
| Simulator + build | 16 | 0.13 | 6.39 | 5.84 | 2.13 | 3.66 | 1.51 |
| Simulator + build | 24 | 0.07 | 10.96 | 10.69 | 2.26 | 0 | 0 |

The same commands do not produce the same physical working set: macOS retains
more file-backed pages and leaves more anonymous memory uncompressed when the
guest is larger. No guest swapped in this matrix. File-backed memory is not all
discardable cache, and logical compressed pages must not be added to the physical
compressor footprint. The diagnostic RSS sum double-counts shared mappings and
is not used as a physical-memory estimate.

This explains part, not all, of the growth. The idle 16/24-GiB guests have very
similar occupied categories, but the 24-GiB snapshot is 1.34 GB larger despite
having about eight GiB more free memory. Snapshot lengths in this matrix are
rounded to 64 MiB plus 4096 bytes; allocated disk blocks are close to those
lengths. We cannot map this opaque, encrypted file directly to active guest
pages, infer that all free pages are omitted, or distinguish historical page
contents, compression and framework metadata from these counters alone.

An initial diagnostic attempt failed before its first save because the script
used `/usr/bin/date` instead of macOS's `/bin/date`; the corrected matrix above
was restarted from fresh clones and excludes that failed attempt.

### Paired 24-GiB cache-reclamation intervention

One further fresh fixture guest completed six cycles: three controls followed
by three with `sudo -n purge` immediately before saving. The same guest,
simulator and in-memory token survive throughout. This is a sequential paired
diagnostic, not a randomized benchmark. Reproduce it with the same benchmark
flags, `--memory-mb 24576 --cycles 6`, and
`--before-suspend-script guest-cache-reclaim.sh` in place of the memory-profile
hook. The script counts cycles inside the disposable guest; the first three
only collect counters. [Samples](memory-shapes/fixture-reclaim-24576.jsonl) and
[before/after counters](memory-shapes/fixture-reclaim-24576.log) are retained.

| Median, three cycles each | Control | Cache reclamation |
| --- | --- | --- |
| Preparation before suspension, including diagnostics | 0.200 s | 2.925 s |
| Saved state | 9.53 GB | 9.13 GB |
| Suspension after preparation | 5.024 s | 4.888 s |
| First successful command | 8.658 s | 8.407 s |
| Following incremental build + simulator command | 1.386 s | 2.435 s |

On the first intervention, file-backed pages fell from **10.869 to 0.846 GiB**
and guest free memory rose from **0.078 to 10.025 GiB**. Nevertheless, the saved
state was still **9.53 GB** and restore-to-command took **8.654 s**. Later purge
cycles reduced the snapshot to 9.13 and 8.99 GB, with command times of 8.407 and
8.246 seconds. This rejects the simple hypothesis that freeing ten GiB of guest
file cache immediately removes ten GiB from Apple's checkpoint/restore work.
It does not identify the private snapshot format or prove which free pages the
framework retains. The extra preparation and slower following builds outweigh
the small wakeup improvement: do not enable purge on the normal suspension path.

### Resulting policy and validation

Keep the resident experiment as the fast tier while CI capacity is spare; do not
claim the 1–2-second target for evicted environments. The shadow evaluator now
distinguishes `pause_resident`, `keep_paused` and `evict`, retaining the full
configured memory, CPU and slot charge through resident pause and eviction.
It recommends eviction on queued CI, unknown/stale demand, lost headroom or
expired grace, and reconciliation on inconsistent idle-resident ownership/state.
The 30-second default / 60-second maximum retention remains bounded. No
production allocation or automatic eviction controller has been enabled.

Validation: all **24 new full restores** preserved the live memory token; all
**15 fixture restores** passed the incremental build and original simulator
command. The instrumented Swift release build and signing succeeded. Go race
tests passed for the lifecycle, benchmark and shadow-policy packages; `go vet`,
shell syntax checks and whitespace checks passed. The readiness test required
local Unix-socket access outside the filesystem sandbox, and was rerun
successfully with that access. The final ownership-fencing policy cases also
passed the race test. These are targeted checks, not the full monorepo suite.

The staging reservation, isolated store and runtime build have been removed.
The node is uncordoned and both ordinary staging runner Pods were verified Ready.
