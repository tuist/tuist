# macOS resume benchmark fixtures

Follow the [experiment guide](../../macos-sandbox-resume.md) for host reservation,
store isolation, lifecycle semantics and command-line options. Performance results
and the historical evidence archive are in the
[handbook research note](../../../../handbook/handbook/engineering/macos-sandbox-resume.md).

## Workloads

- `make-fixture-prepare.sh` generates guest preparation from the repository's small
  iOS framework fixture; `build-fixture.sh` rebuilds it and checks the original
  booted simulator. Generate preparation from this checkout with
  `sh make-fixture-prepare.sh > /path/to/fixture-prepare.sh`.
- `prepare-ci.sh`, `build-ci.sh` and `between-ci.sh` run an independent compilation
  in freed capacity. Set `BENCHMARK_DIR` and `KUBELET_TART_HOME` (the actual kubelet
  store, even when owned by another user). Supply a reservation-checking
  `acquire.sh`; do not substitute an unconditional success command.
- `memory-shape-matrix.sh /absolute/experiment-root /absolute/profile-tart` runs
  three cycles each at 8/16/24 GiB with idle and fixture workloads. Supply
  `benchmark`, `store`, `fixture-prepare.sh` and `acquire.sh` under that root, and
  export `KUBELET_TART_HOME`. Results are written under `results/` without
  overwriting earlier JSONL files.

## Diagnostics

`build-profile-tart.sh` builds and signs the pinned Tart release in a new scratch
checkout. Its optional `resident` argument adds `ResidentBenchmark.swift` and
`EarlyResumeProbe.swift`. Keep both patches with any archived measurements.

`guest-memory.sh` and `guest-memory-profile.sh` capture guest memory counters;
`guest-purge.sh` and `guest-cache-reclaim.sh` are cache-reclamation interventions.
Use them as `--before-suspend-script` and include their preparation cost in comparisons.
`ram-snapshot.sh` is a `--between-script` diagnostic requiring `RAM_SNAPSHOT_DIR`
to name an explicitly verified disposable RAM-disk mount. Its copies still consume
host memory and must be removed before detaching that disk.

Archive new JSONL samples, stderr logs, runtime/image versions, patch/binary hashes,
host pressure and reservation details with the research note. Do not add raw run
history to this source directory. Small samples establish feasibility, not p95s.
