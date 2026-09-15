---
{
  "title": "Bazel Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---

# Bazel flaky tests {#bazel-flaky-tests}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link> with Bazel selected as the build system
> - `tuist bazel setup` has been run in the workspace (see <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link>)
> - Tests are executed with `tuist bazel test` (see <.localized_link href="/guides/features/test-insights/bazel">Bazel test insights</.localized_link>)

`tuist bazel test` fetches Tuist's quarantine policy before each invocation and applies it to the underlying `bazel test` run.

## Applying quarantine {#applying-quarantine}

On a test's page, change its state to **Muted**, then run:

```sh
tuist bazel test -- //app:tests
```

Arguments after `--` are forwarded to `bazel test`. Use `--path` to select the project and working directory, and `--bazel` to select a different executable such as `bazelisk`. Ordinary `bazel test` still reports test results, but does not fetch or enforce Tuist quarantine policies.

Neither a named Bazel configuration nor retries are required for quarantine. The **Flaky Tests**, **Quarantined Tests**, and individual test pages support the same manual state changes as other build systems. Use **Settings → Automations** to configure flakiness thresholds, quarantine actions, and recovery actions.

### Mute {#mute}

Use **Mute** as the primary quarantine workflow. Muted cases continue to run, their failures remain visible, and healthy sibling cases still affect the result. New executions provide evidence for recovery without excluding any cases from the target.

Tuist reads a temporary local build-event file and the referenced `test.xml` reports. It changes Bazel's test-failure exit to success only when complete reports attribute every reported failure in each failed target to a muted case.

Build errors, timeouts, interrupted runs, missing or malformed reports, incomplete event streams, and failures outside the muted set retain Bazel's failure status. The local event file is bounded to 64 mebibytes and individual reports to 5 mebibytes. Tuist needs its own local build-event file to verify muted failures and recover from stale skipped targets, so an explicit `--build_event_json_file` cannot be combined with active muted or skipped cases. Remote build-event reporting remains configured through `tuist bazel setup`.

The original Bazel invocation and reports retain their actual outcomes. Tuist's server records whether a case was quarantined when the invocation started, even if its state changes before the report is processed.

### Skip {#skip}

Use **Skip** only when you intend to exclude the **entire Bazel target**, including healthy cases inside that target. Marking a single case **Skipped** has this target-wide effect. Bazel's individual-case filter syntax depends on the test framework and is not universally supported. Tuist therefore uses native negative target patterns with test-suite expansion enabled. Explicit targets, wildcard selections, and tests inside `test_suite` rules keep Bazel's normal selection behavior.

The command fetches every quarantine page and deduplicates targets. If Bazel's complete event log identifies a missing skipped target before target configuration or execution, Tuist names it in a warning and retries without that stale exclusion. The original requested patterns and all other exclusions are preserved. Recovery is limited to five retries; other loading failures and incomplete evidence retain Bazel's error. Return stale cases to **Enabled** to remove their policies permanently. Pass target patterns directly; `--target_pattern_file` cannot be combined with quarantine exclusions. If no test targets remain, Bazel retains its normal “no tests found” exit status, which also catches an accidentally empty test selection.

The command prints every excluded target label so build logs show which targets, including their healthy cases, the quarantine policy excludes.

### Running quarantined tests again {#running-quarantined-tests-again}

To investigate or validate a fix, bypass both quarantine policies:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Return the case to **Enabled** to include its target in subsequent normal runs. Skipped cases produce no new executions until explicitly included, so an automation based on successful new runs needs a validation run before it can recover them.

Quarantine retrieval errors stop the command before running tests. The command also rejects policies above 20,000 cases or target arguments above its bounded size; it never applies a partial policy. Use `--no-quarantine` when you intentionally want to run without the policy.

## Optional configuration and retries {#optional-configuration-and-retries}

If your repository defines a named `ci` configuration in `.bazelrc`, you can select it with `--config=ci`:

```sh
tuist bazel test -- --config=ci //app:tests
```

This is a repository-defined configuration, not a Tuist prerequisite. Omit the option when your repository does not define it.

Retries are also optional and independent of quarantine. `--flaky_test_attempts=3` enables up to **three total Bazel attempts** per test, not three additional retries. Teams can keep their existing retry configuration in `.bazelrc` or pass it explicitly:

```sh
tuist bazel test -- --flaky_test_attempts=3 //app:tests
```

For repositories that define `ci`, the options can be combined:

```sh
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

## Detecting flakiness {#detecting-flakiness}

Tuist uses the individual cases from Bazel's `test.xml` reports to detect inconsistent results across retries and across runs of the same commit and target selection in continuous integration. Local runs remain visible but do not automatically flag test cases as flaky. Provide commit and branch metadata when your build environment does not already publish it:

```sh
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

Retries must actually run for Tuist to observe their results. A Bazel target's flaky summary alone does not identify which individual case was flaky. Reports that are unavailable or cannot be parsed cannot provide case-level evidence.

Cases are identified by target label, class name (falling back to the suite name), and test name. This keeps identically named methods in different classes separate. Older reports that used a different enclosing suite name retain their history under the old identity; their quarantine state must be applied to the new identity. When a failure matches an old suite-based mute instead of its current class identity, the command warns which policy needs to be reapplied and keeps the failure blocking. Policies are not transferred automatically because multiple classes may have shared the old identity.

See Bazel's [test filters](https://bazel.build/docs/user-manual#test-filter), [command options](https://bazel.build/reference/command-line-reference), and [build-event descriptions](https://bazel.build/remote/bep-glossary) for the underlying behavior.
