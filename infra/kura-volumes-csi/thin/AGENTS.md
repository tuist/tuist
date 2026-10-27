# Thin storage design and qualification

Parent: `../AGENTS.md`. This directory owns the proposed storage contract and
reusable local Linux qualification harness, not a deployed allocator.

- `design.md` distinguishes proposed interfaces from the current thick driver.
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
