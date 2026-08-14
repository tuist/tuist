# Tuist Cache Service (Elixir/Phoenix)

This service provides caching infrastructure for Tuist. It shares tooling and conventions with the Tuist Server.

## Key Boundaries
- Web/API layer: `cache/lib/cache_web`
- Cache domain and storage: `cache/lib/cache`
- Nginx and host-level config: `cache/platform`

## Swift registry: read-only, never a writer
Cache serves Swift registry **reads** (`Cache.Registry.Metadata`, `AlternateManifests`,
`ManifestVariants`, `Disk`) and pulls artifacts to local disk via
`S3Transfers.enqueue_registry_download/1`. It has **no write path**, by construction
rather than by configuration: the sync worker, release worker, S3 lock, sync cursor and
Swift Package Index client are gone, `Cache.Registry.Metadata` exposes no
`put_package`/`delete_package`, and `S3TransferWorker` drops any registry upload it finds
queued.

The single writer is the server's `Tuist.Registry.Swift.SyncWorker` /
`ReleaseWorker` (`TUIST_MODE=swift_registry_sync`). Do not reintroduce a cache-side
writer. Two writers against `registry/metadata/{scope}/{name}/index.json` corrupt it even
though they share an S3 lock, because the whole document is read-modify-written and the
cache read goes through a 10-minute Cachex TTL — the stale snapshot is taken before the
lock is acquired, so the lock cannot protect it. That reverts release checksums while the
archive objects keep the newer bytes, which surfaces to users as `invalidChecksum`.

## Related Context (Downlinks)
- Cache web layer: `cache/lib/cache_web/AGENTS.md`
- Cache domain and storage: `cache/lib/cache/AGENTS.md`
- Platform/nginx config: `cache/platform/AGENTS.md`
- Server conventions and tooling: `server/AGENTS.md`
- Grafana dashboard: [`infra/grafana-dashboards/cache-service.json`](../infra/grafana-dashboards/cache-service.json) (Git Sync'd with Grafana Cloud — see `infra/AGENTS.md`)
