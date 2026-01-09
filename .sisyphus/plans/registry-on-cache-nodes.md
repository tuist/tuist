# Registry on Cache Nodes

## Context

### Original Request
Serve the Swift Package Registry from cache nodes instead of the central server. Currently served by streaming directly from S3 on the server. Should follow the two-tier storage architecture that cache already uses for CAS and module cache. Cannot run package sync on every cache node (4 nodes total) due to GitHub rate limits. Need a single URL for CLI since SwiftPM registry URLs are configured statically.

### Interview Summary
**Key Discussions**:
- Infrastructure: Cloudflare geo-steering with new subdomain `registry.tuist.dev`
- Sync coordination: Leader election via S3 lock file (only one node syncs)
- Metadata storage: S3 JSON files (no database on cache nodes)
- Two-tier storage: Local disk + S3 fallback (same as CAS)
- Same S3 bucket as CAS, different path prefix
- No authentication (public registry, matches server)
- CLI needs update to configure new URL

**Research Findings**:
- Tigris supports conditional writes for lock acquisition
- Cloudflare geo-steering routes based on client location with health checks
- Server sync pulls from SwiftPackageIndex hourly via `SyncPackagesWorker`
- Cache already has `S3TransferWorker` for async S3 operations

### Metis Review
**Identified Gaps** (addressed):
- Leader crash handling: Read lock → check expiry → delete if expired → retry acquisition
- Cold start behavior: Fetch on-demand only (matches CAS)
- Package deletion: Leader sync deletes stale metadata (match server behavior)
- Manifest variant handling: Replicate server's manifest selection and redirect logic

---

## Work Objectives

### Core Objective
Enable cache nodes to serve Swift Package Registry with two-tier storage, coordinated sync via leader election, and single anycast URL via Cloudflare.

### Concrete Deliverables
1. Registry metadata module (`Cache.Registry.Metadata`) for S3 JSON storage (NEW FILE)
2. Leader election module (`Cache.Registry.LeaderElection`) using S3 conditional writes (NEW FILE)
3. Package sync worker (`Cache.Registry.SyncWorker`) ported from server (NEW FILE)
4. Registry controller (`CacheWeb.RegistryController`) matching server's API (NEW FILE)
5. Registry disk functions in `Cache.Disk` (EXTEND EXISTING)
6. S3Transfer schema extension for `:registry` artifact type (SCHEMA CHANGE - NO MIGRATION)
7. CLI update for new registry URL (MODIFY EXISTING)
8. Cloudflare configuration documentation (NEW FILE)

### Definition of Done
- [x] `GET https://registry.tuist.dev/api/registry/swift` returns 200
- [x] `swift package resolve` works with packages from registry
- [x] Leader election ensures only one node syncs at a time
- [x] Cache hit serves from local disk (nginx X-Accel-Redirect)
- [x] Cache miss fetches from S3 and caches locally
- [x] All server API endpoints replicated with identical responses

### Must Have
- Exact API compatibility with server's `/api/registry/swift/*` endpoints
- Leader election with TTL expiry and proper takeover algorithm
- Metadata JSON schema supporting all API responses
- Two-tier storage for source archives and manifests
- CLI `tuist registry setup` generates new URL
- S3Transfer schema supports `:registry` artifact type

### Must NOT Have (Guardrails)
- ❌ Database access from cache nodes
- ❌ GitHub API calls from non-leader nodes
- ❌ Authentication on registry endpoints (public registry)
- ❌ Analytics/telemetry (explicitly deferred)
- ❌ Package upload/publish (read-only registry)
- ❌ Changes to server registry code (code changes)
- ❌ Package signing or private registries

### ⚠️ GIT WORKFLOW REMINDER (CRITICAL) ⚠️

**DO NOT PUSH commits without explicit user approval.**

- Create commits locally as specified in each task
- Wait for user review before pushing
- User will explicitly request push when ready

### Sync Ownership Strategy

**Key Fact**: Cache and server use **completely separate S3 buckets**:
- Server: `Environment.s3_bucket_name()` from encrypted secrets
- Cache: `S3_BUCKET` environment variable

**This means**: There is NO conflict between server and cache writing registry objects. They write to different buckets entirely.

**Architecture**:
1. **Server** syncs packages → writes to **server's S3 bucket** + PostgreSQL DB
2. **Cache** syncs packages → writes to **cache's S3 bucket** (separate bucket)
3. **No coordination needed** - completely independent storage backends

**Cache's registry flow**:
- Cache leader syncs from SwiftPackageIndex → writes metadata JSON + source archives to cache's S3 bucket
- Cache nodes serve from cache's S3 bucket (two-tier: local disk + S3 fallback)
- Checksums computed by cache from cache's own S3 objects

**Server's registry flow** (unchanged):
- Server syncs → writes to server's S3 bucket + DB
- Server API streams from server's S3 bucket
- Checksums stored in PostgreSQL

**No changes needed to server** - it continues operating independently with its own bucket.

### Disk Eviction Strategy for Registry Artifacts

**Problem**: Cache nodes run `DiskEvictionWorker` to evict CAS artifacts when disk fills up. Registry artifacts stored under the same `/cas` volume will consume space but may not be tracked for eviction.

**Decision**: **Registry artifacts do NOT participate in eviction.**

**Rationale**:
1. **Volume is different**: Registry artifacts are stored in S3 and fetched on-demand to local disk
2. **Natural cleanup**: Local registry files can be safely deleted without data loss (S3 is authoritative)
3. **Separate tracking not worth complexity**: Adding registry to `CASArtifacts` SQLite table adds complexity for marginal benefit

**Implementation**:
1. **Accept shared disk usage**: Registry files under `/cas/registry/...` share the CAS volume
2. **Eviction ignores registry**: `DiskEvictionWorker` only tracks/evicts CAS artifacts (current behavior)
3. **Simple cleanup**: If disk pressure becomes an issue, add a separate registry cleanup job that:
   - Lists local registry files older than N days
   - Deletes them (S3 has authoritative copies)
   - NOT part of initial implementation (can be added later if needed)

**Risk mitigation**:
- Registry artifacts are relatively small (manifests are KB, source archives typically <10MB)
- SwiftPackageIndex has ~10K packages, total storage is bounded
- CAS eviction continues to work - it just doesn't evict registry files
- If disk fills: registry files can be manually deleted; next request fetches from S3

**Future improvement** (out of scope for this plan):
- Add `Cache.Registry.CleanupWorker` that deletes local registry files older than 7 days
- Track last-access time for registry files separately

### Key Normalization Rules (CRITICAL for S3 Key Compatibility)

Cache MUST match server's S3 key generation exactly. Rules from `server/lib/tuist/registry/swift/packages.ex`:

**1. All keys are downcased** (`String.downcase/1`):
- `Apple/Swift-Argument-Parser` → `apple/swift-argument-parser`

**2. Version normalization** (`semantic_version/1`):
- Strip leading `v`: `v1.2.3` → `1.2.3`
- Add trailing zeros: `1` → `1.0.0`, `1.2` → `1.2.0`
- Pre-release handling: `1.0.0-alpha.1` → `1.0.0-alpha+1` (dot→plus after hyphen)

**3. Full key format**:
```
registry/swift/{scope}/{name}/{version}/{path}
```
- Example: `registry/swift/apple/swift-argument-parser/1.2.0/source_archive.zip`

**4. Key Storage Strategy (CRITICAL ARCHITECTURE DECISION)**:

**S3 key = Local disk key (NO SEPARATE SHARDING)**

To maintain compatibility with the existing `S3TransferWorker` and `Cache.S3.download/1` pattern:
- Local disk path MUST match S3 key exactly
- The key returned by `Cache.Disk.artifact_path(key)` is used for both S3 operations AND local file access
- **DO NOT** add additional sharding segments to local paths that aren't in S3 keys

**Why**: The existing transfer pipeline in `cache/lib/cache/s3.ex:107-135` (`download/1`) calls:
```elixir
local_path = Disk.artifact_path(key)  # Uses key directly
ExAws.S3.download_file(bucket, key, local_path)  # Same key for S3
```
If local path differs from S3 key, downloads write to wrong location.

**Consequence**: Registry files are stored at:
- S3: `registry/swift/apple/swift-argument-parser/1.2.0/source_archive.zip`
- Local: `{storage_dir}/registry/swift/apple/swift-argument-parser/1.2.0/source_archive.zip`
- No additional scope-based sharding beyond what's in the S3 key

**Implementation**: Create `Cache.Registry.KeyNormalizer` module with:
- `normalize_scope(scope)` → downcase
- `normalize_version(version)` → semantic_version equivalent
- `package_object_key(scope, name, version, path)` → full S3/local key (same key for both)

---

## Verification Strategy (MANDATORY)

### Test Decision
- **Infrastructure exists**: YES (cache has existing test infrastructure)
- **User wants tests**: YES (TDD where applicable)
- **Framework**: ExUnit (Elixir), Swift Testing (CLI)
- **QA approach**: TDD for business logic + manual verification with real SwiftPM

### Test Patterns to Follow
- `cache/test/cache_web/controllers/cas_controller_test.exs` - Controller test structure
- `cache/test/cache/s3_test.exs` - S3 interaction mocking with **Mimic** (NOT Mox)
- `server/test/support/tuist_test_support/fixtures/registry/swift/packages_fixtures.ex` - Test data fixtures

**IMPORTANT**: Cache tests use **Mimic** for mocking, NOT Mox. All test files in `cache/test/` use `use Mimic`.

---

## Task Flow

```
0 (S3Transfer Schema) → 1 (Metadata Schema) → 2 (Metadata Module) → 3 (Leader Election) → 4 (Sync Worker) → 5 (Disk + KeyNormalizer) → 6 (API Endpoints) → 7 (Router Integration) → 8 (CLI Update) → 9 (Cloudflare Docs) → 10 (E2E Testing)
```

## Parallelization

| Group | Tasks | Reason |
|-------|-------|--------|
| A | 8, 9 | CLI and docs independent of cache implementation |
| B | 3, 5 | Leader election and disk functions independent |

| Task | Depends On | Reason |
|------|------------|--------|
| 1 | 0 | Schema needs migration first |
| 2 | 1 | Module implements schema |
| 3 | 0 | Uses S3 operations |
| 4 | 2, 3 | Sync uses metadata + leader election |
| 5 | 0 | Disk functions need artifact type |
| 6 | 2, 5 | Controller reads metadata and uses disk |
| 7 | 6 | Router assembles controller |
| 10 | 7, 8 | E2E needs all components |

---

## TODOs

- [x] 0. Add Registry Artifact Type to S3Transfer Schema

  **What to do**:
  - Update `Cache.S3Transfer` schema to include `:registry` in the Ecto.Enum values (application-level only)
  - Add `enqueue_registry_upload/1` and `enqueue_registry_download/1` functions to `Cache.S3Transfers` (takes only `key`)
  - **CRITICAL**: Registry has no account/project context. Use sentinel values:
    - `account_handle: "registry"`
    - `project_handle: "registry"`
  - **NO MIGRATION NEEDED**: The `artifact_type` column is stored as `:string` in the database (see migration `20251218084035_simplify_s3_transfers_to_key.exs`). Only the Ecto schema uses `Ecto.Enum` for application-level validation.

  **Must NOT do**:
  - Don't create a database migration (not needed - it's a string column)
  - Don't modify existing CAS/module enum values
  - Don't change existing transfer logic

  **Parallelizable**: NO (foundation for other tasks)

  **References**:
  
  **Existing Schema** (to extend):
  - `cache/lib/cache/s3_transfer.ex:18` - Current enum: `values: [:cas, :module]` - ADD `:registry`
  - `cache/lib/cache/s3_transfers.ex:20-21` - `enqueue_cas_upload` pattern to follow
  - `cache/lib/cache/s3_transfers.ex:40-41` - `enqueue_module_upload` pattern to follow
  - `cache/lib/cache/s3_transfers.ex:87-100` - Private `enqueue/5` function - registry will use sentinel values

  **Database Schema Verification** (confirms no migration needed):
  - `cache/priv/repo/migrations/20251218084035_simplify_s3_transfers_to_key.exs:14` - `add :artifact_type, :string, null: false` - it's a STRING, not a DB enum

  **Implementation Pattern for Registry**:
  ```elixir
  # In cache/lib/cache/s3_transfers.ex
  @registry_sentinel_handle "registry"
  
  def enqueue_registry_upload(key) do
    enqueue(:upload, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
  end
  
  def enqueue_registry_download(key) do
    enqueue(:download, @registry_sentinel_handle, @registry_sentinel_handle, :registry, key)
  end
  ```

  **Acceptance Criteria**:
  - [x] **NO migration created** (confirm `artifact_type` is stored as string in DB)
  - [x] `Cache.S3Transfer` schema updated: `values: [:cas, :module, :registry]`
  - [x] `Cache.S3Transfers.enqueue_registry_upload/1` function exists (takes only `key`)
  - [x] `Cache.S3Transfers.enqueue_registry_download/1` function exists (takes only `key`)
  - [x] Test: `enqueue_registry_upload("registry/swift/apple/parser/1.0.0/source_archive.zip")` succeeds
  - [x] Test: Verify inserted row has `account_handle: "registry"`, `project_handle: "registry"`
  - [x] Existing tests still pass: `mix test test/cache/s3_transfers_test.exs`
  - [x] `mix compile --warnings-as-errors` passes

  **Commit**: YES
  - Message: `feat(cache): add registry artifact type to S3Transfer schema`
  - Files: `cache/lib/cache/s3_transfer.ex`, `cache/lib/cache/s3_transfers.ex`, `cache/test/cache/s3_transfers_test.exs`
  - Pre-commit: `mix test test/cache/s3_transfers_test.exs`

---

- [x] 1. Define Registry Metadata JSON Schema

  **What to do**:
  - Create NEW FILE `cache/lib/cache/registry/metadata.ex` with schema in @moduledoc
  - Schema must support all server API responses without database:
    - Package info (scope, name, repository_full_handle)
    - All releases with versions and checksums
    - Manifest metadata (swift_version, swift_tools_version) per release
  - Include `updated_at` timestamp for staleness detection

  **Must NOT do**:
  - Don't add fields not needed for API responses
  - Don't include download counts (analytics deferred)

  **Parallelizable**: NO (depends on 0)

  **References**:
  
  **Package Schema Reference** (server Ecto schema):
  - `server/lib/tuist/registry/swift/packages/package.ex` - Package schema with fields: scope, name, repository_full_handle
  
  **Release Schema Reference** (server Ecto schema):
  - `server/lib/tuist/registry/swift/packages/package_release.ex` - PackageRelease with: version, checksum
  
  **Manifest Schema Reference** (server Ecto schema):
  - `server/lib/tuist/registry/swift/packages/package_manifest.ex` - PackageManifest with: swift_version, swift_tools_version
  
  **API Response References** (to ensure schema supports these):
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:54-66` - `list_releases` returns map of version → url
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:87-100` - `show_release` returns id, version, resources with checksum
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:186-220` - `alternate_manifests_link` iterates over manifests with swift_version

  **Schema Structure** (NEW - to be created):
  ```json
  {
    "scope": "string",
    "name": "string",
    "repository_full_handle": "string",
    "releases": {
      "<version>": {
        "checksum": "string (sha256 hex lowercase)",
        "manifests": [
          {
            "swift_version": "string | null",
            "swift_tools_version": "string | null"
          }
        ]
      }
    },
    "updated_at": "ISO8601 timestamp"
  }
  ```

  **Acceptance Criteria**:
  - [x] NEW FILE exists: `cache/lib/cache/registry/metadata.ex`
  - [x] Schema documented in module @moduledoc with JSON example
  - [x] `mix compile --warnings-as-errors` passes
  - [x] Schema includes all fields needed for `list_releases` response
  - [x] Schema includes all fields needed for `show_release` response
  - [x] Schema includes all fields needed for `alternate_manifests_link` header

  **Commit**: YES
  - Message: `feat(cache): define registry metadata JSON schema`
  - Files: `cache/lib/cache/registry/metadata.ex` (NEW)
  - Pre-commit: `mix compile --warnings-as-errors`

---

- [x] 2. Implement Registry Metadata Module

  **What to do**:
  - Extend `Cache.Registry.Metadata` module (created in Task 1) with functions:
    - `get_package(scope, name)` - fetch from Cachex, fallback to S3
    - `put_package(scope, name, metadata)` - write to S3 + invalidate cache
    - `delete_package(scope, name)` - delete from S3 + invalidate cache
    - `list_all_packages()` - list S3 prefix (for sync comparison)
  - S3 path: `registry/metadata/{scope}/{name}/index.json`
  - Cachex integration with 10 minute TTL
  - JSON encoding/decoding with Jason

  **Must NOT do**:
  - Don't connect to PostgreSQL
  - Don't cache indefinitely (must have TTL)

  **Parallelizable**: NO (depends on 1)

  **References**:
  
  **S3 Operations** (existing patterns):
  - `cache/lib/cache/s3.ex:10-14` - `presign_download_url/1` with bucket from config
  - `cache/lib/cache/s3.ex:38-48` - `exists?/1` for checking object existence
  - `cache/lib/cache/s3.ex:57-75` - `upload/1` pattern (but we need direct PUT for JSON)
  - `cache/lib/cache/s3.ex:107-135` - `download/1` pattern
  
  **Cachex Pattern** (existing):
  - `cache/lib/cache/authentication.ex:17-24` - Cachex child_spec pattern
  - `cache/lib/cache/authentication.ex:49-53` - Cachex.get with fallback pattern
  - `cache/lib/cache/authentication.ex:208-210` - Cachex.put with TTL

  **Direct S3 Operations** (for JSON read/write):
  ```elixir
  # Read JSON from S3
  bucket = Application.get_env(:cache, :s3)[:bucket]
  ExAws.S3.get_object(bucket, key) |> ExAws.request()
  
  # Write JSON to S3
  ExAws.S3.put_object(bucket, key, json_body) |> ExAws.request()
  
  # Delete from S3
  ExAws.S3.delete_object(bucket, key) |> ExAws.request()
  
  # List objects with prefix
  ExAws.S3.list_objects_v2(bucket, prefix: "registry/metadata/") |> ExAws.stream!()
  ```

  **Acceptance Criteria**:
  - [x] NEW TEST FILE: `cache/test/cache/registry/metadata_test.exs`
  - [x] `mix test test/cache/registry/metadata_test.exs` passes
  - [x] `get_package/2` returns `{:ok, metadata_map}` or `{:error, :not_found}`
  - [x] `put_package/3` writes JSON to S3 at path `registry/metadata/{scope}/{name}/index.json`
  - [x] `delete_package/2` removes from S3 and returns `:ok`
  - [x] Cachex caches successful results for 10 minutes (verify with `Cachex.ttl/2`)
  - [x] S3 mock (Mimic) verifies correct paths - use `expect(ExAws.S3, :get_object, ...)` pattern

  **Commit**: YES
  - Message: `feat(cache): implement registry metadata storage with S3 and Cachex`
  - Files: `cache/lib/cache/registry/metadata.ex`, `cache/test/cache/registry/metadata_test.exs` (NEW)
  - Pre-commit: `mix test test/cache/registry/metadata_test.exs`

---

- [x] 3. Implement Leader Election Module

  **What to do**:
  - Create NEW FILE `cache/lib/cache/registry/leader_election.ex` with:
    - `try_acquire_lock()` - attempt to become leader with proper algorithm:
      1. Try conditional PUT with `If-None-Match: "*"` 
      2. If 412 (conflict): read existing lock
      3. If expired: delete lock, retry conditional PUT
      4. Return `{:ok, :acquired}` or `{:error, :already_locked}`
    - `release_lock()` - delete lock file (only if we're the leader)
    - `is_leader?()` - check if current node holds valid (non-expired) lock
    - `current_leader()` - read lock file, return leader node name or nil
  - S3 lock file: `registry/sync/leader.lock`
  - Lock content: `{"node": "<hostname>", "acquired_at": "<iso8601>", "expires_at": "<iso8601>"}`
  - TTL: 70 minutes
  - Node identification: `System.get_env("PHX_HOST")` with fallback to `System.get_env("HOSTNAME")`

  **Tigris Consistency Mode** (CRITICAL for correctness):
  - ALL lock operations MUST use `x-tigris-consistent: true` header
  - This ensures read-after-write consistency and prevents split-brain scenarios
  - Without this, eventual consistency could cause multiple nodes to think they're leader
  - Apply to: conditional PUT, GET (read lock), DELETE

  **Must NOT do**:
  - Don't implement heartbeat/lease renewal
  - Don't wait/block for lock (fail fast)
  - Don't use `If-None-Match: "*"` alone (doesn't handle expired locks)

  **Parallelizable**: YES (independent of metadata module)

  **References**:
  
  **S3 Conditional Writes** (Tigris docs):
  - https://www.tigrisdata.com/docs/objects/conditionals/
  - `If-None-Match: "*"` - creates only if object doesn't exist (returns 412 if exists)
  - `X-Tigris-Consistent: true` - ensures consistent reads from leader

  **ExAws S3 Operations with Headers**:
  
  **CRITICAL**: ExAws operations use `%ExAws.Operation.S3{}` struct with `headers` as a **map** (not keyword list).
  
  **Standard conditional write (if_none_match)** - ExAws supports this natively:
  ```elixir
  bucket = Application.get_env(:cache, :s3)[:bucket]
  
  # ExAws.S3.put_object/4 supports if_none_match as an option
  ExAws.S3.put_object(bucket, key, body, if_none_match: "*")
  |> ExAws.request()
  # Returns {:error, {:http_error, 412, _}} if object exists
  ```
  
  **Custom Tigris header** - Modify operation struct's headers map:
  ```elixir
  # For Tigris-specific X-Tigris-Consistent header, modify the struct
  operation = ExAws.S3.put_object(bucket, key, body, if_none_match: "*")
  operation_with_tigris = %{operation | headers: Map.put(operation.headers, "x-tigris-consistent", "true")}
  ExAws.request(operation_with_tigris)
  
  # For reads with consistent flag
  read_op = ExAws.S3.get_object(bucket, key)
  read_op_consistent = %{read_op | headers: Map.put(read_op.headers, "x-tigris-consistent", "true")}
  ExAws.request(read_op_consistent)
  
  # Delete lock (use Tigris consistency for correctness)
  ExAws.S3.delete_object(bucket, key)
  |> with_tigris_consistent()
  |> ExAws.request()
  ```
  
  **Helper function pattern** (recommended):
  ```elixir
  defp with_tigris_consistent(operation) do
    %{operation | headers: Map.put(operation.headers, "x-tigris-consistent", "true")}
  end
  ```
  
  **Existing patterns in codebase** - See `cache/lib/cache/s3.ex`:
  - `ExAws.request()` without custom headers for standard operations
  - `ExAws.request(http_opts: [...])` for timeout configuration

  **Node Identification** (from CLAUDE.md environment):
  - Production cache nodes have hostname like `cache-eu-central.tuist.dev`
  - Use `System.get_env("PHX_HOST")` as primary, fallback to `HOSTNAME`

  **Acceptance Criteria**:
  - [x] NEW FILE: `cache/lib/cache/registry/leader_election.ex`
  - [x] NEW TEST FILE: `cache/test/cache/registry/leader_election_test.exs`
  - [x] `mix test test/cache/registry/leader_election_test.exs` passes
  - [x] `try_acquire_lock/0` returns `{:ok, :acquired}` when no lock exists
  - [x] `try_acquire_lock/0` returns `{:error, :already_locked}` when valid lock exists
  - [x] `try_acquire_lock/0` acquires lock when existing lock is expired (test with past expires_at)
  - [x] Lock JSON contains `node`, `acquired_at`, `expires_at` fields
  - [x] `is_leader?/0` returns `false` after TTL expires
  - [x] S3 mock (Mimic) verifies conditional write headers - use `expect(ExAws, :request, ...)` pattern

  **Commit**: YES
  - Message: `feat(cache): implement S3-based leader election for registry sync`
  - Files: `cache/lib/cache/registry/leader_election.ex` (NEW), `cache/test/cache/registry/leader_election_test.exs` (NEW)
  - Pre-commit: `mix test test/cache/registry/leader_election_test.exs`

---

- [x] 4. Implement Registry Sync Worker

  **What to do**:
  - Create NEW FILE `cache/lib/cache/registry/sync_worker.ex` as Oban worker:
    - Check leader election before sync: `LeaderElection.try_acquire_lock()`
    - If not leader: return `:ok` immediately (skip silently)
    - If leader: perform full sync, then `LeaderElection.release_lock()`
  - Create NEW FILE `cache/lib/cache/registry/create_package_release_worker.ex`:
    - Downloads source archive from GitHub
    - Extracts Package.swift manifests
    - Uploads to S3 at `registry/swift/{scope}/{name}/{version}/`
    - Updates metadata JSON
  - Port sync logic from server (adapt for S3 metadata instead of DB):
    - Fetch `packages.json` from SwiftPackageIndex
    - Compare with existing metadata in S3 via `Metadata.list_all_packages()`
    - Create new packages, delete removed packages
    - Spawn CreatePackageReleaseWorker for missing versions
  - Add GitHub token configuration to cache
  - Schedule: hourly via Oban cron with random jitter (0-5 min)

  **Must NOT do**:
  - Don't sync if not leader
  - Don't use database for any storage
  - Don't modify server's sync implementation

  **Parallelizable**: NO (depends on 2, 3)

  **References**:
  
  **Server Sync Logic** (to port):
  - `server/lib/tuist/registry/swift/workers/sync_packages_worker.ex:28-49` - perform/1 main flow
  - `server/lib/tuist/registry/swift/workers/sync_packages_worker.ex:51-63` - Fetching packages.json from GitHub
  - `server/lib/tuist/registry/swift/workers/sync_packages_worker.ex:72-89` - Package deletion logic (filter and delete)
  - `server/lib/tuist/registry/swift/workers/sync_packages_worker.ex:91-114` - Creating missing packages and finding versions
  - `server/lib/tuist/registry/swift/workers/sync_packages_worker.ex:159-173` - Spawning release workers
  
  **Server Release Worker** (to port):
  - `server/lib/tuist/registry/swift/workers/create_package_release_worker.ex:22-66` - Release creation logic
  - `server/lib/tuist/registry/swift/packages.ex:162-267` - `create_package_release` with GitHub download
  
  **Cache Oban Pattern**:
  - `cache/lib/cache/s3_transfer_worker.ex:1-29` - Oban worker structure in cache
  
  **GitHub API** (concrete implementation details):
  
  **1. SwiftPackageIndex packages.json fetch**:
  - URL: `https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json`
  - Method: `GET` with `Authorization: token {GITHUB_TOKEN_UPDATE_PACKAGES}`
  - Response: JSON array of GitHub repository URLs
  - Implementation: Use `Req.get!/2` (already a dependency in cache)
  ```elixir
  Req.get!("https://raw.githubusercontent.com/SwiftPackageIndex/PackageList/main/packages.json",
    headers: [{"authorization", "token #{token}"}]
  ).body
  ```
  
  **2. Repository tags fetch** (to find versions):
  - URL: `https://api.github.com/repos/{owner}/{repo}/tags`
  - Method: `GET` with `Authorization: token {GITHUB_TOKEN_UPDATE_PACKAGES}`
  - Response: JSON array with `name` (tag name) fields
  - Rate limit: 5000 requests/hour with auth token
  
  **3. Source archive download** (for CreatePackageReleaseWorker):
  - URL: `https://github.com/{owner}/{repo}/archive/refs/tags/{tag}.zip`
  - Method: `GET` with `Authorization: token {GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES}`
  - Response: ZIP binary (stream to temp file)
  - Implementation:
  ```elixir
  {:ok, tmp_path} = Briefly.create()
  Req.get!(archive_url, headers: [{"authorization", "token #{token}"}], into: File.stream!(tmp_path))
  ```
  
  **4. Manifest extraction** (pure Elixir, no system tools):
  - Use `:zip` Erlang module (built-in, no external dependency)
  - Extract `Package.swift` and `Package@swift-*.swift` files
  ```elixir
  {:ok, files} = :zip.unzip(String.to_charlist(zip_path), [:memory, {:file_filter, &manifest_file?/1}])
  # files is [{~c"path/Package.swift", binary}, ...]
  ```
  - No `git`, `unzip`, or other system tools needed
  
  **Rate Limit Handling**:
  - Check `X-RateLimit-Remaining` header after each request
  - If below threshold (e.g., 100), sleep until `X-RateLimit-Reset` timestamp
  - Log warnings when approaching limits

  **Oban Cron Configuration with Jitter**:
  ```elixir
  # In config/config.exs
  config :cache, Oban,
    queues: [default: 10, s3_transfers: 5, registry: 2],
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {"0 * * * *", Cache.Registry.SyncWorker}
       ]}
    ]
  ```
  
  **Jitter Implementation** (inside worker, NOT in cron config):
  ```elixir
  # At start of perform/1, before acquiring lock:
  jitter_ms = :rand.uniform(300_000)  # 0-5 minutes in milliseconds
  Process.sleep(jitter_ms)
  ```
  This spreads out sync attempts across nodes to reduce lock contention.

  **Acceptance Criteria**:
  - [x] NEW FILE: `cache/lib/cache/registry/sync_worker.ex`
  - [x] NEW FILE: `cache/lib/cache/registry/create_package_release_worker.ex`
  - [x] NEW TEST FILE: `cache/test/cache/registry/sync_worker_test.exs`
  - [x] `mix test test/cache/registry/sync_worker_test.exs` passes
  - [x] Worker returns `:ok` immediately when `LeaderElection.try_acquire_lock()` fails
  - [x] Worker acquires lock at start, releases at end
  - [x] New packages create metadata JSON in S3
  - [x] Removed packages delete metadata JSON from S3
  - [x] Missing versions spawn `CreatePackageReleaseWorker` jobs
  - [x] Oban cron configured for hourly runs in `cache/config/config.exs`
  - [x] Jitter implemented inside worker: `Process.sleep(:rand.uniform(300_000))` before lock acquisition
  - [x] `GITHUB_TOKEN_UPDATE_PACKAGES` and `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES` env vars read from config

  **Commit**: YES
  - Message: `feat(cache): implement registry sync worker with leader election`
  - Files: `cache/lib/cache/registry/sync_worker.ex` (NEW), `cache/lib/cache/registry/create_package_release_worker.ex` (NEW), `cache/test/cache/registry/sync_worker_test.exs` (NEW), `cache/config/config.exs`, `cache/config/runtime.exs`
  - Pre-commit: `mix test test/cache/registry/sync_worker_test.exs`

---

- [x] 5. Add Registry Functions to Cache.Disk and Key Normalizer

  **What to do**:
  - CREATE NEW FILE `cache/lib/cache/registry/key_normalizer.ex` with:
    - `normalize_scope(scope)` - downcase scope
    - `normalize_version(version)` - semantic version normalization (match server exactly)
    - `package_object_key(scope, name, opts)` - construct S3 key (match server's function)
  - EXTEND EXISTING `cache/lib/cache/disk.ex` with registry functions:
    - `registry_key(scope, name, version, filename)` - construct normalized key (same as S3 key)
    - `registry_exists?(scope, name, version, filename)` - check local disk
    - `registry_put(scope, name, version, filename, data)` - write to disk
    - `registry_stat(scope, name, version, filename)` - get file stat
    - `registry_local_accel_path(scope, name, version, filename)` - nginx path
  - Follow existing patterns from `cas_*` and `module_*` functions
  - **CRITICAL**: Use `KeyNormalizer` for all key construction to ensure S3 compatibility

  **Must NOT do**:
  - Don't modify existing CAS/module functions
  - Don't break existing tests
  - Don't deviate from server's key normalization rules

  **Parallelizable**: YES (independent of metadata, parallel with leader election)

  **References**:
  
  **Server Key Normalization** (MUST MATCH EXACTLY):
  - `server/lib/tuist/registry/swift/packages.ex:468-485` - `package_object_key/2`:
    ```elixir
    def package_object_key(%{scope: scope, name: name}, opts \\ []) do
      # ... downcases scope/name, applies semantic_version to version
    end
    ```
  - `server/lib/tuist/registry/swift/packages.ex:135-150` - `semantic_version/1`:
    - Strips leading `v`: `"v1.2.3"` → `"1.2.3"`
    - Adds trailing zeros: `"1"` → `"1.0.0"`, `"1.2"` → `"1.2.0"`
    - Pre-release: `"1.0.0-alpha.1"` → `"1.0.0-alpha+1"` (dot→plus)
  - `server/lib/tuist/registry/swift/packages.ex:154-160` - `add_trailing_semantic_version_zeros/1`

  **Existing Disk Functions** (patterns to follow):
  - `cache/lib/cache/disk.ex:19-24` - `cas_exists?` pattern
  - `cache/lib/cache/disk.ex:42-61` - `cas_put` pattern (both file and binary)
  - `cache/lib/cache/disk.ex:71-73` - `artifact_path` pattern
  - `cache/lib/cache/disk.ex:86-89` - `cas_key` with sharding
  - `cache/lib/cache/disk.ex:91-93` - `shards_for_id` sharding logic
  - `cache/lib/cache/disk.ex:101-103` - `cas_local_accel_path` pattern
  - `cache/lib/cache/disk.ex:140-145` - `cas_stat` pattern

  **Key Format** (S3 key = Local key):
  - **CRITICAL**: S3 key and local disk key MUST be identical to work with existing S3TransferWorker
  - Format: `registry/swift/{scope}/{name}/{version}/{path}` (all downcased, version normalized)
  - Example: `registry/swift/apple/swift-argument-parser/1.2.0/source_archive.zip`
  - **NO additional sharding** beyond what's in the key (unlike CAS which adds hash-based subdirs)
  
  **Why no separate sharding**:
  - `Cache.S3.download/1` uses `Disk.artifact_path(key)` for local path AND `key` for S3
  - If they differ, downloads write to wrong location and disk checks fail
  - Registry scope names provide natural distribution (thousands of unique scopes)

  **Acceptance Criteria**:
  - [x] NEW FILE: `cache/lib/cache/registry/key_normalizer.ex`
  - [x] NEW TEST FILE: `cache/test/cache/registry/key_normalizer_test.exs`
  - [x] `cache/lib/cache/disk.ex` extended with `registry_*` functions
  - [x] **Normalization tests**:
    - `KeyNormalizer.normalize_version("v1.2.3")` → `"1.2.3"`
    - `KeyNormalizer.normalize_version("1")` → `"1.0.0"`
    - `KeyNormalizer.normalize_version("1.0.0-alpha.1")` → `"1.0.0-alpha+1"`
  - [x] **Key generation tests**:
    - `KeyNormalizer.package_object_key(%{scope: "Apple", name: "Parser"}, version: "v1.2", path: "source_archive.zip")` → `"registry/swift/apple/parser/1.2.0/source_archive.zip"`
  - [x] **Disk function tests**:
    - `registry_key("Apple", "Parser", "v1.2", "source_archive.zip")` → `"registry/swift/apple/parser/1.2.0/source_archive.zip"` (same as S3 key)
    - `registry_exists?` returns boolean
    - `registry_put` writes file to correct path
    - `registry_local_accel_path` returns `/internal/local/registry/swift/...`
  - [x] `mix test test/cache/registry/key_normalizer_test.exs` passes
  - [x] `mix test test/cache/disk_test.exs` passes
  - [x] Existing CAS/module tests still pass

  **Commit**: YES
  - Message: `feat(cache): add registry key normalizer and disk storage functions`
  - Files: `cache/lib/cache/registry/key_normalizer.ex` (NEW), `cache/test/cache/registry/key_normalizer_test.exs` (NEW), `cache/lib/cache/disk.ex`
  - Pre-commit: `mix test`

---

- [x] 6. Implement Registry API Endpoints

  **What to do**:
  - Create NEW FILE `cache/lib/cache_web/controllers/registry_controller.ex` with endpoints:
    - `GET /api/registry/swift` - availability (return 200, empty body, NO content-version header)
    - `GET /api/registry/swift/availability` - same as above (server has both routes)
    - `GET /api/registry/swift/identifiers?url=...` - lookup by repo URL, return identifiers (see URL Parsing below)
    - `GET /api/registry/swift/:scope/:name` - list releases (404 with MESSAGE if package not found)
    - `GET /api/registry/swift/:scope/:name/:version` - show release OR download if ends with `.zip` (404 with EMPTY `{}` if release not found)
    - `GET /api/registry/swift/:scope/:name/:version/Package.swift` - manifest with `?swift-version=` support
    - `POST /api/registry/swift/login` - return 200 (no-op)
  - Response format must match server exactly:
    - `content-version: 1` header on all responses EXCEPT availability
    - JSON structure matches server responses
  - Implement two-tier storage for downloads:
    1. Check local disk via `Cache.Disk.registry_exists?`
    2. If hit: serve via nginx X-Accel-Redirect to `/internal/local/...`
    3. If miss: enqueue S3 download + serve presigned URL via nginx proxy `/internal/remote/...`
  - Implement manifest variant selection (303 redirect when requested variant missing)
  - Implement `alternate_manifests_link` header with SwiftPM workaround

  **Must NOT do**:
  - Don't add authentication
  - Don't add analytics events
  - Don't add `content-version` header to availability endpoint (server doesn't)

  **Parallelizable**: NO (depends on 2, 5)

  **References**:
  
  **Server Controller** (exact behavior to match):
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:20-21` - `availability` returns `send_resp(200, [])` with NO headers
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:24-51` - `identifiers` with content-version header
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:54-66` - `list_releases` response shape
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:69-102` - `show_release` with .zip suffix branching
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:105-155` - `show_package_swift` with swift-version and 303 redirect
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:158-183` - `package_manifest_object_key` manifest variant selection
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:186-220` - `alternate_manifests_link` with SwiftPM workaround (padding .0)
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:222-269` - `download_release` streaming
  - `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:298-303` - `login` returns 200

  **404 Response Body Distinction** (CRITICAL - server uses different bodies):
  - **Package not found via `assign_package` plug** (list_releases, show_release, show_package_swift): `404` with `{"message": "The package {scope}/{name} was not found in the registry."}` + `content-version: 1`
  - **Package not found via identifiers**: `404` with `{"message": "The package {url} was not found in the registry."}` + `content-version: 1` (uses original URL, not scope/name)
  - **Release not found** (show_release when package exists but version doesn't): `404` with `{}` (empty object) + `content-version: 1`
  - Cache must reproduce this exact split behavior

  **Two-Tier Pattern** (from CAS controller):
  - `cache/lib/cache_web/controllers/cas_controller.ex:51-91` - download with disk check, S3 fallback
  - `cache/lib/cache/s3.ex:10-14` - `presign_download_url/1`
  - `cache/lib/cache/s3.ex:24-36` - `remote_accel_path/1` for nginx proxy

  **Identifiers URL Parsing** (MUST implement in `Cache.Registry.URLParser`):
  
  The `identifiers` endpoint receives a GitHub URL and must extract `{scope, name}`.
  
  **CRITICAL**: Response behavior MUST MATCH SERVER EXACTLY (see `server/lib/tuist_web/controllers/api/registry/swift_controller.ex:24-51`):
  
  **Success case**:
  - GitHub URL + package found → `200 OK` with `{"identifiers": ["scope.name"]}` + `content-version: 1`
  
  **Error cases** (MUST return errors, NOT empty arrays - match server's `Tuist.VCS` behavior):
  - Non-GitHub URL (GitLab, bare strings like "invalid", etc.) → `404 Not Found` with `{"message": "The package {url} was not found in the registry."}` + `content-version: 1` (server treats as `:unsupported_vcs`)
  - GitHub URL but invalid path format → `400 Bad Request` with `{"message": "Invalid repository URL: {url}"}` + `content-version: 1` (only when URL is GitHub-shaped but handle extraction fails)
  - Package not in registry → `404 Not Found` with `{"message": "The package {url} was not found in the registry."}` + `content-version: 1`
  
  **Supported URL formats** (all must work for GitHub):
  ```
  https://github.com/apple/swift-argument-parser
  https://github.com/apple/swift-argument-parser.git
  git@github.com:apple/swift-argument-parser.git
  ssh://git@github.com/apple/swift-argument-parser.git
  ```
  
  **Parsing algorithm** (mirrors `server/lib/tuist/vcs.ex` behavior):
  ```elixir
  def parse_repository_url(url) do
    # Step 1: Normalize URL (handle SSH, strip .git)
    normalized = url
      |> String.trim_trailing(".git")
      |> normalize_ssh_to_https()
    
    # Step 2: Check provider (must be GitHub)
    case URI.parse(normalized) do
      %URI{host: "github.com", path: "/" <> path} ->
        # Step 3: Extract owner/repo from path
        case String.split(path, "/") do
          [owner, repo] when owner != "" and repo != "" -> 
            {:ok, :github, %{scope: String.downcase(owner), name: String.downcase(repo)}}
          _ -> 
            # GitHub URL but malformed path → invalid_repository_url → 400
            {:error, :invalid_repository_url}
        end
      _ ->
        # Not GitHub (includes bare strings, GitLab, etc.) → unsupported_vcs → 404
        {:error, :unsupported_vcs}
    end
  end
  
  defp normalize_ssh_to_https("git@github.com:" <> path), do: "https://github.com/" <> path
  defp normalize_ssh_to_https("ssh://git@github.com/" <> path), do: "https://github.com/" <> path
  defp normalize_ssh_to_https(url), do: url
  ```
  
  **Key behavior** (matches `Tuist.VCS`):
  - `"invalid"` → `URI.parse/1` gives `%URI{host: nil}` → NOT github.com → `:unsupported_vcs` → **404**
  - `"https://gitlab.com/foo/bar"` → host is gitlab.com → NOT github.com → `:unsupported_vcs` → **404**
  - `"https://github.com/apple"` → GitHub but only 1 path segment → `:invalid_repository_url` → **400**
  - `"https://github.com/apple/parser"` → GitHub + valid path → **200** with identifiers
  
  **Controller logic** (MUST match server's `Tuist.VCS` semantics):
  ```elixir
  def identifiers(conn, %{"url" => url}) do
    with {:ok, :github, %{scope: scope, name: name}} <- URLParser.parse_repository_url(url),
         {:ok, _metadata} <- Metadata.get_package(scope, name) do
      conn
      |> put_resp_header("content-version", "1")
      |> json(%{identifiers: ["#{scope}.#{name}"]})
    else
      {:error, :invalid_repository_url} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:bad_request)
        |> json(%{message: "Invalid repository URL: #{url}"})
      
      {:error, :unsupported_vcs} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{message: "The package #{url} was not found in the registry."})
      
      {:error, :not_found} ->
        conn
        |> put_resp_header("content-version", "1")
        |> put_status(:not_found)
        |> json(%{message: "The package #{url} was not found in the registry."})
    end
  end
  ```
  
  **URL Parsing MUST match server's `Tuist.VCS` behavior**:
  - Reference: `server/lib/tuist/vcs.ex` - `get_provider_from_repository_url/1` and `get_repository_full_handle_from_url/1`
  - Port the exact parsing logic or validate against server test cases
  - Key distinction: `:invalid_repository_url` (malformed) vs `:unsupported_vcs` (valid URL but not GitHub)

  **Acceptance Criteria**:
  - [x] NEW FILE: `cache/lib/cache_web/controllers/registry_controller.ex`
  - [x] NEW TEST FILE: `cache/test/cache_web/controllers/registry_controller_test.exs`
  - [x] `mix test test/cache_web/controllers/registry_controller_test.exs` passes
  - [x] `GET /api/registry/swift` returns 200 with empty body, NO `content-version` header
  - [x] `GET /api/registry/swift/availability` returns 200 with empty body, NO `content-version` header
  - [x] `GET /api/registry/swift/identifiers?url=https://github.com/apple/swift-argument-parser` returns `200` with `{"identifiers": ["apple.swift-argument-parser"]}` + `content-version: 1`
  - [x] `GET /api/registry/swift/identifiers?url=https://github.com/Apple/Parser.git` correctly downcases and strips `.git`
  - [x] `GET /api/registry/swift/identifiers?url=git@github.com:apple/parser.git` handles SSH URL format
  - [x] `GET /api/registry/swift/identifiers?url=https://gitlab.com/foo/bar` returns `404` with `{"message": "The package ... was not found..."}` (non-GitHub)
  - [x] `GET /api/registry/swift/identifiers?url=invalid` returns `404` with `{"message": "The package invalid was not found in the registry."}` (matches server's unsupported_vcs behavior)
  - [x] `GET /api/registry/swift/identifiers?url=https://github.com/unknown/repo` returns `404` with not found message (package not in registry)
  - [x] `GET /api/registry/swift/apple/swift-argument-parser` returns releases map with `content-version: 1`
  - [x] `GET /api/registry/swift/apple/swift-argument-parser/1.2.0` returns release info with checksum
  - [x] `GET /api/registry/swift/unknown/package` returns `404` with `{"message": "The package unknown/package was not found..."}` (package-level 404)
  - [x] `GET /api/registry/swift/apple/swift-argument-parser/99.99.99` returns `404` with `{}` (release-level 404, empty body)
  - [x] `GET /api/registry/swift/apple/swift-argument-parser/1.2.0.zip` serves source archive via two-tier
  - [x] Manifest endpoint with `?swift-version=5.7` returns 303 redirect if variant missing
  - [x] Manifest endpoint returns `link` header with alternate manifests (with `.0` padding)
  - [x] `POST /api/registry/swift/login` returns 200 with `content-version: 1`
  - [x] Cache hit: response includes `x-accel-redirect` header starting with `/internal/local/`
  - [x] Cache miss: S3 download enqueued, response includes `x-accel-redirect` to `/internal/remote/`

  **Commit**: YES
  - Message: `feat(cache): implement registry API endpoints with two-tier storage`
  - Files: `cache/lib/cache_web/controllers/registry_controller.ex` (NEW), `cache/test/cache_web/controllers/registry_controller_test.exs` (NEW)
  - Pre-commit: `mix test test/cache_web/controllers/registry_controller_test.exs`

---

- [x] 7. Integrate Registry into Router and Application

  **What to do**:
  - MODIFY `cache/lib/cache_web/router.ex` to add:
    1. **New pipeline** for SwiftPM Accept headers (CRITICAL for SwiftPM compatibility)
    2. Registry routes using the new pipeline
    
    ```elixir
    # Add new pipeline for SwiftPM registry (REQUIRED - SwiftPM sends specific Accept headers)
    pipeline :api_registry_swift do
      plug :accepts, ["swift-registry-v1-json", "swift-registry-v1-zip", "swift-registry-v1-api", "json"]
    end
    
    scope "/api/registry/swift", CacheWeb do
      pipe_through [:api_registry_swift, :open_api]
      # No :project_auth - registry is public
      
      get "/", RegistryController, :availability
      get "/availability", RegistryController, :availability
      get "/identifiers", RegistryController, :identifiers
      get "/:scope/:name", RegistryController, :list_releases
      get "/:scope/:name/:version", RegistryController, :show_release
      get "/:scope/:name/:version/Package.swift", RegistryController, :show_package_swift
      post "/login", RegistryController, :login
    end
    ```
  - MODIFY `cache/lib/cache/application.ex` to add Cachex for registry metadata
  - MODIFY `cache/config/config.exs` to add Oban queue `:registry`
  - MODIFY `cache/config/runtime.exs` to read GitHub token env vars

  **Must NOT do**:
  - Don't add authentication pipeline
  - Don't modify existing CAS/module routes
  - Don't use `:api_json` pipeline (will cause 406 Not Acceptable for SwiftPM requests)

  **Parallelizable**: NO (depends on 6)

  **References**:
  
  **Server Registry Pipeline** (MUST MATCH Accept headers):
  - `server/lib/tuist_web/router.ex:123-128` - Server's `:api_registry_swift` pipeline:
    ```elixir
    pipeline :api_registry_swift do
      plug :accepts, ["swift-registry-v1-json", "swift-registry-v1-zip", "swift-registry-v1-api"]
      # ... other plugs
    end
    ```
  - **CRITICAL**: SwiftPM sends `Accept: application/vnd.swift.registry.v1+json` which Phoenix normalizes to `swift-registry-v1-json`
  - Without this pipeline, cache will return **406 Not Acceptable** for SwiftPM requests
  
  **Existing Router** (to extend):
  - `cache/lib/cache_web/router.ex:44-63` - Existing route structure with pipelines
  - `cache/lib/cache_web/router.ex:49-63` - CAS/module routes under `/api/cache`
  
  **Server Routes** (must match paths):
  - `server/lib/tuist_web/router.ex:466-475` - Server registry routes
  - `server/lib/tuist_web/router.ex:493` - Additional availability route at `/api/registry/swift`

  **Application Supervisor** (to extend):
  - `cache/lib/cache/application.ex` - Supervisor children list

  **Cachex Child Spec Pattern**:
  - `cache/lib/cache/authentication.ex:17-24` - `child_spec` for Cachex

  **Acceptance Criteria**:
  - [x] `mix compile --warnings-as-errors` passes
  - [x] New pipeline `:api_registry_swift` created with SwiftPM Accept types
  - [x] `GET /api/registry/swift` returns 200 (route works)
  - [x] `GET /api/registry/swift/availability` returns 200 (both routes work)
  - [x] **SwiftPM compatibility test**: `curl -H "Accept: application/vnd.swift.registry.v1+json" http://localhost:4000/api/registry/swift` returns 200 (NOT 406)
  - [x] Routes do NOT go through `:project_auth` pipeline
  - [x] Cachex `:registry_metadata_cache` started (check in IEx)
  - [x] Oban queue `:registry` configured
  - [x] `GITHUB_TOKEN_UPDATE_PACKAGES` env var documented in runtime.exs comments
  - [x] `GITHUB_TOKEN_UPDATE_PACKAGE_RELEASES` env var documented in runtime.exs comments

  **Commit**: YES
  - Message: `feat(cache): integrate registry into router and application`
  - Files: `cache/lib/cache_web/router.ex`, `cache/lib/cache/application.ex`, `cache/config/config.exs`, `cache/config/runtime.exs`
  - Pre-commit: `mix compile --warnings-as-errors`

---

- [x] 8. Update CLI Registry Setup

  **What to do**:
  - MODIFY `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift`:
    - Change registry URL from `{serverURL}/api/registry/swift` to `https://registry.tuist.dev/api/registry/swift`
    - Keep authentication host as `tuist.dev` (server still handles login)
  - The `registryConfigurationJSON` function at line 115-143 needs update

  **Must NOT do**:
  - Don't remove support for self-hosted scenarios (check if custom server URL)
  - Don't change authentication flow

  **Parallelizable**: YES (with task 9)

  **References**:
  
  **Existing Implementation**:
  - `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift:115-143` - `registryConfigurationJSON` function
  - `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift:128` - Authentication host: `serverURL.host()`
  - `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift:136` - Registry URL: `{serverURL}/api/registry/swift`

  **Updated Logic**:
  ```swift
  // If serverURL is tuist.dev (production), use registry.tuist.dev
  // Otherwise (self-hosted), use serverURL directly
  let registryHost = if serverURL.host() == "tuist.dev" {
      "registry.tuist.dev"
  } else {
      serverURL.host() ?? "tuist.dev"
  }
  let registryURL = "https://\(registryHost)/api/registry/swift"
  ```

  **Build Command** (from CLAUDE.md):
  - `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace`

  **Acceptance Criteria**:
  - [x] Build succeeds: `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace`
  - [x] For production (tuist.dev): `registries.json` contains `"url": "https://registry.tuist.dev/api/registry/swift"`
  - [x] For self-hosted: `registries.json` uses the provided server URL
  - [x] Authentication host is `tuist.dev` for production (server handles login)
  - [x] `tuist registry login` still works with new config

  **Commit**: YES
  - Message: `feat(cli): update registry setup for cache-based registry URL`
  - Files: `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift`
  - Pre-commit: `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace`

---

- [x] 9. Create Cloudflare Configuration Documentation

  **What to do**:
  - Create NEW FILE `docs/cloudflare-registry-setup.md` with step-by-step instructions:
    1. Create DNS record for `registry.tuist.dev` (proxied, A or CNAME)
    2. Create Load Balancer named `registry.tuist.dev`
    3. Create 4 origin pools (one per region)
    4. Configure HTTP health checks (GET `/up`, expect 200)
    5. Configure geo-steering region mappings
    6. Configure failover order
    7. Verify setup

  **Must NOT do**:
  - Don't automate Cloudflare configuration
  - Don't include API keys or secrets in documentation

  **Parallelizable**: YES (with task 8)

  **References**:
  
  **Cloudflare Documentation**:
  - Geo steering: https://developers.cloudflare.com/load-balancing/understand-basics/traffic-steering/steering-policies/geo-steering
  - Load balancing: https://developers.cloudflare.com/load-balancing/
  - Health checks: https://developers.cloudflare.com/load-balancing/monitors/
  - Region codes: https://developers.cloudflare.com/load-balancing/reference/region-mapping-api/#list-of-load-balancer-regions
  
  **Cache Node Hostnames**:
  - `cache/config/deploy.production.yml:4-7`:
    - `cache-eu-central.tuist.dev`
    - `cache-us-east.tuist.dev`  
    - `cache-us-west.tuist.dev`
    - `cache-ap-southeast.tuist.dev`
  
  **Health Check Endpoint**:
  - `cache/lib/cache_web/router.ex:41` - `get "/up", UpController, :index`

  **Acceptance Criteria**:
  - [x] NEW FILE exists: `docs/cloudflare-registry-setup.md`
  - [x] Document includes numbered step-by-step instructions
  - [x] All 4 origin pools documented with exact hostnames
  - [x] Geo-steering region mapping documented using valid Cloudflare region codes:
    - `WEU` (Western Europe) → `cache-eu-central.tuist.dev`
    - `ENAM` (Eastern North America) → `cache-us-east.tuist.dev`
    - `WNAM` (Western North America) → `cache-us-west.tuist.dev`
    - `SEAS` (Southeast Asia) → `cache-ap-southeast.tuist.dev`
  - [x] Health check configuration documented (path, interval, timeout, expected codes)
  - [x] Failover behavior documented
  - [x] Verification steps included

  **Commit**: YES
  - Message: `docs(cache): add Cloudflare configuration guide for registry load balancing`
  - Files: `docs/cloudflare-registry-setup.md` (NEW)
  - Pre-commit: N/A (documentation only)

---

- [x] 10. End-to-End Testing with Real SwiftPM

  **What to do**:
  - Create NEW FILE `docs/registry-e2e-testing.md` with manual test procedure:
    1. Start local cache server with test S3/MinIO
    2. Run `tuist registry setup` pointing to local cache
    3. Create test Swift package with registry dependency
    4. Run `swift package resolve`
    5. Verify package downloaded correctly
  - Test scenarios to document:
    - Package exists in registry → resolves successfully
    - Package not in registry → appropriate error message
    - Cold cache → first request slower (S3 fetch)
    - Warm cache → second request fast (verify via logs or response time)

  **Must NOT do**:
  - Don't test against production Cloudflare
  - Don't modify production data

  **Parallelizable**: NO (depends on 7, 8)

  **References**:
  
  **Test Environment Setup**:
  - Run cache locally: `cd cache && mix phx.server`
  - MinIO for local S3: `docker run -p 9000:9000 minio/minio server /data`
  
  **SwiftPM Test Project**:
  ```swift
  // Package.swift
  // swift-tools-version: 5.9
  import PackageDescription
  let package = Package(
      name: "RegistryTest",
      dependencies: [
          .package(id: "apple.swift-argument-parser", from: "1.2.0")
      ],
      targets: [
          .executableTarget(name: "RegistryTest", dependencies: [
              .product(name: "ArgumentParser", package: "apple.swift-argument-parser")
          ])
      ]
  )
  ```

  **Verification Signals** (for warm vs cold cache):
  - Cold: Cache logs show "S3 download for artifact" 
  - Warm: Cache logs show "disk hit" or no S3 download log
  - Alternative: Check `/internal/local/` vs `/internal/remote/` in nginx logs

  **Acceptance Criteria**:
  - [x] NEW FILE exists: `docs/registry-e2e-testing.md`
  - [x] Document includes local test environment setup steps
  - [x] Document includes sample Package.swift for testing
  - [x] Document includes verification commands for each scenario
  - [x] Cold cache scenario: document how to verify S3 fetch occurred
  - [x] Warm cache scenario: document how to verify local disk serve occurred
  - [x] Error scenarios documented

  **Commit**: YES
  - Message: `docs: add E2E testing guide for registry`
  - Files: `docs/registry-e2e-testing.md` (NEW)
  - Pre-commit: N/A (documentation only)

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 0 | `feat(cache): add registry artifact type to S3Transfer` | s3_transfer.ex, s3_transfers.ex, s3_transfers_test.exs | `mix test` |
| 1 | `feat(cache): define registry metadata JSON schema` | metadata.ex | `mix compile` |
| 2 | `feat(cache): implement registry metadata storage` | metadata.ex, test | `mix test` |
| 3 | `feat(cache): implement S3-based leader election` | leader_election.ex, test | `mix test` |
| 4 | `feat(cache): implement registry sync worker` | sync_worker.ex, release_worker.ex, test | `mix test` |
| 5 | `feat(cache): add registry disk storage functions` | disk.ex | `mix test` |
| 6 | `feat(cache): implement registry API endpoints` | registry_controller.ex, test | `mix test` |
| 7 | `feat(cache): integrate registry into router` | router.ex, application.ex, config | `mix compile` |
| 8 | `feat(cli): update registry setup URL` | RegistrySetupCommandService.swift | `xcodebuild` |
| 9 | `docs: Cloudflare registry setup guide` | cloudflare-registry-setup.md | N/A |
| 10 | `docs: registry E2E testing guide` | registry-e2e-testing.md | N/A |

---

## Success Criteria

### Verification Commands
```bash
# Cache builds without errors
cd cache && mix compile --warnings-as-errors

# Cache tests pass
cd cache && mix test

# CLI builds without errors  
cd cli && xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace

# Local smoke test (after starting cache with test data)
curl -I http://localhost:4000/api/registry/swift
# Expected: HTTP/1.1 200 OK
```

### Final Checklist
- [x] All "Must Have" requirements implemented
- [x] All "Must NOT Have" guardrails respected
- [x] All API endpoints match server behavior exactly (verified by tests)
- [x] Leader election prevents concurrent syncs (verified by tests)
- [x] Two-tier storage working for all artifacts (verified by tests)
- [x] CLI generates correct registry URL
- [x] Cloudflare documentation complete
- [x] E2E testing documentation complete
