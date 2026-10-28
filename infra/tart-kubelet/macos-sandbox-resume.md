# macOS sandbox resume experiment

This opt-in prototype provides a Tart lifecycle, a same-host benchmark and a
CI-first shadow policy. It does not enable production sandbox placement. Results,
tradeoffs and the original evidence archive live in the
[handbook research note](../../handbook/handbook/engineering/macos-sandbox-resume.md).

## Lifecycle and capacity

Start with `StartWithOptions` and `Suspendable: true`, preserving disks, shares
and device configuration across restores. `RunWithOptions` keeps the existing
five-second CI launcher window. `WaitReady` requires a successful guest command
through Tart's local control socket; an IP, socket or acknowledgement is insufficient.

Serialize lifecycle operations and retain the owned process handle. `Suspend`
requires a successful request, clean process exit, suspended state and no remaining
matching process before capacity can be released. Its `IsRunning` check is
host-wide, not scoped to `TART_HOME`: **names must be unique across all stores**.
The benchmark generates random names. A collision with another store fails closed
by retaining the charge; production integration must enforce host-wide uniqueness
or implement store-aware process fencing. Never reuse an old handle for a new process.

`Resume` requires a same-host reservation and refuses cold-boot fallback. Readiness
failure, cancellation or failed suspension does not release capacity. Saved state
is coupled to the original host, runtime, configuration and disks. Process-local
handles do not provide restart recovery or durable ownership.

## Reproduce

1. Reserve an Apple Silicon staging Mac exclusively for a bounded period. Drain
   CI normally and verify its VMs have exited. Do not terminate CI to make room.
2. Stage a stopped `sandbox-base` in a private Tart store on the same APFS
   filesystem. Include content referenced by stacked images; never hard-link
   writable disks. Disable the base's CI launch agent and supply no runner token.
   Xcode, simulator runtimes and the Tart guest agent must be present.
3. Identify the **actual kubelet store**, including when the benchmark runs as a
   different user. Pass it as `--kubelet-home`. The benchmark resolves symlinks and
   rejects equal, nested or ancestor paths relative to that store and the invoking
   user's existing default store. Both supplied stores must exist. These checks
   depend on correct operator input and stable host paths, not untrusted users.
4. Build from `infra/tart-kubelet`: `go build -o /tmp/sandbox-resume-benchmark
   ./cmd/sandbox-resume-benchmark`. Use the [workload scripts](benchmarks/macos-resume/README.md)
   or equivalent representative guest preparation/build scripts.
5. Provide an operator-owned `acquire.sh` that verifies the reservation before
   every launch and retains it until VM exit is confirmed. Host hooks receive
   `TART_HOME`, `TART_BINARY` and `SANDBOX_VM`. They must not manipulate the sandbox
   lifecycle. Shell cancellation does not prove child processes have exited.

```sh
/tmp/sandbox-resume-benchmark \
  --home /path/to/private-store --kubelet-home /Users/runner/.tart \
  --source sandbox-base --memory-mb 8192 --cpus 8 --cycles 30 --timeout 1h \
  --acquire-script /path/to/acquire.sh \
  --prepare-script /path/to/prepare.sh --build-script /path/to/build.sh \
  > results.jsonl 2> results.log
```

Repeat at 16384 and 24576 MiB. `--between-script` runs and awaits a CI workload
while the sandbox is suspended; compare a separate `--mode workload` baseline.
The benchmark checks a live-memory challenge-response token after every restore;
the build script must also use the original booted simulator. Capture host memory
pressure and filesystem free space. Restore scheduling only after all experiment
VMs and hook children exit; remove only their private stores and reservations.

## Optional profiling and resident mode

Build a separate pinned runtime with `sh benchmarks/macos-resume/build-profile-tart.sh
/absolute/new/checkout resident`. Never replace the fleet binary. Pass the resulting
`profile-tart.app/Contents/MacOS/tart` via `--tart` and set `TUIST_TART_PROFILE=1`.
Keep its version string unchanged for guest-agent and snapshot compatibility.
Record the upstream commit, patches and binary checksum with each run.

For resident pause, also set `TUIST_RESIDENT_BENCHMARK=1` and add `--mode resident
--resident-idle 30s --resident-evict`. The same VM process, slot, vCPUs and configured
RAM remain fully charged during pause. Eviction measures save and process exit
before a full restore; it does not dispatch CI. Resident mode rejects intervening
workload hooks. The benchmark transport is not a production session protocol.

`--gate-command-probe` waits for replacement of the old control socket before
executing the readiness command. `first_command_ms` includes launch/restore and
excludes admission wait and the following build. Profile collection allows up to
one second for buffered log delivery after capturing first-command time; Apple
API durations use event timestamps, never log arrival times. Uninstrumented runs
omit the profile. `state_consumed_ms` is an upper bound, not Apple API duration.

Diagnostics: `--before-suspend-script` reports its cost separately;
`--snapshot-read-ahead` includes read cost in first-command latency. The RAM-disk
hook moves snapshot copying outside that timer and still consumes host memory.
`TUIST_EARLY_RESUME_PROBE=1` on the resident build with ordinary resume mode probes
Apple's restore/resume boundary; rejection is not a successful lazy restore.

## Shadow policy and integration gate

`sandbox-admission-shadow` reads one `sandboxpolicy.Observation` JSON object per
line. Decisions never grant reservations or prove released capacity. Count all
committed slots, vCPUs and configured memory, including paused VMs, provisioning,
teardown and saves. Protect CI headroom without counting warm CI twice. Demand
must be known and at most 15 seconds old; queued CI blocks new turns. Active turns
finish. Idle residents get 30 seconds of grace (maximum 60), then eviction; CI
demand or lost headroom ends grace early. Ownership/state mismatch requires
reconciliation. A wake and an eviction must be fenced atomically by the allocator.

Before rollout, add durable ownership, authenticated routing, same-host Pods,
atomic reservations, generation fencing, restart reconciliation, snapshot budgets
and retention. Begin with one concurrent sandbox and measure CI queue/build
latency as well as resume latency. Eviction takes time: keep protected headroom.
