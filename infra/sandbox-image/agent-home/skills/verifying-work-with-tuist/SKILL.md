---
name: verifying-work-with-tuist
description: Checks a change against the project's history in Tuist before calling it done, so that flaky tests, failures that already happen on the default branch, and test or build slowdowns are told apart from regressions. Use in a Tuist sandbox when tests fail, when a change may affect test or build time, or before reporting a task as complete in a project connected to Tuist.
---

# Verifying work with Tuist

Tuist records the project's test runs, test cases with their flakiness, builds,
and Previews. Compare your results against that history before you call a
failure real, a test fixed, or a task done.

## Access

In this sandbox the `tuist` CLI signs in on its own. Pass `--json` to read its
output. If a Tuist MCP server is configured, its tools (`list_test_runs`,
`get_test_case`, `list_test_case_runs` and so on) answer the same questions.

Only read: do not change test cases, quarantine tests, or upload anything
unless the user asks.

Find the project handle (`account/project`) in the repository's `Tuist.swift`
(`fullHandle`) or `tuist.toml` (`project`), and pass it as `--project`. If
neither file exists, the repository is not set up for Tuist; skip this check.

If a command prints a decoding or other client error instead of results, the
sandbox's CLI is older than the server. Its exit status can still be 0, so read
the output. Say so once and continue without this check.

If the CLI reports that you are not authenticated, the
sandbox's account has not connected it to Tuist. Say so once and continue
without this check.

## When a test fails

Before you debug or report a failure, check whether it is yours:

```bash
tuist test case show Module/Suite/TestCase --json
tuist test case run list Module/Suite/TestCase --json --page-size 20
```

- `is_flaky` or a nonzero `flakiness_rate`: the test fails without code
  changes. Rerun it. If it passes, say it is a known flaky test and link it;
  do not change code to fix it unless that is the task.
- Recent failures on the default branch: the failure predates your change.
  Report it as existing, with the failing run.
- Passes on the default branch and fails with your change: treat it as a
  regression you caused and fix it.

## When a change may affect speed

For changes to build configuration, dependencies, caching, or test setup,
compare against recent runs on the default branch (`main` below):

```bash
tuist test list --git-branch main --json --page-size 10
tuist build list --git-branch main --json --page-size 10
```

Skip runs whose `status` is `in_progress`, `processing` or
`failed_processing`; they have no final result yet. Compare durations with your
local run only when both ran the same scheme or task set; a sandbox is slower than CI hardware, so report large differences
(over about 20%) as worth checking, not as proof.

## Before you say the work is done

Include in your report what Tuist showed: tests that failed and whether they
were already flaky or failing on the default branch, and any duration change
you measured. Link the Tuist pages the tools return so the user can check.
