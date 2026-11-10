# Shared disk allocator

One agent owns a physical XFS filesystem and its project quotas. Account
floors are protected; ceilings may exceed capacity in aggregate. Current
enforced budgets and physical usage must both remain charged until quota
read-back proves capacity can be reassigned. Kernel quotas are authoritative
after restart; JSON budget files only tell compatible runtimes how to reclaim.

Never credit a requested shrink, stale inventory, expired authorization,
unlinked-but-open file or disappeared pod as reclaimed capacity. Unmanaged
project quotas and non-tenant usage also consume capacity. Use the same quota
lock as the local-path provisioner. Runtime control files must be mounted
read-only outside tenant data directories.

Run `go test ./internal/diskallocator/...` and the local real-XFS harness in
`kura/test/e2e/shared-disk/`. No mock-only test establishes disk protection.
