---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect, manage, and quarantine flaky tests in a Tuist-generated Xcode project."
}
---
# Generated Xcode project {#generated-xcode-project-flaky-tests}

> [!IMPORTANT]
> **Requirements**
>
> - <.localized_link href="/guides/features/test-insights/xcode">Xcode test insights</.localized_link> configured (auto-generated schemes include the `tuist inspect test` post-action; custom schemes need it added).

<!-- @snippet: ./_intro -->

![Flaky Tests page](/images/guides/features/test-insights/flaky-tests-page.png)

## How flaky detection works {#how-it-works}

Tuist detects flaky tests in two ways:

### Test retries {#test-retries}

When you run tests with retry functionality, Tuist analyzes the results of each attempt. If a test fails on some attempts but passes on others, it's marked as flaky.

Pass `-retry-tests-on-failure` or `-test-iterations` through `tuist test`:

```sh
tuist test MyScheme -- -retry-tests-on-failure -test-iterations 3
```

![Flaky test case detail](/images/guides/features/test-insights/flaky-test-case-detail.png)

<!-- @snippet: ./_xcode-cross-run -->

<!-- @snippet: ./_managing -->

## Quarantining flaky tests {#quarantining}

<!-- @snippet: ./_quarantine-intro -->

A quarantined test is in one of two modes:

- **Muted**: the test still runs, but `tuist test` masks the failure. Failures still feed the flaky-tests detector, so you can keep watching the test without breaking the build. Pick this for a test you're actively investigating.
- **Skipped**: xcodebuild receives `-skip-testing <identifier>`, so the test never starts. It produces no new results and drops off the flaky-tests dashboard until you re-enable it. Pick this when the test is broken, slow, or so persistently flaky that running it is just wasted CI minutes.

<!-- @snippet: ./_quarantined-passing -->

### Running tests {#running-tests}

`tuist test` honors both modes automatically:

```sh
tuist test
```

Skipped tests are passed to xcodebuild as `-skip-testing` and never start. Muted tests run normally; if they fail, the failure is masked in the resulting build status.

To bypass quarantine entirely and run everything, including muted and skipped tests:

```sh
tuist test --skip-quarantine
```

## Stress-testing new tests {#stress-testing-new-tests}

<!-- @snippet: ./_stress-intro -->

A test case counts as new when it hasn't run in CI in the last 90 days on the project's default branch, or on a commit that has since landed on it. With a merge queue, a test case the queue ran is known once the queue's commit lands, and stays new if the queue drops it. Commits are matched through the <.localized_link href="/guides/features/test-insights/xcode#git-history">Git history</.localized_link> Tuist collects on CI.

<!-- @snippet: ./_stress-modes -->

In both modes, <.localized_link href="/guides/features/selective-testing/generated-xcode-project">selective testing</.localized_link> doesn't skip a test target with a flaky new test case on the next run. The target runs again, and the gate stresses the test case again, until it passes all its reruns.

Pass it ahead of the passthrough arguments, or set `TUIST_TEST_STRESS_NEW_TESTS` to vary the mode per CI lane:

```sh
tuist test --stress-new-tests report
```

<!-- @snippet: ./_stress-reruns -->

Reruns reuse what the first pass built.

<!-- @snippet: ./_stress-skipped -->

<!-- @snippet: ./_slack -->

<!-- @snippet: ./_querying -->
