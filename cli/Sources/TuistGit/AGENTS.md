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
- `GitController+History.swift` collects a run's Git history for the server's commit graph and coverage baselines (`gitHistory`: object format, merge base with the base branch, deepening a shallow clone within a budget, the commits within the window, leaving out a shallow clone's boundary commits (listed in its `shallow` file) because `git log` shows them without the parents they have and the server would store them as roots for good, the changed files with hunks against the merge base) and the commit's file listing (`commitFiles`: every blob of the reported commit's tree from `git ls-tree -r --full-tree <sha>` with its mode, at most the server's limit, marking the listing truncated beyond it; the tree rather than the index because on a `refs/pull/N/merge` checkout the run reports HEAD^2 while the index is the merge commit's; the server keys it by repository and commit, so it is uploaded once per commit). `GitHistoryParser` parses the `git log`, `git diff --raw`/`-U0` and `git ls-tree` output. The `-U0` diff pins `core.quotePath=false` and the `a/`/`b/` prefixes so the user's diff config cannot change the `+++ b/<path>` headers the hunks are keyed by; the parser strips the tab Git appends to a name with a space, unquotes C-quoted names, and only reads `+++ ` as a header right after the `--- ` line of a `diff --git` block (inside a hunk it is an added line). Everything is best effort: a missing piece is reported as a reason with the run, never an error.
