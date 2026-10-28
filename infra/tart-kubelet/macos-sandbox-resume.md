# macOS sandbox resume experiment

This is the first stage of macOS sandbox support: a reusable Tart lifecycle,
a runnable same-host benchmark and a CI-first policy evaluator in shadow mode.
It does **not** enable macOS sandbox placement in the server or change runner
admission. Measure restoration before adding that integration.

The [staging measurements and reproducible workloads](benchmarks/macos-resume/README.md)
cover 8/16/24-GiB guests and an 8-GiB suspend → CI build → resume sequence.

## Runtime path

`StartWithOptions` starts a monitored, detached process without the runner
launcher's five-second sanity delay. `Run` and `RunWithOptions` preserve that
existing runner behavior. Start sandbox VMs with `Suspendable: true` from their
first boot and retain exactly the same device, disk and share configuration.

`RunHandle.WaitReady` calls a guest probe immediately, retries failed probes at
100 ms intervals and notices process death even during a probe. An IP or open
port is not readiness. The benchmark executes `/usr/bin/true` using `tart exec`:
the host-local, per-VM control socket reaches that VM's guest agent over vsock.
There are no shared network passwords, DHCP assumptions, desktop/VNC readiness
checks or infrastructure credentials inside the guest.

`Suspend` takes the owned process handle. It waits for **all** of:

1. A successful suspend request (the CLI only delivers a signal).
2. A clean exit from the `tart run` process. A failed save can leave a partial
   state file; its existence alone does not prove success.
3. Tart reporting suspended, with no remaining process for that VM.

Only then can a caller release the guest slot, CPU and memory reservation.
On error, keep the charge until a separate reconciliation fences the VM. Do not
retry against a different process with an old handle. All lifecycle operations
for a VM must be serialized by its owner. Recovery after a daemon restart needs
a durable ownership journal; these process-local handles do not implement it.

`Resume` refuses a VM without suspended state. It does not pull, clone, resize,
move to another host or fall back to a cold boot. Readiness timeout or request
cancellation does not kill a successfully launched VM or release its charge.
Local saved state remains coupled to the original host, Tart version, guest
configuration and disk contents. Treat an incompatible restore as an explicit
failure, not a successful new session.

The relevant upstream behavior is in Tart 2.41.1's
[save/restore implementation](https://github.com/cirruslabs/tart/blob/2.41.1/Sources/tart/Commands/Run.swift),
[state reporting](https://github.com/cirruslabs/tart/blob/2.41.1/Sources/tart/VMDirectory.swift)
and [guest command transport](https://github.com/cirruslabs/tart/blob/2.41.1/Sources/tart/Commands/Exec.swift).
Other runtime versions need the same live acceptance checks.

## Run the benchmark

Use an Apple silicon staging Mac, its deployed Tart binary, enough local SSD
space for writable image growth plus snapshots, and an **exclusive, bounded
host reservation**. Coordinate use of staging, cordon through the usual drain
path, let active jobs finish and verify all runner VMs have exited. Do not kill
CI to make a benchmark fit. Restore scheduling after stopping every experiment
VM, including a failed intervening workload.

Use a separate `TART_HOME` on the same APFS filesystem. The kubelet owns its
ordinary store and would collect a suspended VM without a Pod as an orphan.
Never put an experiment there or exclude a naming prefix from production GC.
The benchmark refuses the user's default store, requires an admission hook,
checks other running Tart processes before launch, and cleans up only its
uniquely named disposable clone. These checks supplement the reservation; they
cannot replace the fleet allocator or protect against another VM manager.

Stage a stopped local base in the isolated store, including any immutable content
referenced by a stacked image. APFS `cp -cR` can copy the base and content store
without downloading or duplicating all blocks. Do not hard-link writable files
or expose the host's image/cache store to the guest.

A runner golden needs preparation: its launch agent polls for CI work and halts
the guest on missing dispatch credentials. Use a sandbox-specific base whose
CI launch agent is disabled, with Xcode, simulator runtimes and the Tart guest
agent available. Do not give an experiment a real runner token. The production
sandbox image pipeline remains a follow-up.

Build from `infra/tart-kubelet`:

```sh
go build -o /tmp/sandbox-resume-benchmark ./cmd/sandbox-resume-benchmark
go build -o /tmp/sandbox-admission-shadow ./cmd/sandbox-admission-shadow
```

Provide four scripts:

| Script | Where it runs | Contract |
| --- | --- | --- |
| `acquire.sh` | Host | Wait for and verify an exclusive CI-safe reservation; fail if unavailable. Called before each launch. |
| `prepare.sh` | Guest | Checkout/build prerequisites and boot a simulator. Runs once per disposable clone. |
| `build.sh` | Guest | Run a representative build/test, fail on errors; retain build outputs for the incremental run. Required. |
| `between.sh` | Host | Run and **wait for** a substantial CI workload in the freed capacity, then confirm its VM has exited. Optional; omission measures immediate restore only. |

Host hooks receive `TART_HOME`, `TART_BINARY` and `SANDBOX_VM`. They are trusted
operator scripts, never session-supplied commands. Do not suspend/resize/delete
the named sandbox from a hook. The hook's output and guest build output go to
stderr; machine-readable samples go to stdout. The admission hook must own its
reservation until suspension/cleanup is confirmed, even if the benchmark exits
with an error. Cancellation of a shell does not prove its children have exited.

```sh
/tmp/sandbox-resume-benchmark \
  --home /path/to/private-tart-store --source sandbox-base \
  --memory-mb 8192 --cpus 8 --cycles 30 --timeout 1h \
  --acquire-script /path/to/acquire.sh \
  --prepare-script /path/to/prepare.sh \
  --build-script /path/to/build.sh \
  --between-script /path/to/between.sh \
  > after-ci-8g.jsonl 2> after-ci-8g.log
```

Repeat at 16384 and 24576 MiB. Run a matched immediate-restore series by omitting
`--between-script`. A host hook can invoke this binary with `--mode workload`
to create one independent disposable CI guest, run preparation and a build,
then stop and delete it. Use the same workload image, shape and scripts for a
baseline run before the sandbox experiment. Workload mode has no suspend loop.
Use a distinct result file for the nested command so its JSON does not mix
with the parent samples.

Every resume must answer a fresh challenge using a random token retained **only
in a live guest shell's memory**. An on-disk PID, stale reply or cold-booted guest
cannot satisfy that check. The post-resume build should also exercise the
previously booted simulator; the sentinel alone does not validate Xcode services.

Samples separate capacity-hook wait, process launch, time from capacity granted
to first successful guest command, suspension, intervening workload and build
time. `warm_command_ms` measures a command before suspension, while the guest
already runs. `first_command_ms` includes `launch_ms`; do not add them. `snapshot_bytes`
is logical size; `snapshot_allocated_bytes` is the file's allocated blocks, not
an estimate of total CoW storage reclaimed by deleting it. Collect filesystem
free space and host memory telemetry alongside the run.

The current public CLI does not expose a separately timed Apple restore RPC.
Its restore log messages may be buffered; do not report their arrival timestamps
as framework duration. The benchmark observes when Tart consumes `state.vzvmsave`
(`state_consumed_ms`, polled every 10 ms). In 2.41.1 that happens after Apple's
restore call returns and before the VM resumes. This includes Tart setup and
polling delay, so it is an upper bound on restore time rather than the API call's
isolated duration. `first_command_ms` includes framework restore, resume and guest
reconnection. The difference helps distinguish restoration cost from reconnect
delay. Add upstream instrumentation for an exact framework-only measurement.

An intervening CI workload does not prove all snapshot pages were evicted from
the host's filesystem cache. Record workload and host memory pressure. Compare
several representative workloads and longer pauses before claiming a p95. The
restoration target is p95 at or below two seconds **after capacity is granted**,
with running processes and simulator state preserved. The initial 5–10 second
measurements do not meet it. An already-running guest during warm grace does not
count as restoration, and the target is not an availability guarantee under CI
saturation.

### Instrumented restoration

`benchmarks/macos-resume/build-profile-tart.sh` builds a separate Tart 2.41.1
binary with the adjacent patch. Never replace the fleet binary to profile it.
Set `TUIST_TART_PROFILE=1` and pass the built binary with `--tart`. The patch
retains version `2.41.1`: Tart places it in a console device name, so changing
it to a development version changes the VM configuration and can break both
guest-agent discovery and snapshot compatibility. Record the pinned upstream
commit, patch and binary checksum to distinguish the instrumented build.
Monotonic timestamps immediately surround Apple's restore and resume calls,
state-file removal and control-socket setup. The benchmark reads only this
launch's log segment and rejects incomplete, mixed-process or out-of-order
traces. Unmodified Tart omits `runtime_profile` rather than reporting zeros.
CPU usage in those events covers the Tart process, **not** Apple's separate
virtualization service, so low process CPU alone does not prove an I/O bottleneck.

Use `--before-suspend-script benchmarks/macos-resume/guest-memory.sh` to record
guest page counts and swap. The experimental `guest-purge.sh` additionally clears
reclaimable guest caches; its cost is `pre_suspend_ms`, separate from suspension
and restoration. Preserve processes and the booted simulator in every comparison.
Compare 4/6/8-GiB guests with identical workloads before treating a smaller shape
as viable; a small fixture cannot establish a realistic project's memory needs.

`--snapshot-read-ahead` reads the snapshot after capacity is granted, before
launching Tart. Its `read_ahead_ms` is **included** in `first_command_ms`; do not
subtract it when judging the target. This distinguishes a possible read-ahead
benefit from merely moving work outside the timer. It is not proof of a cold
page cache. `readiness_attempts` records each command probe's start, duration and
success to reveal retry/backoff gaps after the framework finishes.

`--gate-command-probe` first observes replacement of the previous launch's
host-local control socket, then executes the guest command. It avoids starting a
gRPC reconnect budget while that socket is absent or stale, without opening
extra connections to the guest. A socket file alone never satisfies readiness.
This remains a benchmark-only comparison; no CI
runner readiness or production admission changes with these flags.

For example, after building the profiler and reserving an isolated host:

```sh
TUIST_TART_PROFILE=1 /tmp/sandbox-resume-benchmark \
  --home /path/to/private-tart-store --source sandbox-base \
  --tart /path/to/profile-checkout/profile-tart.app/Contents/MacOS/tart \
  --memory-mb 8192 --cpus 8 --cycles 30 --timeout 1h \
  --acquire-script /path/to/acquire.sh \
  --prepare-script /path/to/prepare.sh --build-script /path/to/build.sh \
  --before-suspend-script /path/to/guest-memory.sh --gate-command-probe \
  > profile-8g.jsonl 2> profile-8g.log
```

Finish the profiler build **before** collecting measured runs. Preserve a
matched uninstrumented control, and change one experimental flag at a time.

`ram-snapshot.sh` is an optional diagnostic `--between-script`. Point
`RAM_SNAPSHOT_DIR` at an explicitly created, verified, disposable RAM-disk mount
and use `--between-label ram_snapshot`. It copies saved state there after the VM
exits and replaces the original path with a symlink. Copy cost is `between_ms`,
not hidden in suspension or claimed as a CI workload. The VM process is absent
between turns, but the snapshot's RAM still counts against protected CI headroom.
Remove retained copies and detach the RAM disk after the experiment. This is
an I/O isolation experiment, not a production snapshot retention design.

### Resident pause and the public restore boundary

Build with `build-profile-tart.sh /absolute/new/checkout resident` to add two
opt-in diagnostics. This applies the profiling patch first, then the resident
patch and its two Swift helpers. Neither is part of the deployed runtime.

With `TUIST_RESIDENT_BENCHMARK=1`, the isolated runtime accepts correlated
host-local `pause`, `resume` and `save` requests in its private VM directory.
They call the public Virtualization framework APIs on the main actor. The Go
benchmark's `--mode resident --resident-idle 30s` measures pause, the retained
interval, and resume through the first successful guest command. It verifies
the same host process, live guest token and simulator, and refuses to call a
socket or an acknowledgement alone readiness. All guest RAM and its VM slot
remain reserved. The file transport polls every five milliseconds; its overhead
is included in the end-to-end latency.

```sh
TUIST_TART_PROFILE=1 TUIST_RESIDENT_BENCHMARK=1 /tmp/sandbox-resume-benchmark \
  --home /path/to/private-tart-store --source sandbox-base \
  --tart /path/to/resident-build/profile-tart.app/Contents/MacOS/tart \
  --mode resident --memory-mb 8192 --cpus 8 --cycles 10 --resident-idle 1s \
  --resident-evict --acquire-script /path/to/acquire.sh \
  --prepare-script /path/to/prepare.sh --build-script /path/to/build.sh \
  > resident-8g.jsonl 2> resident-8g.log
```

`--resident-evict` additionally pauses, saves and stops the guest, waits for its
owned Tart process to exit, then restores it from disk. `evict_ms` includes pause,
save and process exit; `save_api_ms` isolates the save call. This measures the
cost of yielding the resident VM to CI, and confirms that the checkpoint still
preserves the original processes. It does not actually dispatch a CI job.

Separately, `TUIST_EARLY_RESUME_PROBE=1` with ordinary `--mode resume` starts the
restore operation, yields for ten milliseconds, and attempts the public resume
API before awaiting restoration. `TUIST_EARLY_RESUME_PROBE` log records include
the observed state, `canResume`, success or error, and PID. Only records that
observed restoration in progress test overlapping execution. The normal restore
then completes and still must pass the guest checks. This probes an API boundary;
it is **not** a lazy-memory implementation, and a rejected call must not be
reported as a fast restore.

## Shadow CI policy

`sandbox-admission-shadow` reads one `sandboxpolicy.Observation` JSON object per
line from stdin and prints a decision. It does not fetch demand, publish grants,
create Pods or authorize a launch. Feed it trusted, timestamped observations
from the allocator; `would_admit` is only a counterfactual decision.

Each observation identifies the host and owning host generation, includes fresh
fleet-wide dispatchable CI demand, host health/reservation/disk status and three
resource vectors (`slots`, `vcpus`, `memory_mb`): total capacity, committed use and
protected CI headroom. Also supply the requested sandbox shape. Count the actual
macOS VM slots (currently two), not `maxPods`. Committed use includes provisioning,
CI teardown, active sandbox turns, idle grace and suspension in progress. Include
an already resident sandbox once in committed use, including a resident with
`paused: true`; do not double-count protected headroom already held by running
warm CI VMs. Pausing execution releases no admission capacity.

The evaluator keeps active turns running, blocks new turns whenever CI is queued,
and fails closed when observations are over 15 seconds old, implausibly in the
future, or unknown. Resume stays on the owner host and generation. Every resource
dimension must fit after protected CI headroom. A resident idle sandbox gets
30 seconds of fully charged grace by default (configurable up to 60). Within that
grace, `pause_resident` recommends pausing an idle running VM, and `keep_paused`
retains an already paused VM. Queued CI, stale demand, lost headroom or expired
grace returns `evict`: save the current state, stop the process and confirm its
exit before releasing the charge. A failed save keeps the charge and is an
explicit reconciliation failure; it must not silently discard the environment.
`evict` itself never means resources have been freed. An impossible combination
of paused and active, or paused without resident, returns `reconcile`. An idle resident
whose host/generation ownership disagrees also needs reconciliation before any
VM operation; an eviction recommendation never overrides ownership fencing.

This is still a shadow evaluator and an experimental runtime. The benchmark's
exclusive staging reservation does not exercise live CI-driven eviction. The
production allocator must atomically fence a resident wake against an eviction
request; a cached `keep_paused` decision is not permission to start another turn.
The measured multi-second eviction latency must be part of CI admission latency,
so preserve protected CI headroom instead of assuming eviction is instantaneous.

## Integration gate

Before enabling even an internal account, the next change must connect these
primitives to durable sandbox ownership, authenticated worker/session routing,
same-host execution Pods, atomic CI/sandbox reservations, explicit guest-slot
accounting for all Mac workloads, snapshot/disk budgets, retention, generation
fencing and restart reconciliation. Existing Linux admission cannot be reused
unchanged: its elastic cgroup memory grants are not macOS guest reservations.

Keep the first rollout at one concurrent sandbox, with no fixed reserved warm
pool. Compare CI queue latency and build/test duration as well as resume latency.
If local restoration is too slow, test longer opportunistic grace within CI
headroom before expanding availability promises. Pausing a VM in RAM continues
to consume its slot and memory and is not capacity reclamation.
