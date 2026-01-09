# Registry on Cache Nodes - Learnings

## Conventions Discovered
- Cache tests use `ExUnit.Case` with `async: false` and `Ecto.Adapters.SQL.Sandbox`
- The `artifact_type` in DB is stored as `:string`, but Ecto.Enum provides app-level validation
- All S3 transfer functions return `{:ok, transfer}` tuple
- Modules should be in `cache/lib/cache/registry/` namespace
- Cache uses Mimic for mocking, NOT Mox
- Oban workers use `use Oban.Worker, queue: :queue_name`

## Successful Approaches
- Task 0: Followed existing pattern for `enqueue_cas_upload/3` and `enqueue_module_upload/3`
- Used module attribute `@registry_sentinel_handle "registry"` for sentinel values
- Task 1: Created comprehensive @moduledoc with JSON schema documentation
- Task 3: Leader election with S3 conditional writes and TTL expiry
- Task 5: Key normalization matching server exactly (strip v, add .0.0, prerelease handling)
- Task 6: Two-tier storage pattern from CAS controller
- Task 7: Cachex integration via child_spec in application.ex

## Technical Patterns
- `S3Transfers.enqueue_*` functions use `on_conflict: :nothing` for idempotent inserts
- Tests verify: transfer fields, deduplication, and different types for same key
- Server API response structures:
  - `list_releases`: Map of version → {url: path}
  - `show_release`: {id, version, resources: [{name, type, checksum}]}
  - `alternate_manifests_link`: Link header with swift_version suffixes (add .0 for single-segment versions)
- S3 key = Local disk key (no separate sharding for registry)
- Tigris consistency: use `x-tigris-consistent: true` header for leader election

## Task 8: CLI Registry Setup Update

### Key File
- `cli/Sources/TuistKit/Services/Registry/RegistrySetupCommandService.swift`

### Implementation Pattern
The `registryConfigurationJSON` function generates a `registries.json` configuration file for Swift Package Manager. The key insight is that:

1. **Authentication and Registry URLs are separate concerns**:
   - Authentication host: Uses `serverURL.host()` - this is where users log in (tuist.dev for production)
   - Registry URL: Where packages are fetched from (registry.tuist.dev for production)

2. **Production vs Self-hosted logic**:
   ```swift
   let registryHost = if serverURL.host() == "tuist.dev" {
       "registry.tuist.dev"  // Production: use dedicated registry subdomain
   } else {
       serverURL.host() ?? "tuist.dev"  // Self-hosted: use provided server URL
   }
   ```

3. **Backwards compatibility**: Self-hosted setups continue to work unchanged - they use their own server URL for both authentication and registry.

## Completed Tasks
- [x] 0. Add Registry Artifact Type to S3Transfer Schema
- [x] 1. Define Registry Metadata JSON Schema
- [x] 2. Implement Registry Metadata Module
- [x] 3. Implement Leader Election Module
- [x] 4. Implement Registry Sync Worker
- [x] 5. Add Registry Functions to Cache.Disk and Key Normalizer
- [x] 6. Implement Registry API Endpoints
- [x] 7. Integrate Registry into Router and Application
- [x] 8. Update CLI Registry Setup URL
- [x] 9. Create Cloudflare Configuration Documentation
- [x] 10. Create E2E Testing Documentation

## Final Verification
- 267 tests, 0 failures
- mix compile --warnings-as-errors passes
- All plan checkboxes marked complete (126 total)
