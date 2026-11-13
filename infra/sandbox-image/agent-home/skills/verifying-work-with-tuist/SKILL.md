---
name: verifying-work-with-tuist
description: Checks a change against the project's history in Tuist before calling it done, so that flaky tests, failures that already happen on the default branch, and test or build slowdowns are told apart from regressions. Use in a Tuist sandbox when tests fail, when a change may affect test or build time, or before reporting a task as complete in a project connected to Tuist.
---

# Verifying work with Tuist

Tuist records the project's test runs, test cases with their flakiness, builds,
and Previews. Compare your results against that history before you call a
failure real, a test fixed, or a task done.

## Access

In this sandbox, both ways of reading Tuist sign in on their own:

- The `tuist` MCP server (tools such as `list_test_runs`, `list_test_cases`,
  `get_test_case`, `list_test_case_runs`, `list_xcode_builds`,
  `list_gradle_builds`, `list_previews`).
- The `tuist` CLI. Pass `--json` to read its output.

Access is read-only in practice: do not change test cases, quarantine tests,
or upload anything unless the user asks.

Find the project handle (`account/project`) in the repository's `Tuist.swift`
(`fullHandle`) or `tuist.toml` (`project`). If neither exists, call
`list_projects` and match the repository. Pass it as `--project` to the CLI
when you run it outside the project directory.

If both the MCP server and the CLI report that you are not authenticated, the
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

Compare durations with your local run only when both ran the same scheme or
task set; a sandbox is slower than CI hardware, so report large differences
(over about 20%) as worth checking, not as proof.

## Before you say the work is done

Include in your report what Tuist showed: tests that failed and whether they
were already flaky or failing on the default branch, and any duration change
you measured. Link the Tuist pages the tools return so the user can check.
