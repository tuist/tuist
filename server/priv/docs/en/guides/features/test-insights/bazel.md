---
{
  "title": "Bazel Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Bazel test analytics in the Tuist dashboard to monitor test performance and reliability."
}
---
# Bazel test insights {#bazel-test-insights}

> [!WARNING]
> **Requirements**
>
> - A <.localized_link href="/guides/server/accounts-and-projects">Tuist account and project</.localized_link> with Bazel selected as the build system
> - `tuist bazel setup` has been run in the workspace (see <.localized_link href="/guides/features/cache/bazel-cache">Bazel cache</.localized_link>)

Run Bazel tests through Tuist to feed the same test dashboards used by every other build system:

```bash
tuist bazel test -- //app:tests
```

Arguments after `--` are forwarded to `bazel test`. Use `--path` to select the project and working directory, and `--bazel` to select a different executable such as `bazelisk`. Ordinary `bazel test` still reports test results, but does not fetch or enforce Tuist quarantine policies.

> [!NOTE]
> The `tuist bazel test` wrapper is only required for <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">quarantined tests</.localized_link>. Per-case reporting for regular test runs is set up by `tuist bazel setup` in `.bazelrc.tuist`, so a plain `bazel test` reports individual cases too.

## What is tracked {#what-is-tracked}

Tuist parses the `test.xml` reports and captures the `test.log` output that Bazel produces for each test target, then rolls them up into the shared test-runs model. Each run records:

- Individual test case pass, fail, and skipped status, along with duration.
- Test target, class, and suite structure.
- Retry attempts, when Bazel is configured to retry flaky tests.
- Failure output, captured from the target's `test.log`.

The **Test Runs**, **Test Cases**, and individual test pages all work the same way for Bazel as they do for other build systems.

## Emitting per-case JUnit reports {#per-case-junit-reports}

Per-case rows depend on the test target writing a JUnit `test.xml` at the `$XML_OUTPUT_FILE` path Bazel provides. When the runner does not write one, Bazel falls back to a synthesized one-case report named after the target, and Tuist shows a single row per target (labelled **Bazel target** in the Test Cases list) with the raw `test.log` still available on the run page.

Most Bazel test rules already produce a real `test.xml`:

- `java_test` and `kt_jvm_test`: JUnit is built in.
- `cc_test` with GoogleTest: the runner writes JUnit when compiled against a recent gtest; older setups need `--gtest_output=xml:$XML_OUTPUT_FILE`.
- `py_test`: use pytest with `--junitxml=$XML_OUTPUT_FILE`, or the `rules_python` pytest runner.
- `go_test`: pipe `go test -json` through `gotestsum --junitfile=$XML_OUTPUT_FILE`, or wrap with a helper that emits JUnit.

`rust_test` from `rules_rust` and `rules_rs` runs the standard `libtest` harness, which does not write JUnit on stable Rust. Wrap the test target with [cargo-nextest](https://nexte.st) or a small script that parses `libtest` output and writes JUnit to `$XML_OUTPUT_FILE`; you keep per-case rows in Tuist and the same run stays a single Bazel test target.

## Test identity {#test-identity}

Cases are identified by target label, class name (falling back to the suite name), and test name. This keeps identically named methods in different classes separate. Older reports that used a different enclosing suite name retain their history under the old identity; state changes applied to the old identity need to be reapplied to the new one, and the command warns you when a failure matches an old identity so you know which policy to move.

## Providing CI context {#providing-ci-context}

Tuist reads git commit and branch information from Bazel's build metadata so runs on the same commit can be compared across environments. Most continuous integration systems set these already; when yours does not, pass them explicitly:

```bash
tuist bazel test -- \
  --build_metadata=CI=true \
  --build_metadata=GIT_COMMIT="$GIT_COMMIT" \
  --build_metadata=GIT_BRANCH="$GIT_BRANCH" //app:tests
```

The same `--build_metadata` flag is what the <.localized_link href="/guides/features/build-insights/bazel#custom-metadata">Bazel build insights</.localized_link> page describes for tagging invocations, so a single set of flags covers both surfaces.

## Flaky tests and quarantine {#flaky-tests-and-quarantine}

Retries, cross-run flakiness detection, and per-case quarantine (Mute and Skip) all work through `tuist bazel test`. See <.localized_link href="/guides/features/test-insights/flaky-tests/bazel">Bazel flaky tests</.localized_link> for the full workflow.

## Data retention {#data-retention}

Tuist retains the Bazel invocation that produced a test run, its logs, and the pending test ingestion records for 90 days. Test cases and their run history use the same model as every other build system and are not covered by that window. See <.localized_link href="/guides/server/data-retention">data retention</.localized_link> for the full policy.
