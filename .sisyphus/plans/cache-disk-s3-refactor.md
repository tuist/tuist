# Cache Disk Module Domain Split Refactoring

## TL;DR

> **Quick Summary**: Split the monolithic `Cache.Disk` (587 lines) into 4 domain-specific modules (`Cache.CAS.Disk`, `Cache.Module.Disk`, `Cache.Gradle.Disk`, `Cache.Registry.Disk`) while keeping shared infrastructure in the base `Cache.Disk`. Do NOT split `Cache.S3` — it has zero domain-specific functions.
> 
> **Deliverables**:
> - 4 new domain disk modules with simplified function names
> - Slimmed-down `Cache.Disk` with only shared helpers (now public)
> - Updated callers (4 controllers, tests)
> - 4 new domain-specific test files
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 2 waves (after shared prep)
> **Critical Path**: Prep (helpers public) → CAS extraction → Module extraction → remaining domains

---

## Context

### Original Request
Split `Cache.Disk` and `Cache.S3` into domain-specific modules since they grew organically. Domain-specific disk/S3 functions should live in their respective domain directories.

### Interview Summary
**Key Discussions**:
- All 4 domains (CAS, Module, Gradle, Registry) get domain-specific disk modules
- Shared helpers stay in `Cache.Disk` base module as public functions
- Tests move to match new module structure

**Research Findings**:
- `Cache.Disk` has 5 clear function groups: CAS (6 fns), Module (7 fns including `put_from_parts`), Gradle (5 fns), Registry (5 fns), Shared infra (6+ fns)
- Each domain repeats identical patterns: key→path→exists/stat/put, ensure_directory→move_file, accel_path
- `Cache.S3` has NO domain-specific functions — all 9 public functions are generic, operating on keys and bucket types via `:type` option
- S3TransferWorker, DiskEvictionWorker, CleanProjectWorker only use shared Disk functions

### Metis Review
**Identified Gaps** (addressed):
- **S3 has no domain-specific functions** → Dropped S3 split entirely. S3 stays as-is.
- **`shards_for_id`, `ensure_directory`, `move_file` are private** → Must be promoted to public before extraction.
- **Mimic copies needed in test_helper.exs** → Added explicit task for this.
- **No Gradle controller test exists** → Noted as known gap, not blocking.
- **`xcode_cas_get_local_path/3` was omitted** → Included in CAS extraction.
- **`module_put_from_parts/6` + `copy_parts_to_file/2` are complex** → Module gets special attention.

---

## Work Objectives

### Core Objective
Extract domain-specific disk functions from the monolithic `Cache.Disk` module into 4 domain modules, simplifying function names and improving code organization, while maintaining full backward compatibility of shared infrastructure functions.

### Concrete Deliverables
- `cache/lib/cache/cas/disk.ex` — `Cache.CAS.Disk` module
- `cache/lib/cache/module/disk.ex` — `Cache.Module.Disk` module
- `cache/lib/cache/gradle/disk.ex` — `Cache.Gradle.Disk` module  
- `cache/lib/cache/registry/disk.ex` — `Cache.Registry.Disk` module
- Updated `cache/lib/cache/disk.ex` — Shared helpers only (public)
- Updated controllers: `cas_controller.ex`, `module_cache_controller.ex`, `gradle_controller.ex`, `registry_controller.ex`
- New test files: `cache/test/cache/cas/disk_test.exs`, `cache/test/cache/module/disk_test.exs`, `cache/test/cache/gradle/disk_test.exs`, `cache/test/cache/registry/disk_test.exs`
- Updated `cache/test/test_helper.exs` — Mimic copies for new modules

### Definition of Done
- [x] `mix test` passes with 0 failures
- [x] `mix format --check-formatted` passes
- [x] `mix credo` has no new issues
- [x] `Cache.Disk` contains only shared helpers (artifact_path, storage_dir, usage, delete_project, list_artifact_paths, ensure_directory, move_file, shards_for_id)
- [x] Each domain module exports simplified function names (e.g., `exists?` not `xcode_cas_exists?`)
- [x] No controller calls `Cache.Disk.xcode_cas_*`, `Cache.Disk.module_*`, `Cache.Disk.gradle_*`, or `Cache.Disk.registry_*`

### Must Have
- All 4 domain disk modules created and working
- All callers updated to use new domain modules
- All tests passing
- Shared helpers public in `Cache.Disk`

### Must NOT Have (Guardrails)
- Do NOT create `Cache.CAS.S3`, `Cache.Module.S3`, `Cache.Gradle.S3`, or `Cache.Registry.S3` — S3 has zero domain-specific functions
- Do NOT change any S3 function signatures, bucket selection logic, or `:type` option handling
- Do NOT modify `Cache.S3TransferWorker`, `Cache.DiskEvictionWorker`, or `Cache.CleanProjectWorker` beyond `alias` updates if needed
- Do NOT refactor controller logic, telemetry events, body reading, or API behavior
- Do NOT add deprecation warnings or backward-compat wrappers — clean cut
- Do NOT rename shared functions in `Cache.Disk` (artifact_path stays artifact_path)
- Do NOT touch `Cache.S3` at all

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks in this plan MUST be verifiable WITHOUT any human action.

### Test Decision
- **Infrastructure exists**: YES (ExUnit + Mimic)
- **Automated tests**: YES (Tests-after — move existing tests to new structure)
- **Framework**: ExUnit with Mimic mocking

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

**Verification Tool by Deliverable Type:**

| Type | Tool | How Agent Verifies |
|------|------|-------------------|
| Elixir module | Bash (mix test) | Run specific test files, assert 0 failures |
| Code formatting | Bash (mix format) | Run formatter check, assert exit code 0 |
| Code quality | Bash (mix credo) | Run credo, check for new issues |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately):
└── Task 1: Promote private helpers to public in Cache.Disk

Wave 2 (After Wave 1):
├── Task 2: Extract Cache.CAS.Disk + update callers + tests
├── Task 3: Extract Cache.Gradle.Disk + update callers + tests
└── Task 4: Extract Cache.Registry.Disk + update callers + tests

Wave 3 (After Wave 2):
└── Task 5: Extract Cache.Module.Disk + update callers + tests (depends on seeing pattern from Wave 2)

Wave 4 (After Wave 3):
└── Task 6: Clean up Cache.Disk, update test_helper.exs, final verification
```

### Dependency Matrix

| Task | Depends On | Blocks | Can Parallelize With |
|------|------------|--------|---------------------|
| 1 | None | 2, 3, 4, 5 | None (foundation) |
| 2 | 1 | 6 | 3, 4 |
| 3 | 1 | 6 | 2, 4 |
| 4 | 1 | 6 | 2, 3 |
| 5 | 1 | 6 | 2, 3, 4 (but recommended after to learn from pattern) |
| 6 | 2, 3, 4, 5 | None | None (final) |

### Agent Dispatch Summary

| Wave | Tasks | Recommended Agents |
|------|-------|-------------------|
| 1 | 1 | task(category="quick", load_skills=[], run_in_background=false) |
| 2 | 2, 3, 4 | dispatch parallel, each task(category="unspecified-low", ...) |
| 3 | 5 | task(category="unspecified-low", ...) — Module is most complex due to put_from_parts |
| 4 | 6 | task(category="quick", ...) — cleanup and final verification |

---

## TODOs

- [x] 1. Promote private helpers to public in Cache.Disk

  **What to do**:
  - Make `shards_for_id/1` public with `@doc` — used by CAS, Module, and Gradle domain modules for key construction
  - Make `ensure_directory/1` public with `@doc` — used by all domain `put` functions
  - Make `move_file/2` public with `@doc` — used by all domain `put` functions for atomic file placement
  - Run existing tests to verify nothing breaks

  **Must NOT do**:
  - Do not rename any functions
  - Do not change function signatures
  - Do not move any other functions yet

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file change, promoting 3 private functions to public
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 1 (solo)
  - **Blocks**: Tasks 2, 3, 4, 5
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex:93-95` — `shards_for_id/1` private function, binary pattern match extracting 2-char shards
  - `cache/lib/cache/disk.ex:309-320` — `ensure_directory/1` private function, mkdir_p with error logging
  - `cache/lib/cache/disk.ex:322-334` — `move_file/2` private function, atomic rename with exists check

  **Test References**:
  - `cache/test/cache/disk_test.exs` — Run full file to verify nothing breaks after promotion

  **WHY Each Reference Matters**:
  - `shards_for_id` needs to become public because all 3 non-registry domain modules call it in their `key/` functions
  - `ensure_directory` and `move_file` need to become public because every domain's `put` function calls them
  - Existing tests verify the current behavior is preserved after visibility change

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Private helpers promoted to public successfully
    Tool: Bash (mix)
    Preconditions: cache/ directory, mix deps available
    Steps:
      1. Run: mix test test/cache/disk_test.exs --trace
      2. Assert: Exit code 0
      3. Assert: Output contains "0 failures"
      4. Run: mix format --check-formatted lib/cache/disk.ex
      5. Assert: Exit code 0
    Expected Result: All existing disk tests pass, formatting correct
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `refactor(cache): promote shared disk helpers to public functions`
  - Files: `cache/lib/cache/disk.ex`
  - Pre-commit: `mix test test/cache/disk_test.exs`

---

- [x] 2. Extract Cache.CAS.Disk module + update callers + tests

  **What to do**:
  - Create `cache/lib/cache/cas/disk.ex` with module `Cache.CAS.Disk`
  - Move these functions from `Cache.Disk` (simplifying names):
    - `xcode_cas_key/3` → `Cache.CAS.Disk.key/3`
    - `xcode_cas_exists?/3` → `Cache.CAS.Disk.exists?/3`
    - `xcode_cas_put/4` → `Cache.CAS.Disk.put/4`
    - `xcode_cas_stat/3` → `Cache.CAS.Disk.stat/3`
    - `xcode_cas_local_accel_path/3` → `Cache.CAS.Disk.local_accel_path/3`
    - `xcode_cas_get_local_path/3` → `Cache.CAS.Disk.get_local_path/3`
  - New module should `alias Cache.Disk` and call shared helpers: `Disk.shards_for_id/1`, `Disk.artifact_path/1`, `Disk.ensure_directory/1`, `Disk.move_file/2`
  - Update `cache/lib/cache_web/controllers/cas_controller.ex`:
    - Change `alias Cache.Disk` to `alias Cache.CAS.Disk, as: CASDisk` (keep `alias Cache.Disk` for `artifact_path` if still needed — check: not needed, CAS controller doesn't call artifact_path directly)
    - Replace `Disk.xcode_cas_key(...)` → `CASDisk.key(...)`
    - Replace `Disk.xcode_cas_stat(...)` → `CASDisk.stat(...)`
    - Replace `Disk.xcode_cas_local_accel_path(...)` → `CASDisk.local_accel_path(...)`
    - Replace `Disk.xcode_cas_exists?(...)` → `CASDisk.exists?(...)`
    - Replace `Disk.xcode_cas_put(...)` → `CASDisk.put(...)`
  - Remove CAS functions from `cache/lib/cache/disk.ex`
  - Create `cache/test/cache/cas/disk_test.exs` — move CAS tests from `disk_test.exs` `Cache.DiskTest` module
  - Update `cache/test/cache_web/controllers/cas_controller_test.exs` — change stubs from `Cache.Disk.xcode_cas_*` to `Cache.CAS.Disk.*`
  - Add `Mimic.copy(Cache.CAS.Disk)` to `cache/test/test_helper.exs`
  - Run tests to verify

  **Must NOT do**:
  - Do not change telemetry event names
  - Do not change controller logic or API behavior
  - Do not modify S3 module

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Straightforward extraction with clear pattern, updating ~4 files
  - **Skills**: []
    - No special skills needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 3, 4)
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex:21-105` — All 6 CAS functions to extract
  - `cache/lib/cache/cas/prom_ex_plugin.ex` — Existing CAS module showing naming convention `Cache.CAS.*`

  **Caller References (exhaustive)**:
  - `cache/lib/cache_web/controllers/cas_controller.ex:53` — `Disk.xcode_cas_key(account_handle, project_handle, id)`
  - `cache/lib/cache_web/controllers/cas_controller.ex:56` — `Disk.xcode_cas_stat(account_handle, project_handle, id)`
  - `cache/lib/cache_web/controllers/cas_controller.ex:58` — `Disk.xcode_cas_local_accel_path(account_handle, project_handle, id)`
  - `cache/lib/cache_web/controllers/cas_controller.ex:132` — `Disk.xcode_cas_exists?(account_handle, project_handle, id)`
  - `cache/lib/cache_web/controllers/cas_controller.ex:174` — `Disk.xcode_cas_put(account_handle, project_handle, id, data)`
  - `cache/lib/cache_web/controllers/cas_controller.ex:182` — `Disk.xcode_cas_key(account_handle, project_handle, id)`

  **Test References**:
  - `cache/test/cache/disk_test.exs` — `Cache.DiskTest` module (lines ~10-170) contains CAS unit tests
  - `cache/test/cache_web/controllers/cas_controller_test.exs` — Controller integration tests that stub `Cache.Disk.xcode_cas_*`
  - `cache/test/test_helper.exs:~line 5` — `Mimic.copy(Cache.Disk)` line where new module must be added

  **WHY Each Reference Matters**:
  - Controller lines are the ONLY callers — must update all 6 call sites
  - DiskTest contains the unit tests that must move to the new test file
  - Controller test stubs mock the old function names, must update to new names
  - test_helper.exs needs Mimic.copy for mocking support

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: CAS disk module extracted and all tests pass
    Tool: Bash (mix)
    Preconditions: Task 1 complete (helpers public)
    Steps:
      1. Run: mix test test/cache/cas/disk_test.exs --trace
      2. Assert: Exit code 0, output contains "0 failures"
      3. Run: mix test test/cache_web/controllers/cas_controller_test.exs --trace
      4. Assert: Exit code 0, output contains "0 failures"
      5. Run: mix test test/cache/s3_test.exs --trace
      6. Assert: Exit code 0 (S3 still calls Cache.Disk.artifact_path, must not break)
      7. Run: mix format --check-formatted lib/cache/cas/disk.ex lib/cache/disk.ex lib/cache_web/controllers/cas_controller.ex
      8. Assert: Exit code 0
    Expected Result: CAS module works, controller uses new module, S3 unaffected
    Evidence: Terminal output captured

  Scenario: Old CAS functions removed from Cache.Disk
    Tool: Bash (grep)
    Preconditions: Extraction complete
    Steps:
      1. Run: grep -c "xcode_cas" lib/cache/disk.ex
      2. Assert: Output is "0" (no CAS functions remain)
    Expected Result: Cache.Disk no longer contains CAS-specific functions
    Evidence: grep output
  ```

  **Commit**: YES
  - Message: `refactor(cache): extract CAS disk functions to Cache.CAS.Disk`
  - Files: `cache/lib/cache/cas/disk.ex`, `cache/lib/cache/disk.ex`, `cache/lib/cache_web/controllers/cas_controller.ex`, `cache/test/cache/cas/disk_test.exs`, `cache/test/cache_web/controllers/cas_controller_test.exs`, `cache/test/test_helper.exs`
  - Pre-commit: `mix test test/cache/cas/disk_test.exs && mix test test/cache_web/controllers/cas_controller_test.exs`

---

- [x] 3. Extract Cache.Gradle.Disk module + update callers + tests

  **What to do**:
  - Create `cache/lib/cache/gradle/` directory
  - Create `cache/lib/cache/gradle/disk.ex` with module `Cache.Gradle.Disk`
  - Move these functions from `Cache.Disk` (simplifying names):
    - `gradle_key/3` → `Cache.Gradle.Disk.key/3`
    - `gradle_exists?/3` → `Cache.Gradle.Disk.exists?/3`
    - `gradle_put/4` → `Cache.Gradle.Disk.put/4`
    - `gradle_stat/3` → `Cache.Gradle.Disk.stat/3`
    - `gradle_local_accel_path/3` → `Cache.Gradle.Disk.local_accel_path/3`
  - New module calls shared helpers: `Disk.shards_for_id/1`, `Disk.artifact_path/1`, `Disk.ensure_directory/1`, `Disk.move_file/2`
  - Update `cache/lib/cache_web/controllers/gradle_controller.ex`:
    - Add `alias Cache.Gradle.Disk, as: GradleDisk`
    - Keep `alias Cache.Disk` (GradleController calls `Disk.artifact_path` on line 77)
    - Replace `Disk.gradle_key(...)` → `GradleDisk.key(...)`
    - Replace `Disk.gradle_stat(...)` → `GradleDisk.stat(...)`
    - Replace `Disk.gradle_local_accel_path(...)` → `GradleDisk.local_accel_path(...)`
    - Replace `Disk.gradle_exists?(...)` → `GradleDisk.exists?(...)`
    - Replace `Disk.gradle_put(...)` → `GradleDisk.put(...)`
  - Remove Gradle functions from `cache/lib/cache/disk.ex`
  - Create `cache/test/cache/gradle/disk_test.exs` — Note: `disk_test.exs` has no dedicated Gradle tests currently. Create new tests covering key generation, exists, put, stat, local_accel_path.
  - Add `Mimic.copy(Cache.Gradle.Disk)` to `cache/test/test_helper.exs`
  - Run tests to verify

  **Must NOT do**:
  - Do not change Gradle controller's dev-mode file serving logic (lines 76-78)
  - Do not change telemetry event names

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Simple extraction, same pattern as CAS
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 2, 4)
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex:388-479` — All 5 Gradle functions to extract
  - `cache/lib/cache/cas/disk.ex` (created in Task 2) — Follow same pattern for module structure

  **Caller References (exhaustive)**:
  - `cache/lib/cache_web/controllers/gradle_controller.ex:62` — `Disk.gradle_key(...)`
  - `cache/lib/cache_web/controllers/gradle_controller.ex:64` — `Disk.gradle_stat(...)`
  - `cache/lib/cache_web/controllers/gradle_controller.ex:77` — `Disk.artifact_path(key)` (SHARED — keep `alias Cache.Disk`)
  - `cache/lib/cache_web/controllers/gradle_controller.ex:80` — `Disk.gradle_local_accel_path(...)`
  - `cache/lib/cache_web/controllers/gradle_controller.ex:152` — `Disk.gradle_exists?(...)`
  - `cache/lib/cache_web/controllers/gradle_controller.ex:194` — `Disk.gradle_put(...)`
  - `cache/lib/cache_web/controllers/gradle_controller.ex:202` — `Disk.gradle_key(...)`

  **Test References**:
  - No existing Gradle unit tests in `disk_test.exs` — create new tests following CAS test pattern
  - No `gradle_controller_test.exs` exists — known gap, not blocking

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Gradle disk module extracted and tests pass
    Tool: Bash (mix)
    Preconditions: Task 1 complete
    Steps:
      1. Run: mix test test/cache/gradle/disk_test.exs --trace
      2. Assert: Exit code 0, output contains "0 failures"
      3. Run: mix format --check-formatted lib/cache/gradle/disk.ex lib/cache/disk.ex lib/cache_web/controllers/gradle_controller.ex
      4. Assert: Exit code 0
    Expected Result: Gradle module works, controller uses new module
    Evidence: Terminal output captured

  Scenario: Old Gradle functions removed from Cache.Disk
    Tool: Bash (grep)
    Preconditions: Extraction complete
    Steps:
      1. Run: grep -c "def gradle_" lib/cache/disk.ex
      2. Assert: Output is "0"
    Expected Result: Cache.Disk no longer contains Gradle-specific functions
    Evidence: grep output
  ```

  **Commit**: YES
  - Message: `refactor(cache): extract Gradle disk functions to Cache.Gradle.Disk`
  - Files: `cache/lib/cache/gradle/disk.ex`, `cache/lib/cache/disk.ex`, `cache/lib/cache_web/controllers/gradle_controller.ex`, `cache/test/cache/gradle/disk_test.exs`, `cache/test/test_helper.exs`
  - Pre-commit: `mix test test/cache/gradle/disk_test.exs`

---

- [x] 4. Extract Cache.Registry.Disk module + update callers + tests

  **What to do**:
  - Create `cache/lib/cache/registry/disk.ex` with module `Cache.Registry.Disk`
  - Move these functions from `Cache.Disk` (simplifying names):
    - `registry_key/4` → `Cache.Registry.Disk.key/4`
    - `registry_exists?/4` → `Cache.Registry.Disk.exists?/4`
    - `registry_put/5` → `Cache.Registry.Disk.put/5`
    - `registry_stat/4` → `Cache.Registry.Disk.stat/4`
    - `registry_local_accel_path/4` → `Cache.Registry.Disk.local_accel_path/4`
  - Note: Registry does NOT use `shards_for_id` — it uses `KeyNormalizer.package_object_key` for key construction
  - New module should `alias Cache.Disk` and `alias Cache.Registry.KeyNormalizer`
  - Update `cache/lib/cache_web/controllers/registry_controller.ex`:
    - Add `alias Cache.Registry.Disk, as: RegistryDisk`
    - Remove `alias Cache.Disk` (not needed — controller doesn't call shared Disk functions directly)
    - Replace `Disk.registry_exists?(...)` → `RegistryDisk.exists?(...)`
    - Replace `Disk.registry_local_accel_path(...)` → `RegistryDisk.local_accel_path(...)`
  - Remove Registry functions from `cache/lib/cache/disk.ex`
  - Remove `alias Cache.Registry.KeyNormalizer` from `cache/lib/cache/disk.ex` (only used by registry functions)
  - Create `cache/test/cache/registry/disk_test.exs` — move registry tests from `disk_test.exs` `Cache.DiskRegistryTest` module
  - Add `Mimic.copy(Cache.Registry.Disk)` to `cache/test/test_helper.exs`
  - Update `cache/test/cache_web/controllers/registry_controller_test.exs` — change stubs from `Cache.Disk.registry_*` to `Cache.Registry.Disk.*`
  - Run tests to verify

  **Must NOT do**:
  - Do not change `KeyNormalizer` logic
  - Do not modify S3 type: :registry handling

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Simple extraction, same pattern as CAS
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 2, 3)
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex:481-586` — All 5 Registry functions to extract + comment block
  - `cache/lib/cache/registry/key_normalizer.ex` — `KeyNormalizer.package_object_key` called by `registry_key/4`

  **Caller References (exhaustive)**:
  - `cache/lib/cache_web/controllers/registry_controller.ex:167` — `Disk.registry_exists?(...)`
  - `cache/lib/cache_web/controllers/registry_controller.ex:169` — `Disk.registry_local_accel_path(...)`
  - `cache/lib/cache_web/controllers/registry_controller.ex:217` — `Disk.registry_exists?(...)`
  - `cache/lib/cache_web/controllers/registry_controller.ex:250` — `Disk.registry_local_accel_path(...)`

  **Test References**:
  - `cache/test/cache/disk_test.exs` — `Cache.DiskRegistryTest` module (lines ~180-350) — move to new file
  - `cache/test/cache_web/controllers/registry_controller_test.exs` — Controller tests that stub `Cache.Disk.registry_*`

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Registry disk module extracted and tests pass
    Tool: Bash (mix)
    Preconditions: Task 1 complete
    Steps:
      1. Run: mix test test/cache/registry/disk_test.exs --trace
      2. Assert: Exit code 0, output contains "0 failures"
      3. Run: mix test test/cache_web/controllers/registry_controller_test.exs --trace
      4. Assert: Exit code 0, output contains "0 failures"
      5. Run: mix format --check-formatted lib/cache/registry/disk.ex lib/cache/disk.ex lib/cache_web/controllers/registry_controller.ex
      6. Assert: Exit code 0
    Expected Result: Registry module works, controller uses new module
    Evidence: Terminal output captured

  Scenario: Old Registry functions removed from Cache.Disk
    Tool: Bash (grep)
    Preconditions: Extraction complete
    Steps:
      1. Run: grep -c "def registry_" lib/cache/disk.ex
      2. Assert: Output is "0"
      3. Run: grep -c "KeyNormalizer" lib/cache/disk.ex
      4. Assert: Output is "0" (alias removed since only registry used it)
    Expected Result: Cache.Disk no longer contains Registry-specific code
    Evidence: grep output
  ```

  **Commit**: YES
  - Message: `refactor(cache): extract Registry disk functions to Cache.Registry.Disk`
  - Files: `cache/lib/cache/registry/disk.ex`, `cache/lib/cache/disk.ex`, `cache/lib/cache_web/controllers/registry_controller.ex`, `cache/test/cache/registry/disk_test.exs`, `cache/test/cache_web/controllers/registry_controller_test.exs`, `cache/test/test_helper.exs`
  - Pre-commit: `mix test test/cache/registry/disk_test.exs && mix test test/cache_web/controllers/registry_controller_test.exs`

---

- [x] 5. Extract Cache.Module.Disk module + update callers + tests

  **What to do**:
  - Create `cache/lib/cache/module/disk.ex` with module `Cache.Module.Disk`
  - Move these functions from `Cache.Disk` (simplifying names):
    - `module_key/5` → `Cache.Module.Disk.key/5`
    - `module_exists?/5` → `Cache.Module.Disk.exists?/5`
    - `module_put/6` → `Cache.Module.Disk.put/6`
    - `module_put_from_parts/6` → `Cache.Module.Disk.put_from_parts/6`
    - `module_stat/5` → `Cache.Module.Disk.stat/5`
    - `module_local_accel_path/5` → `Cache.Module.Disk.local_accel_path/5`
  - ALSO move the private helper `copy_parts_to_file/2` — this is only used by `module_put_from_parts` so it stays private in the new module
  - New module calls shared helpers: `Disk.shards_for_id/1`, `Disk.artifact_path/1`, `Disk.ensure_directory/1`, `Disk.move_file/2`
  - Update `cache/lib/cache_web/controllers/module_cache_controller.ex`:
    - Add `alias Cache.Module.Disk, as: ModuleDisk`
    - Remove `alias Cache.Disk` (controller doesn't call shared Disk functions directly)
    - Replace `Disk.module_key(...)` → `ModuleDisk.key(...)`
    - Replace `Disk.module_stat(...)` → `ModuleDisk.stat(...)`
    - Replace `Disk.module_local_accel_path(...)` → `ModuleDisk.local_accel_path(...)`
    - Replace `Disk.module_exists?(...)` → `ModuleDisk.exists?(...)`
    - Replace `Disk.module_put_from_parts(...)` → `ModuleDisk.put_from_parts(...)`
  - Remove Module functions AND `copy_parts_to_file/2` from `cache/lib/cache/disk.ex`
  - Create `cache/test/cache/module/disk_test.exs` — move module-related tests from `disk_test.exs` `Cache.DiskIntegrationTest` module (the `module_put_from_parts` tests)
  - Update `cache/test/cache_web/controllers/module_cache_controller_test.exs` — change stubs from `Cache.Disk.module_*` to `Cache.Module.Disk.*`
  - Add `Mimic.copy(Cache.Module.Disk)` to `cache/test/test_helper.exs`
  - Run tests to verify

  **Must NOT do**:
  - Do not change multipart upload logic
  - Do not change `copy_parts_to_file` behavior

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Most complex extraction due to `put_from_parts` + `copy_parts_to_file`, but still follows established pattern
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (technically parallelizable with Wave 2, but recommended sequential to learn from simpler extractions first)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 6
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex:159-275` — All 6 Module functions + `copy_parts_to_file` to extract
  - `cache/lib/cache/disk.ex:242-258` — `copy_parts_to_file/2` private helper (only used by module_put_from_parts)

  **Caller References (exhaustive)**:
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:80` — `Disk.module_key(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:85` — `Disk.module_stat(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:87` — `Disk.module_local_accel_path(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:182` — `Disk.module_key(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:184` — `Disk.module_exists?(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:240` — `Disk.module_exists?(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:363` — `Disk.module_put_from_parts(...)`
  - `cache/lib/cache_web/controllers/module_cache_controller.ex:373` — `Disk.module_key(...)`

  **Test References**:
  - `cache/test/cache/disk_test.exs` — `Cache.DiskIntegrationTest` module contains `module_put_from_parts` and `delete_project` tests. Move `put_from_parts` tests; keep `delete_project` tests (shared function).
  - `cache/test/cache_web/controllers/module_cache_controller_test.exs` — Controller tests that stub `Cache.Disk.module_*`

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Module disk module extracted and all tests pass
    Tool: Bash (mix)
    Preconditions: Task 1 complete
    Steps:
      1. Run: mix test test/cache/module/disk_test.exs --trace
      2. Assert: Exit code 0, output contains "0 failures"
      3. Run: mix test test/cache_web/controllers/module_cache_controller_test.exs --trace
      4. Assert: Exit code 0, output contains "0 failures"
      5. Run: mix format --check-formatted lib/cache/module/disk.ex lib/cache/disk.ex lib/cache_web/controllers/module_cache_controller.ex
      6. Assert: Exit code 0
    Expected Result: Module cache works, multipart assembly preserved
    Evidence: Terminal output captured

  Scenario: Old Module functions removed from Cache.Disk
    Tool: Bash (grep)
    Preconditions: Extraction complete
    Steps:
      1. Run: grep -c "def module_" lib/cache/disk.ex
      2. Assert: Output is "0"
      3. Run: grep -c "copy_parts_to_file" lib/cache/disk.ex
      4. Assert: Output is "0"
    Expected Result: Cache.Disk no longer contains Module-specific code
    Evidence: grep output
  ```

  **Commit**: YES
  - Message: `refactor(cache): extract Module disk functions to Cache.Module.Disk`
  - Files: `cache/lib/cache/module/disk.ex`, `cache/lib/cache/disk.ex`, `cache/lib/cache_web/controllers/module_cache_controller.ex`, `cache/test/cache/module/disk_test.exs`, `cache/test/cache_web/controllers/module_cache_controller_test.exs`, `cache/test/test_helper.exs`
  - Pre-commit: `mix test test/cache/module/disk_test.exs && mix test test/cache_web/controllers/module_cache_controller_test.exs`

---

- [x] 6. Clean up Cache.Disk, update old test file, final verification

  **What to do**:
  - Verify `cache/lib/cache/disk.ex` now only contains shared functions:
    - `artifact_path/1`, `storage_dir/0`, `list_artifact_paths/1`, `delete_project/2`, `usage/1`
    - `shards_for_id/1`, `ensure_directory/1`, `move_file/2` (now public)
    - Private helpers: `parse_df_output/1`, `parse_df_data_line/1`, `parse_kbytes/1`, `parse_percent/1`
  - Update `@moduledoc` in `Cache.Disk` to describe its new role as shared disk infrastructure
  - Update `cache/test/cache/disk_test.exs`:
    - Remove all domain-specific tests that were moved to new files (CAS tests from DiskTest, Registry tests from DiskRegistryTest, module_put_from_parts from DiskIntegrationTest)
    - Keep tests for shared functions: `storage_dir`, `artifact_path`, `usage`, `delete_project`, `list_artifact_paths`
    - Add tests for newly-public helpers: `shards_for_id`, `ensure_directory`, `move_file`
  - Run FULL test suite: `mix test`
  - Run `mix format`
  - Run `mix credo`
  - Verify no remaining domain function calls in Cache.Disk

  **Must NOT do**:
  - Do not remove shared functions
  - Do not change function signatures of shared helpers

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Cleanup and verification, mostly removing code and running checks
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (final, solo)
  - **Blocks**: None
  - **Blocked By**: Tasks 2, 3, 4, 5

  **References**:

  **Pattern References**:
  - `cache/lib/cache/disk.ex` — After all extractions, should be ~170 lines (shared infrastructure only)

  **Test References**:
  - `cache/test/cache/disk_test.exs` — Original 521-line test file, needs trimming to shared-only tests
  - `cache/test/cache/s3_test.exs` — S3 tests call `Cache.Disk.artifact_path`, must still pass
  - `cache/test/cache/s3_transfer_worker_test.exs` — Uses shared Disk functions, must still pass
  - `cache/test/cache/disk_eviction_worker_test.exs` — Uses shared Disk functions, must still pass
  - `cache/test/cache/clean_project_worker_test.exs` — Uses `Disk.delete_project`, must still pass

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Full test suite passes after complete refactoring
    Tool: Bash (mix)
    Preconditions: Tasks 1-5 complete
    Steps:
      1. Run: mix test --trace
      2. Assert: Exit code 0
      3. Assert: Output contains "0 failures"
      4. Run: mix format --check-formatted
      5. Assert: Exit code 0
      6. Run: mix credo
      7. Assert: No new issues
    Expected Result: Complete refactoring verified, all tests green
    Evidence: Terminal output captured

  Scenario: Cache.Disk only contains shared functions
    Tool: Bash (grep)
    Preconditions: All extractions complete
    Steps:
      1. Run: grep -c "def xcode_cas" lib/cache/disk.ex
      2. Assert: Output is "0"
      3. Run: grep -c "def module_" lib/cache/disk.ex
      4. Assert: Output is "0"
      5. Run: grep -c "def gradle_" lib/cache/disk.ex
      6. Assert: Output is "0"
      7. Run: grep -c "def registry_" lib/cache/disk.ex
      8. Assert: Output is "0"
      9. Run: wc -l lib/cache/disk.ex
      10. Assert: Line count is roughly 150-200 (shared infra only)
    Expected Result: Cache.Disk is clean, only shared helpers remain
    Evidence: grep and wc output

  Scenario: Workers still function with shared helpers
    Tool: Bash (mix)
    Preconditions: All extractions complete
    Steps:
      1. Run: mix test test/cache/s3_transfer_worker_test.exs --trace
      2. Assert: Exit code 0
      3. Run: mix test test/cache/disk_eviction_worker_test.exs --trace
      4. Assert: Exit code 0
      5. Run: mix test test/cache/clean_project_worker_test.exs --trace
      6. Assert: Exit code 0
    Expected Result: Workers unaffected by domain extraction
    Evidence: Terminal output captured
  ```

  **Commit**: YES
  - Message: `refactor(cache): clean up Cache.Disk shared module and finalize domain split`
  - Files: `cache/lib/cache/disk.ex`, `cache/test/cache/disk_test.exs`
  - Pre-commit: `mix test`

---

## Commit Strategy

| After Task | Message | Key Files | Verification |
|------------|---------|-----------|--------------|
| 1 | `refactor(cache): promote shared disk helpers to public functions` | disk.ex | mix test test/cache/disk_test.exs |
| 2 | `refactor(cache): extract CAS disk functions to Cache.CAS.Disk` | cas/disk.ex, cas_controller.ex | mix test |
| 3 | `refactor(cache): extract Gradle disk functions to Cache.Gradle.Disk` | gradle/disk.ex, gradle_controller.ex | mix test |
| 4 | `refactor(cache): extract Registry disk functions to Cache.Registry.Disk` | registry/disk.ex, registry_controller.ex | mix test |
| 5 | `refactor(cache): extract Module disk functions to Cache.Module.Disk` | module/disk.ex, module_cache_controller.ex | mix test |
| 6 | `refactor(cache): clean up Cache.Disk shared module and finalize domain split` | disk.ex, disk_test.exs | mix test |

---

## Success Criteria

### Verification Commands
```bash
mix test                          # Expected: 0 failures
mix format --check-formatted      # Expected: exit code 0
mix credo                         # Expected: no new issues
grep -c "def xcode_cas" cache/lib/cache/disk.ex    # Expected: 0
grep -c "def module_" cache/lib/cache/disk.ex       # Expected: 0
grep -c "def gradle_" cache/lib/cache/disk.ex       # Expected: 0
grep -c "def registry_" cache/lib/cache/disk.ex     # Expected: 0
```

### Final Checklist
- [x] All "Must Have" present (4 domain modules, updated callers, updated tests)
- [x] All "Must NOT Have" absent (no S3 split, no behavior changes, no API changes)
- [x] All tests pass
- [x] `Cache.Disk` only contains shared infrastructure (~199 lines)
- [x] Each domain module has simplified function names
- [x] No controller references old `Cache.Disk` domain functions
