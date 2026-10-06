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
- `GitController+History.swift` collects a run's Git history for the server's commit graph and coverage baselines (`gitHistory`: object format, merge base with the base branch, deepening a shallow clone within a budget (the base branch named on every fetch, `--filter=blob:none`, the steps together within the window), the commits within the window, with a shallow clone's boundary commits (listed in its `shallow` file) given the parents their commit objects store, read in one `git log --no-walk --no-decorate --format=raw` call because `git log` lists them without parents and the raw format ignores the shallow grafts (in a depth-1 clone the head is such a commit, so without this a push uploads nothing; when the parents cannot be read the boundary commits are left out rather than stored as roots), the changed files with hunks against the merge base) and the commit's file listing (`commitFiles`: every blob of the reported commit's tree from `git ls-tree -r --full-tree <sha>` with its mode, at most the server's limit, marking the listing truncated beyond it; the tree rather than the index because on a `refs/pull/N/merge` checkout the run reports HEAD^2 while the index is the merge commit's; the server keys it by repository and commit, so it is uploaded once per commit). `GitHistoryParser` parses the `git log` (including the raw format's `commit`/`parent` headers), `git diff --raw`/`-U0` and `git ls-tree` output. The `-U0` diff pins `core.quotePath=false` and the `a/`/`b/` prefixes so the user's diff config cannot change the `+++ b/<path>` headers the hunks are keyed by; the parser strips the tab Git appends to a name with a space, unquotes C-quoted names, and only reads `+++ ` as a header right after the `--- ` line of a `diff --git` block (inside a hunk it is an added line). Every fetch of the merge-base recovery (the base branch's, then each `--deepen`) shares the deepen budget and is raced against what is left of it: one still running at the deadline is cancelled through `CommandRunning.runInOwnProcessGroup`, which tears down `git fetch` together with the `git-remote-https`/`ssh`/`index-pack` processes it started, and the run reports the base branch as not fetched, or the merge base as not found, "within Ns". Everything is best effort: a missing piece is reported as a reason with the run, never an error.
