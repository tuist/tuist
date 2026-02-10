# Draft: Cache Disk & S3 Module Refactoring

## Requirements (confirmed)
- Split `Cache.Disk` (587 lines) into domain-specific modules
- Split `Cache.S3` (355 lines) into domain-specific modules
- Consolidate shared helpers

## User's Vision
- `cache/lib/cache/disk.ex` → generic disk functions (artifact_path, storage_dir, usage, etc.)
- `cache/lib/cache/registry/disk.ex` → registry-related disk functions
- `cache/lib/cache/module/disk.ex` → module cache disk functions  
- Same pattern for S3
- Helpers consolidated

## Research Findings

### Current Cache.Disk Structure (587 lines)
Contains 5 domain groups + shared infrastructure:

| Domain | Functions | Lines | Callers |
|--------|-----------|-------|---------|
| Xcode CAS | xcode_cas_key, xcode_cas_exists?, xcode_cas_put, xcode_cas_stat, xcode_cas_local_accel_path, xcode_cas_get_local_path | ~130 | CASController |
| Module Cache | module_key, module_exists?, module_put, module_put_from_parts, module_stat, module_local_accel_path | ~110 | ModuleCacheController |
| Gradle | gradle_key, gradle_exists?, gradle_put, gradle_stat, gradle_local_accel_path | ~80 | GradleController |
| Registry | registry_key, registry_exists?, registry_put, registry_stat, registry_local_accel_path | ~90 | RegistryController |
| Infrastructure | artifact_path, storage_dir, list_artifact_paths, delete_project, usage + private helpers | ~170 | DiskEvictionWorker, CleanProjectWorker, CacheArtifacts, S3TransferWorker, S3 |

### Current Cache.S3 Structure (355 lines)
| Function | Callers (cache) | Callers (registry) |
|----------|----------------|-------------------|
| presign_download_url | CAS, Module, Gradle controllers | RegistryController |
| remote_accel_path | CAS, Module, Gradle controllers | RegistryController |
| exists? | ModuleCacheController | RegistryController |
| upload | S3TransferWorker | — |
| download | S3TransferWorker | S3TransferWorker (type: :registry) |
| delete_all_with_prefix | CleanProjectWorker | — |
| upload_file | (via upload) | S3TransferWorker, ReleaseWorker |
| upload_content | — | ReleaseWorker |
| etag_from_headers | — | Lock, Metadata |

### Existing Directory Structure
- `cache/lib/cache/cas/` — only has `prom_ex_plugin.ex`
- `cache/lib/cache/module/` — only has `prom_ex_plugin.ex`
- `cache/lib/cache/registry/` — has 8 files (metadata, lock, sync_worker, etc.)
- No `cache/lib/cache/gradle/` directory exists

### Shared Patterns (consolidation candidates)
1. **Sharding** (`shards_for_id/1`): Used by CAS, module, and gradle (not registry)
2. **ensure_directory/1**: Used by all domains for mkdir_p before write
3. **move_file/2**: Used by CAS, module, gradle, registry for atomic file placement
4. **Key → path → stat/exists/put pattern**: Identical across all 4 domains
5. **local_accel_path pattern**: All 4 domains do `"/internal/local/" <> key`
6. **bucket_for_type**: S3's `:cache`/`:registry` switching logic

### Test Coverage
- `disk_test.exs` (521 lines, 3 test modules): Covers CAS, Registry, and multipart
- `s3_test.exs` (389 lines): Covers all S3 operations
- Controller tests cover integration with Disk/S3
- Mocking via Mimic with modules copied in test_helper.exs

## Technical Decisions
- (pending) Naming convention: `Cache.CAS.Disk` vs `Cache.Cas.Disk`
- (pending) Whether gradle gets its own directory
- (pending) How S3 split works — by domain or by type option
- (pending) What stays in the base `Cache.Disk` / `Cache.S3`

## Open Questions
- Should CAS also get its own subdirectory + disk module? (currently only prom_ex_plugin)
- Should Gradle get a new directory?
- Test strategy: update existing tests or create new domain-specific test files?

## Scope Boundaries
- INCLUDE: Splitting Disk and S3 modules, updating callers, updating tests
- EXCLUDE: Changing controller logic, changing API behavior, changing S3 transfer worker architecture
