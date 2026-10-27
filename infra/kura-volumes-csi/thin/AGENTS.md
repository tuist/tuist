# Thin storage design and qualification

Parent: `../AGENTS.md`. This directory owns the storage contract and
reusable local Linux qualification harness, not a deployed allocator.

- `interface.md` documents the implemented conservative mode; `design.md` also describes blocked future shared mode.
  Do not describe a documented interface as implemented or qualified.
- Run `stack_test.rb` only as root inside a disposable Linux VM. It creates one
  private sparse file and attaches its own loop device. Never accept a caller
  supplied block device, reuse an existing VG, or run against hosted nodes.
- Preserve the cleanup trap and unique resource names. Keys are generated in
  memory and passed to cryptsetup on stdin. Output contains measurements only.
- Test physical mapped bytes and pool counters, not `df` or fstrim's reported
  bytes. Deleted open files and failed/ignored discard must retain charges.
- A project quota is not a limit on a thin device's mapped allocation. Keep the
  negative churn test; removing it would hide a pool-exhaustion failure mode.
- VM measurements qualify mechanisms only. They do not establish hosted NVMe
  throughput, regional capacity gains, memory costs, or CSI lifecycle safety.

- `prepare_pool.rb` only creates a new pool from free VG extents and writes per-node opt-in configuration. Never use it to convert populated thick storage.
- Host preparation must make `dm_thin_pool` available before creation and after reboot. The script checks loaded device-mapper targets and fails before mutation if support is absent; loading modules belongs to authorized host preparation.
- The real CSI Linux test is `../internal/driver/thin_integration_test.go`; compile it for the disposable VM and opt in explicitly. Its failure cleanup retains backing files if detachment cannot be verified.
