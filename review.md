# Review: change @- (feat(cache): registry)

## Blocking / must-fix
- Registry metadata is never populated, so `list_releases`/`show_release`/manifest links will always 404 even if artifacts exist. `Cache.Registry.Metadata` only reads from S3; no writer exists in sync or release workers. Files: `cache/lib/cache/registry/metadata.ex:21`, `cache/lib/cache/registry/sync_worker.ex:42`, `cache/lib/cache/registry/release_worker.ex:62`, `cache/lib/cache_web/controllers/registry_controller.ex:18`.
- Sync and release workers call server endpoints that do not exist and expect fields the server never returns (`/api/registry/swift/packages`, `/api/registry/swift/packages/:scope/:name/releases`, `source_archive_url`, `manifests[].url`). This will 404 immediately. Files: `cache/lib/cache/registry/sync_worker.ex:55`, `cache/lib/cache/registry/release_worker.ex:39`, `server/lib/tuist_web/router.ex:468`.
- Registry API surface is incomplete vs current server: missing `/availability`, `/identifiers`, and `/login` endpoints, and the cache only accepts `json` instead of Swift registry MIME types. This is a compatibility break for existing clients. Files: `cache/lib/cache_web/router.ex:6`, `cache/lib/cache_web/router.ex:67`, `server/lib/tuist_web/router.ex:126`, `server/lib/tuist_web/router.ex:468`, `server/config/config.exs:72`.
- `swift-version` manifests are only served when present on local disk; if evicted, the cache redirects to the default manifest even when the alternate manifest exists in S3. This breaks SPM behavior and conflicts with the “can’t store all packages on disk” requirement. Files: `cache/lib/cache_web/controllers/registry_controller.ex:123`, `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:158`.
- Registry artifacts are never tracked for LRU eviction. Without `CacheArtifacts.track_artifact_access/1`, registry files won’t be evicted and disk usage can grow unbounded. Files: `cache/lib/cache_web/controllers/registry_controller.ex:93`, `cache/lib/cache/cache_artifacts.ex:49`, `cache/lib/cache/disk_eviction_worker.ex:70`.

## Major issues
- Sync re-downloads every package every hour with no S3 existence or “updated_at” delta check. `ReleaseWorker` only checks local disk, so evicted artifacts will be fetched again from the server, risking GitHub rate limits. Files: `cache/lib/cache/registry/sync_worker.ex:42`, `cache/lib/cache/registry/release_worker.ex:143`, `cache/config/config.exs:31`.
- `KeyNormalizer.normalize_version/1` doesn’t match server semantics for versions with multiple hyphens (server splits on all hyphens; cache uses `parts: 2`). This can generate different object keys for the same version. Files: `cache/lib/cache/registry/key_normalizer.ex:52`, `server/lib/tuist/registry/swift/packages.ex:138`.
- Cache-to-server HTTP calls do not set Swift registry `Accept` headers. With the server’s `api_registry_swift` pipeline, these requests will return 406 unless the server is loosened. Files: `cache/lib/cache/registry/sync_worker.ex:59`, `cache/lib/cache/registry/release_worker.ex:43`, `cache/lib/cache/registry/release_worker.ex:166`, `server/lib/tuist_web/router.ex:126`.
- Release downloads load the entire archive into memory before writing to disk, which is risky for large packages. Prefer streaming to file. File: `cache/lib/cache/registry/release_worker.ex:162`.
- `tuist registry setup` now always emits an HTTPS registry URL with no port, breaking local and custom-port setups and contradicting the new e2e docs. Files: `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift:115`, `docs/docs/registry-e2e-testing.md:127`.
- Cache does not attempt the same Swift version normalization as the server when resolving manifests (server tries `x`, `x.0`, `x.0.0`). This can incorrectly redirect to the default manifest even when an alternate manifest exists. Files: `cache/lib/cache_web/controllers/registry_controller.ex:123`, `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:158`.

## Test gaps
- `Cache.DiskRegistryTest` stubs the very functions it intends to test (`registry_put/5`, `registry_exists?/4`, `registry_stat/4`), so the tests do not validate real behavior. File: `cache/test/cache/disk_test.exs:23`.

## Fix Progress
- 2026-01-27: Begin remediation. Plan: remove cache->server sync, export registry metadata to S3 from server, align cache API surface/MIME types, fix manifest/S3 fallback + LRU tracking, fix CLI registry URL handling, and repair tests.
- 2026-01-27: Removed cache registry sync queue/cron and added Swift registry MIME types in `cache/config/config.exs`.
- 2026-01-27: Deleted cache registry sync/release/leader modules and their tests; removed Mimic copies for deleted modules.
- 2026-01-27: Aligned registry version normalization with server semantics in `cache/lib/cache/registry/key_normalizer.ex`.
- 2026-01-27: Added registry MIME accept pipeline and endpoints in `cache/lib/cache_web/router.ex`.
- 2026-01-27: Reworked registry controller to avoid server calls, add `/identifiers` and `/login`, normalize scope/name, handle S3 manifest fallback, and track LRU for registry artifacts.
- 2026-01-27: Fixed `Cache.DiskRegistryTest` to use real disk functions with a temporary storage dir.
- 2026-01-27: Added `Tuist.Registry.Swift.MetadataExporter` and wired package/release create/delete to write/delete S3 metadata; updated server test stubs.
- 2026-01-27: Adjusted registry fixtures to avoid S3 metadata export during tests.
- 2026-01-27: Fixed registry setup URL generation to preserve scheme/port for non-production hosts.
- 2026-01-27: Updated cache AGENTS.md files to include registry responsibilities.
- 2026-01-27: Updated `docs/docs/registry-e2e-testing.md` to reflect S3-first registry behavior and remove sync-worker references.
- 2026-01-27: Updated `server/data-export.md` to document registry metadata/artifact storage paths as non-exportable.
- 2026-01-27: Reverted server-side registry exporter changes (removed exporter file, calls, tests, and data-export additions).
- 2026-01-27: Added cache-side registry ingestion modules (GitHub client, SPI fetcher, S3 lock, sync worker, release worker) and re-enabled registry sync Oban queue/cron.
- 2026-01-27: Added registry sync configuration (token/allowlist/limits/interval) and helpers in `Cache.Config`.
- 2026-01-27: Added cache tests for registry sync/release workers and updated Mimic copies.
- 2026-01-27: Updated `docs/docs/registry-e2e-testing.md` for cache-driven sync and GitHub token requirement.
- 2026-01-27: Added `zip` to cache Docker image to support submodule-safe source archives.
- 2026-01-27: Removed global Mimic usage in cache tests, adjusted sync logic for new packages, and set registry tests to async: false to avoid env races.
- 2026-01-27: Cache tests run: `test/cache/registry/sync_worker_test.exs`, `test/cache/registry/release_worker_test.exs`, `test/cache_web/controllers/registry_controller_test.exs`, `test/cache/disk_test.exs` (pass).
- 2026-01-27: Server registry test attempt blocked by missing Postgres; ran `mix deps.get` in `server/` to satisfy deps (updated lockfile).

## Status
- Metadata now generated by cache sync (SPI + GitHub) and stored in S3.
- Cache-side registry sync restored with S3-backed locks to reduce multi-node duplication; no server dependency.
- API surface gaps: added `/availability`, `/identifiers`, `/login`, and registry MIME types in cache.
- Swift-version manifests: now search S3 before redirect and honor Swift version fallbacks.
- LRU eviction coverage: registry downloads now call `CacheArtifacts.track_artifact_access/1`.
- Key normalization mismatch: `normalize_version/1` aligned with server.
- Memory-heavy downloads: registry ingestion streams zipball to disk and uploads to S3; no server downloads.
- Server exporter changes reverted; no server-side registry dependencies added.
- Registry setup URL regression: fixed to preserve scheme/port for non-production.
- Tests: registry controller tests updated for new behavior; disk registry tests now exercise real code.

## Discussion Notes (2026-01-27)
- End goal: remove registry from `server/` entirely; cache registry must not depend on server at all (no server sync/export).
- Cache owns registry ingestion via SPI + GitHub, including writing artifacts + metadata to S3.
- Deduplicate downloads across nodes (best-effort; occasional duplicates acceptable).
- Use `REGISTRY_GITHUB_TOKEN` for cache-side GitHub access.

## Plan (2026-01-27)
- Undo server-side exporter work: remove `server/lib/tuist/registry/swift/metadata_exporter.ex`, remove exporter calls/alias in `server/lib/tuist/registry/swift/packages.ex`, revert server tests/fixtures, and revert `server/data-export.md` changes tied to server-side registry metadata.
- Reintroduce cache-side registry ingestion using SPI + GitHub directly (no server calls): restore `Cache.Registry.SyncWorker` and `Cache.Registry.ReleaseWorker` and rework them to call SPI + GitHub APIs with `REGISTRY_GITHUB_TOKEN`.
- Add S3-backed lock helper for sync + per-package/per-release to reduce multi-node duplicate downloads.
- Implement cache-side artifact + metadata pipeline: download zipball to temp file, compute checksum, upload `source_archive.zip` and manifest files to S3, and update `registry/metadata/{scope}/{name}/index.json`.
- Keep disk bounded: ingestion uses temp files only; serving remains disk-first with S3 fallback + on-demand hydration + LRU eviction.
- Config/scheduling: restore `registry_sync` Oban queue + cron schedule; add config/env for token/allowlist as needed.
- Tests/docs: add tests for sync/release/lock, and update registry docs/env notes; keep `review.md` updated with each step.
