---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Rust flaky tests {#rust-flaky-tests}

Tuist can detect inconsistent Cargo test results and help you investigate them in **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configure <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

## How flaky detection works {#how-it-works}

Tuist compares CI runs on the same commit. A test that passes in one run and fails in another can be marked as flaky.

Report each run through the usual command:

```sh
tuist cargo test --workspace
```

Cargo does not automatically retry failed tests. Re-running a CI job on the same commit provides another result for cross-run detection.

## Managing flaky tests {#managing-flaky-tests}

### Automatic clearing

Detection and recovery run through the project's "Flaky test detection" automation. By default, the flaky flag clears after 14 days without re-triggering. Edit the recovery window and actions under **Settings → Automations**.

### Manual management

Open **Tests → Flaky Tests** to inspect a test's history. You can manually mark or unmark it as flaky from its detail page.

## Quarantining and stress-testing {#quarantine}

Mute or skip a test from its detail page, or configure quarantine in **Settings → Automations**. The next `tuist cargo test` fetches the project's current quarantine state:

- **Muted** tests still run and report their actual results, but their failures do not fail the command. Other test failures, compilation errors, crashes, and incomplete results still fail normally.
- **Skipped** tests are excluded from execution and reported as quarantined skips. Matching includes the package, target, Rust module path, and test name, so similarly named tests remain independent.

Muting preserves the selected workspace packages and features, and runs all selected targets even after a muted target fails. Skip quarantine requires one selected package: use `tuist cargo test -p store` rather than a multi-package workspace command. Tuist rejects multi-package skipping because narrowing the command can change Cargo's unified dependency features.

Quarantine also applies to <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link>. If Tuist cannot fetch the state, it warns and runs without quarantine; failures are not suppressed. To deliberately run without quarantine:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

Enforcement requires standard libtest harnesses and captured default output. Commands with quiet, verbose, alternate-format, or uncaptured output fail when quarantine needs to be applied. Select an exact workspace package with `-p <package>` if target attribution is ambiguous. Custom harnesses, package/target-name globs, and unresolved package selections are unsupported. Doctests can be muted or skipped too, but Rustdoc's test filtering cannot distinguish every possible pair of example names. If skipping an example would also skip an enabled example, or a partial doctest exclusion uses `--exact`, Tuist fails with a diagnostic rather than executing the skipped example or silently omitting enabled tests; use the override above while investigating.

Tuist does not stress-test new Cargo tests. Use a Cargo test filter to repeat a failing test while investigating it:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Slack notifications {#notifications}

Configure <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> to notify your team when a test becomes flaky.
