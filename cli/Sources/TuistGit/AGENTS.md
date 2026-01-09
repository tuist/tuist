# TuistGit (CLI Module)

This module provides Git-related helpers and repository interactions.

## Responsibilities
- Execute git operations (clone, checkout, log) and query repo metadata.
- Provide `GitInfo` with CI-aware fallbacks for refs, branches, and PR IDs.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md

## Invariants
- `GitController` uses the system to execute git commands and tolerates missing repos.
- CI environment variables are used to infer branch and PR refs when git data is unavailable.
