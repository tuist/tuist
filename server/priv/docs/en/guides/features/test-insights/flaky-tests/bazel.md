---
{
  "title": "Bazel Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---
# Bazel flaky tests {#bazel-flaky-tests}

> [!IMPORTANT]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights/bazel">Bazel test insights</.localized_link> configured through `tuist bazel setup`.

<!-- @snippet: ./_intro -->

## How flaky detection works {#how-it-works}

Tuist uses the individual cases from Bazel's `test.xml` reports to detect inconsistent results across retries and across runs of the same commit and target selection in continuous integration. Local runs remain visible but do not automatically flag test cases as flaky.

### Test retries {#test-retries}

Retries are optional and independent of quarantine. `--flaky_test_attempts=3` enables up to **three total Bazel attempts** per test, not three additional retries. Keep your existing retry configuration in `.bazelrc` or pass it explicitly:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

Retries must actually run for Tuist to observe their results. A Bazel target's flaky summary alone does not identify which individual case was flaky.

### Cross-run detection {#cross-run-detection}

Comparing runs needs commit and branch metadata. Provide it when your build environment does not already publish it:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Cases are identified by target label, class name (falling back to the suite name), and test name, as described in <.localized_link href="/guides/features/test-insights/bazel">Bazel test insights</.localized_link>.

<!-- @snippet: ./_managing -->

## Quarantining flaky tests {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

`tuist bazel test` fetches the quarantine policy before each invocation and applies it to the underlying `bazel test` run. Ordinary `bazel test` still reports test results, but does not apply quarantine:

```sh
tuist bazel test -- //app:tests
```

Arguments after `--` are forwarded to `bazel test`. Use `--path` to select the project and working directory, and `--bazel` to select a different executable such as `bazelisk`. A named Bazel configuration such as `--config=ci` is optional and works the same way.

### Mute {#mute}

Use **Mute** as the primary quarantine workflow. Muted cases continue to run, their failures remain visible, and healthy sibling cases still affect the result. Tuist turns Bazel's test-failure exit into success only when the reports attribute every failure in each failed target to a muted case. Build errors, timeouts, interrupted runs, missing or incomplete reports, and failures outside the muted set keep Bazel's failure status.

### Skip {#skip}

Skipping works per Bazel target: skipping one case excludes its whole target, including healthy cases, because Bazel can't filter individual cases for every test framework. Prefer **Mute** unless you intend to exclude the entire target. The command prints every excluded target label so build logs show what the quarantine policy left out.

If a skipped target no longer exists, Tuist names it in a warning and runs without that exclusion. Return stale cases to **Enabled** to remove their policies permanently. If no test targets remain, Bazel keeps its normal "no tests found" exit status.

<!-- @snippet: ./_quarantined-passing -->

### Running quarantined tests again {#running-quarantined-tests-again}

To investigate or validate a fix, bypass the quarantine policy:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Return the case to **Enabled** to include its target in subsequent normal runs. Skipped cases produce no new executions until explicitly included, so an automation based on successful new runs needs a validation run before it can recover them.

### Limitations {#limitations}

- An explicit `--build_event_json_file` or `--target_pattern_file` cannot be combined with active quarantine. Pass target patterns directly.
- If Tuist cannot fetch the quarantine policy, the command stops before running tests. It never applies a partial policy. Use `--no-quarantine` when you intentionally want to run without it.
- A failure that matches a mute recorded under an older suite-based identity stays blocking, and the command names the policy to reapply.

See Bazel's [test filters](https://bazel.build/docs/user-manual#test-filter), [command options](https://bazel.build/reference/command-line-reference), and [build-event descriptions](https://bazel.build/remote/bep-glossary) for the underlying behavior.

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
