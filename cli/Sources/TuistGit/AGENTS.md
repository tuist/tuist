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
- `GitController+History.swift` collects a run's Git history for the server's commit graph and coverage baselines (`gitHistory`: object format, merge base with the base branch, deepening a shallow clone within a budget, the commits within the window, the changed files with hunks against the merge base) and the tracked files (`trackedFiles`: `git ls-files --stage` over the server's pathspec globs, at most the server's limit, marking the listing truncated beyond it). `GitHistoryParser` parses the `git log`, `git diff --raw`/`-U0` and `git ls-files --stage` output. Everything is best effort: a missing piece is reported as a reason with the run, never an error.
