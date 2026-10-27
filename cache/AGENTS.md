# Cache service

Elixir/Phoenix service with nginx-authenticated file serving. See `cache/README.md`
for the storage and request paths; `cache/platform/` contains NixOS/nginx config.
Use `server/AGENTS.md` for shared Elixir and testing conventions.

Run from `cache/`: `mise run install`, `mise run test`,
`mise run format --check`, and `mise run credo`.

- Keep authentication in the Phoenix layer before nginx serves cached files.
- Repository-monitoring wrappers supply cache-specific labels and telemetry
  prefixes; shared pool metrics belong in `tuist_common/`. Repo supervision stays
  in `cache/lib/cache/application.ex`.
- Swift registry reads and local downloads belong here, but never registry writes.
  The only writer is the server's `Tuist.Registry.Swift.SyncWorker`/`ReleaseWorker`
  in `TUIST_MODE=swift_registry_sync`. Do not restore cache-side sync/release jobs,
  metadata mutation, or registry uploads; queued uploads must remain dropped.
  An S3 lock cannot make two writers safe: cached metadata is read before the lock
  and can overwrite newer checksums while leaving newer archive bytes.
