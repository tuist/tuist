---
{
  "title": "Bazel",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Tuist",
  "description": "Detect flaky Bazel tests, mute their failures, and skip quarantined targets."
}
---

# Bazel {#bazel}

Configure build and test reporting with `tuist bazel setup`. Tuist uses the individual cases from Bazel's `test.xml` reports to detect inconsistent results across retries and across runs of the same commit and target selection in continuous integration. Local runs remain visible but do not automatically flag test cases as flaky. Provide commit and branch metadata when your build environment does not already publish it:

```sh
bazel test --flaky_test_attempts=3 \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //...
```

Retries must actually run for Tuist to observe their results. A Bazel target's flaky summary alone does not identify which individual case was flaky. Reports that are unavailable or cannot be parsed cannot provide case-level evidence.

Cases are identified by target label, class name (falling back to the suite name), and test name. This keeps identically named methods in different classes separate. Older reports that used a different enclosing suite name retain their history under the old identity; their quarantine state must be applied to the new identity.

The **Flaky Tests**, **Quarantined Tests**, and individual test pages support the same manual state changes as other build systems. Use **Settings → Automations** to configure flakiness thresholds, quarantine actions, and recovery actions.

## Applying quarantine {#applying-quarantine}

Run tests through Tuist to fetch and apply the project's quarantine states before each invocation:

```sh
tuist bazel test -- //...
tuist bazel test -- --config=ci --flaky_test_attempts=3 //app:tests
```

Arguments after `--` are forwarded to `bazel test`. Use `--path` to select the project and working directory, and `--bazel` to select a different executable such as `bazelisk`. Ordinary `bazel test` still reports test results, but does not fetch or enforce Tuist quarantine policies.

### Skip {#skip}

Marking a case **Skipped** excludes its **entire Bazel target**, including healthy cases inside that target. Bazel's individual-case filter syntax depends on the test framework and is not universally supported. Tuist therefore uses native negative target patterns with test-suite expansion enabled. Explicit targets, wildcard selections, and tests inside `test_suite` rules keep Bazel's normal selection behavior.

The command fetches every quarantine page and deduplicates targets. Unresolvable labels, including deleted targets, retain Bazel's error rather than silently weakening the policy. Return those cases to **Enabled** to remove stale exclusions. Pass target patterns directly; `--target_pattern_file` cannot be combined with quarantine exclusions. If no test targets remain, Bazel retains its normal “no tests found” exit status.

### Mute {#mute}

**Muted** cases continue to run. Tuist reads a temporary local build-event file and the referenced `test.xml` reports. It changes Bazel's test-failure exit to success only when complete reports attribute every reported failure in each failed target to a muted case. Healthy cases within those targets still affect the result.

Build errors, timeouts, interrupted runs, missing or malformed reports, incomplete event streams, and failures outside the muted set retain Bazel's failure status. The local event file is bounded to 64 mebibytes and individual reports to 5 mebibytes. Tuist needs its own local build-event file for this check, so an explicit `--build_event_json_file` cannot be combined with active muted cases. Remote build-event reporting remains configured through `tuist bazel setup`.

The original Bazel invocation and reports retain their actual outcomes. Tuist's server records whether a case was quarantined when the invocation started, even if its state changes before the report is processed.

### Running quarantined tests again {#running-quarantined-tests-again}

To investigate or validate a fix, bypass both quarantine policies:

```sh
tuist bazel test --no-quarantine -- --nocache_test_results //app:tests
```

Return the case to **Enabled** to include its target in subsequent normal runs. Skipped cases produce no new executions until explicitly included, so an automation based on successful new runs needs a validation run before it can recover them.

Quarantine retrieval errors stop the command before running tests. The command also rejects policies above 20,000 cases or target arguments above its bounded size; it never applies a partial policy. Use `--no-quarantine` when you intentionally want to run without the policy.

See Bazel's [test filters](https://bazel.build/docs/user-manual#test-filter), [command options](https://bazel.build/reference/command-line-reference), and [build-event descriptions](https://bazel.build/remote/bep-glossary) for the underlying behavior.
