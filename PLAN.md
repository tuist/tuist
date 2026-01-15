# Plan: Builds, Tests, and CLI Runs API

## Milestone 0: Design and alignment
- Ensure `DESIGN.md` is approved by the team.
- Confirm naming: `generations`, `cache-runs`, `build`, `test`, `test case`.

## Milestone 1: Generations (command runs)
- API:
  - `GET /api/projects/:account_handle/:project_handle/generations`
  - `GET /api/projects/:account_handle/:project_handle/generations/:run_id`
- Scope: `project:runs:read`.
- OpenAPI: add endpoints + regenerate client types.
- CLI: `tuist generate list/show`.
- Tests: server controller tests + CLI tests.

## Milestone 2: Cache runs (command runs)
- API:
  - `GET /api/projects/:account_handle/:project_handle/cache-runs`
  - `GET /api/projects/:account_handle/:project_handle/cache-runs/:run_id`
- Scope: `project:runs:read`.
- OpenAPI: add endpoints + regenerate client types.
- CLI: `tuist cache list/show`.
- Tests: server controller tests + CLI tests.

## Milestone 3: Builds
- API:
  - `GET /api/projects/:account_handle/:project_handle/builds`
  - `GET /api/projects/:account_handle/:project_handle/builds/:build_id`
- Scope: `project:builds:read`.
- OpenAPI: add endpoints + regenerate client types.
- CLI: `tuist build list/show`.
- Tests: server controller tests + CLI tests.

## Milestone 4: Tests (test runs)
- API:
  - `GET /api/projects/:account_handle/:project_handle/tests`
  - `GET /api/projects/:account_handle/:project_handle/tests/:test_id`
- Scope: `project:tests:read`.
- OpenAPI: add endpoints + regenerate client types.
- CLI: `tuist test list/show`.
- Tests: server controller tests + CLI tests.

## Milestone 5: Test cases
- API:
  - `GET /api/projects/:account_handle/:project_handle/tests/cases`
  - `GET /api/projects/:account_handle/:project_handle/tests/cases/:test_case_id`
  - Filter: `flaky`.
- Scope: `project:tests:cases:read`.
- OpenAPI: add endpoints + regenerate client types.
- CLI: `tuist test case list/show`.
- Tests: server controller tests + CLI tests.

## Milestone 6: Internal module alignment (optional)
- Split `Tuist.Runs` into `Tuist.Builds` and `Tuist.Tests`.
- Update callers incrementally behind a compatibility layer.

## Notes
- Keep payloads minimal in list endpoints.
- Add heavy sub-resources only if needed (issues, targets, files, cache/CAS).
- Use `build_system_type` and add fields per build system without early generalization.
