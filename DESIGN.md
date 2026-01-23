# API Design: Builds, Tests, and CLI Runs

## Goals
- Expose read APIs for build runs, test runs, and CLI command runs.
- Keep `command_events` as an internal implementation detail.
- Support multiple toolchains (Xcode now; Gradle/React Native/Flutter later).
- Provide CLI commands that mirror bundle access patterns and map 1:1 to endpoints.

## Terminology
- **Builds**: Build runs and their related data (issues, targets, files, cache/CAS).
- **Tests**: Test runs (executions of a test suite).
- **Test cases**: Individual test cases (used for flakiness workflows).
- **CLI runs**: Command invocations captured via `/api/analytics` (internal `command_events`).
- **Build system type**: The build system that produced the build/test run (e.g. `xcode`, `gradle`, `flutter`, `react_native`).

## Design Summary
- Keep **`/api/analytics`** as the write-only ingestion endpoint for command events.
- Introduce **read endpoints scoped under** `/api/projects/:account_handle/:project_handle`.
- Expose CLI runs as **`/generations`** and **`/cache-runs`** (dashboard-aligned naming).
- Expose build runs via **`/builds`** and test runs via **`/tests`**.
- Keep **`command_events`** and related storage internal.

## API Endpoints (Read, scoped under projects)

### CLI runs (command runs; internal `command_events`)
- `GET /api/projects/:account_handle/:project_handle/generations`
  - Filters: `git_ref`, `git_branch`, `git_commit_sha`, pagination.
- `GET /api/projects/:account_handle/:project_handle/generations/:run_id`
- `GET /api/projects/:account_handle/:project_handle/cache-runs`
  - Filters: `git_ref`, `git_branch`, `git_commit_sha`, pagination.
- `GET /api/projects/:account_handle/:project_handle/cache-runs/:run_id`
  - Backed by `command_events` filtered by `name`/`subcommand`.

### Builds
- `GET /api/projects/:account_handle/:project_handle/builds`
  - Filters: `build_system_type`, `status`, `category`, `scheme`, `configuration`,
    `git_ref`, `git_branch`, `git_commit_sha`, pagination.
- `GET /api/projects/:account_handle/:project_handle/builds/:build_id`
  - Response: build run detail (fields vary by build system type).

### Tests
- `GET /api/projects/:account_handle/:project_handle/tests`
  - Filters: `build_system_type`, `status`, `git_ref`, `git_branch`, `git_commit_sha`, pagination.
- `GET /api/projects/:account_handle/:project_handle/tests/:test_id`
  - Response: test run detail (fields vary by build system type).

### Test cases
- `GET /api/projects/:account_handle/:project_handle/tests/cases`
  - Filters: `flaky`, pagination.
- `GET /api/projects/:account_handle/:project_handle/tests/cases/:test_case_id`

## API Endpoints (Write/Ingestion)
- `POST /api/analytics` (command runs ingestion, internal `command_events`)
- `POST /api/projects/:account_handle/:project_handle/runs` (build/test run ingestion)

## Data Model Notes
- Build runs include:
  - Common fields: `id`, `project_id`, `duration`, `status`, `git_ref`, `git_branch`,
    `git_commit_sha`, `is_ci`, timestamps.
  - `build_system_type` field (enum) with additional fields depending on the type.
    - Example fields for `xcode`: `scheme`, `configuration`, `xcode_version`,
      `macos_version`, `model_identifier`, cache metrics.
- Command runs include:
  - `id`, `name`, `subcommand`, `duration`, `tuist_version`, `swift_version`,
    `macos_version`, `status`, `git_ref`, `git_branch`, `git_commit_sha`, `ran_at`,
    `is_ci`, `cache_endpoint`, `build_run_id`, `test_run_id`.

## Scopes
- Keep ingestion scopes:
  - `project:runs:write` for run ingestion
  - `project:builds:write` for build ingestion (if separate in the future)
- Add read scopes:
  - `project:runs:read` for CLI runs
  - `project:builds:read` for build runs
  - `project:tests:read` for test runs
  - `project:tests:cases:read` for test cases

## CLI Commands and Matching API Endpoints
Mirror the bundle command style and map 1:1 to endpoints:
- `tuist generate list` -> `GET /api/projects/:account_handle/:project_handle/generations`
- `tuist generate show <id>` -> `GET /api/projects/:account_handle/:project_handle/generations/:run_id`
- `tuist cache list` -> `GET /api/projects/:account_handle/:project_handle/cache-runs`
- `tuist cache show <id>` -> `GET /api/projects/:account_handle/:project_handle/cache-runs/:run_id`
- `tuist build list` -> `GET /api/projects/:account_handle/:project_handle/builds`
- `tuist build show <id>` -> `GET /api/projects/:account_handle/:project_handle/builds/:build_id`
- `tuist test list` -> `GET /api/projects/:account_handle/:project_handle/tests`
- `tuist test show <id>` -> `GET /api/projects/:account_handle/:project_handle/tests/:test_id`
- `tuist test case list` -> `GET /api/projects/:account_handle/:project_handle/tests/cases`
- `tuist test case show <id>` -> `GET /api/projects/:account_handle/:project_handle/tests/cases/:test_case_id`

## Iteration Plan
1) First iteration
   - Implement read endpoints for builds, tests, generations, and cache-runs.
   - Keep payloads minimal; avoid heavy sub-resources for now.
   - Use `build_system_type` and add fields per build system without early generalization.
2) Follow-up iteration
   - Add test case endpoints and flaky filters for agent workflows.
   - Consider renaming/mirroring dashboard pages to `generations` (if needed).
3) Align modules
   - Split `Tuist.Runs` into `Tuist.Builds` and `Tuist.Tests` when implementing
     to match API terminology and reduce ambiguity.

## Future Toolchains
- `build_system_type` allows us to add Gradle/Flutter/React Native with new fields
  without forcing premature generalization of the API.
