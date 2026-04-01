# RFC: Quarantine Modes -- Mute and Skip

## Status

Draft

## Context

Until recently, quarantining a test in Tuist meant fully skipping it during test execution. We changed this behavior so quarantined tests still run but their failures no longer affect the CI exit code (mute mode). This gives teams continuous signal on whether a quarantined test has been fixed.

However, multiple customers have requested the ability to fully skip quarantined tests again. Their use cases include:

- **Custom reporting**: Some teams have their custom test reporting that rely directly on the `.xcresult`, but the new quarantine behavior only adjusts Tuist reporting.
- **Consistently failing or slow tests**: Some tests are so broken or slow that running them provides no value. Teams want to remove them from execution entirely until they are fixed.
- **Decision matrix alignment**: Some teams use a two-tier system internally: silence (mute) for temporary flaky issues, and disable (skip) for high-flakiness or consistently broken tests.

Reference: [Buildkite Test Engine](https://buildkite.com/docs/test-engine) has a similar distinction between "muting" and "quarantining" a test.

## Proposal

Introduce two distinct quarantine modes for test cases:

| Mode | Behavior | Use case |
|------|----------|----------|
| **Mute** (current default) | Test runs normally. Failures are reported but do not affect the CI exit code. | Flaky tests that need monitoring. Teams want signal on when the test stabilizes. |
| **Skip** (previous behavior) | Test is fully excluded from execution. Results are not reported. | Broken, slow, or highly flaky tests that provide no useful signal. |

## User-Facing Changes

### Dashboard

#### Quarantine button (test case detail page)

The current single "Quarantine" button becomes a two-option action. When quarantining a test, the user selects a mode:

```
[Quarantine ▾]
  ├── Mute (run but ignore failures)
  └── Skip (exclude from execution)
```

When a test is already quarantined, show the current mode and allow switching:

```
Quarantine mode: (•) Mute  ( ) Skip    [Unquarantine]
```

Switching mode does not require unquarantining first -- it updates the mode in place and logs an event in the test case history.

#### Quarantined tests page

- Add a **Mode** column to the table showing "Mute" or "Skip" with distinct visual badges
- Add a **mode filter** dropdown (All / Mute / Skip)

#### Project automations

When auto-quarantine is enabled, auto-quarantined tests default to **Mute** mode. A project-level setting allows changing the default to Skip:

```
Auto-quarantine mode: [Mute ▾]
```

### CLI (`tuist test` / `tuist xcodebuild test`)

- **Mute mode** (current behavior): The CLI fetches quarantined tests from the server, runs all tests normally, then marks quarantined tests in the parsed `.xcresult`. If only quarantined tests failed, the exit code is overridden to success. Results are uploaded to Tuist with the quarantine flag.
- **Skip mode**: The CLI fetches quarantined tests with `mode=skip` from the server and passes them as `-skip-testing` arguments to xcodebuild, so they are never executed. This is equivalent to what users previously did manually with `tuist test case list --skip-testing`:

  ```bash
  # Automatic: tuist test and tuist xcodebuild test handle this transparently.
  # The CLI adds -skip-testing arguments for each skip-quarantined test:
  tuist test
  # -> xcodebuild test -skip-testing Module/Suite/testMethod ...

  # Manual: for teams using raw xcodebuild, the existing command still works:
  xcodebuild test $(tuist test case list --skip-testing)
  ```

  Since skipped tests produce no results in the `.xcresult` bundle, they are not included in the uploaded test run.

The existing `--skip-quarantine` flag continues to work and disables all quarantine behavior (both mute and skip).

### Gradle plugin

- **Mute mode** (current behavior): Tests run normally. Only non-quarantined failures cause the build to fail.
- **Skip mode**: Tests are excluded via Gradle's `excludeTestsMatching` filter. They do not execute.

The existing `testQuarantine.enabled = false` setting continues to disable all quarantine behavior.

### API

The list test cases endpoint (`GET /api/.../test-cases?quarantined=true`) gains a `quarantine_mode` field in the response (`"mute"` or `"skip"`). This is the only contract change clients need to act on.

The test upload endpoint (`POST /api/.../tests`) accepts an optional `quarantine_mode` field on test cases, alongside the existing `is_quarantined` boolean.

### Automatic flaky unmarking

Automatic unmarking of flaky tests only applies to tests quarantined with **Mute** mode, since those tests continue to run and produce results that can be evaluated. Tests quarantined with **Skip** mode are excluded from execution, so there is no signal to determine whether they have stabilized.

### Reporting and analytics

- Muted tests: reported with full results (pass/fail/duration), as today.
- Skipped tests: not present in test runner output. The CLI/Gradle plugin reports them synthetically to the server as skipped, so the quarantined tests page and analytics remain accurate.
- The quarantined tests analytics chart optionally breaks down by mode.

## Backward Compatibility

- All existing quarantined tests are migrated to **Mute** mode. No behavior change for current users.
- Old CLI/Gradle versions that do not understand `quarantine_mode` continue to treat all quarantined tests as muted.
- The `is_quarantined` boolean is preserved. The new `quarantine_mode` field is additive.

## Open Questions

1. **Naming**: "Mute" and "Skip" are used throughout this RFC. Alternatives considered:
   - Silence / Disable
   - Monitor / Exclude
   - Run / Skip

   "Mute" and "Skip" are concise and unambiguous.
