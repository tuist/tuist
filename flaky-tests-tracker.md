# Fixing Flaky Tests in tuist/tuist with the `fix-flaky-tests` Skill

## Overview

This document tracks the process of finding and fixing flaky tests in the tuist/tuist repository using the [`fix-flaky-tests`](https://github.com/tuist/agent-skills) agent skill. The skill provides a structured workflow: discover flaky tests via Tuist's test insights, investigate failure patterns, identify root causes, and apply targeted fixes.

## Workflow

The skill follows a 5-step process:

1. **Discover** — `tuist test case list --flaky` to find all flaky tests
2. **Get metrics** — `tuist test case show <id>` to see reliability rates and run counts
3. **Analyze runs** — `tuist test case run list <id> --flaky` to find failure patterns
4. **Get details** — `tuist test case run show <run-id>` to get failure messages and stack traces
5. **Fix & verify** — Read the source, identify the pattern, fix it, run with `--test-iterations`

## Discovery

We started by listing all flaky tests:

```bash
tuist test case list --flaky --json --page-size 50
```

This returned **17 flaky test cases** across 4 test suites:

### Unit Tests (fast, high value to fix)

| Suite | Test | Avg Duration | Quarantined |
|-------|------|-------------|-------------|
| ShareCommandServiceTests | `share_app_bundles()` | 939ms | No |
| ShareCommandServiceTests | `share_ipa()` | 913ms | No |
| ShareCommandServiceTests | `share_ipa_with_track()` | 913ms | No |
| ShareCommandServiceTests | `share_tuist_project()` | 1040ms | No |
| ShareCommandServiceTests | `share_tuist_project_with_a_specified_app()` | 1039ms | No |
| ShareCommandServiceTests | `share_tuist_project_with_a_specified_appclip()` | 1038ms | No |
| ShareCommandServiceTests | `share_with_track()` | 912ms | No |
| ShareCommandServiceTests | `share_xcode_app()` | 1039ms | No |
| AnalyticsUploadCommandServiceTests | `run_deletes_event_file_after_upload()` | 957ms | No |
| HashSelectiveTestingCommandServiceTests | `run_outputsAWarning_when_noHashes()` | 659ms | No |
| InitCommandServiceTests | `generatesTheRightConfiguration_...` | 4577ms | Yes |

### Acceptance Tests (slow, environment-sensitive)

| Suite | Test | Avg Duration | Quarantined |
|-------|------|-------------|-------------|
| ShareAcceptanceTests | `share_ios_app_with_frameworks()` | 257s | No |
| ShareAcceptanceTests | `share_xcode_app_files()` | 243s | Yes |
| ShareAcceptanceTests | `share_and_run_xcode_app()` | 236s | Yes |
| ShareAcceptanceTests | `share_and_run_ios_app_with_appclip()` | 282s | Yes |
| TuistCacheEECanaryAcceptanceTests | `ios_app_with_frameworks_legacy()` | 166s | No |
| TuistCacheEEAcceptanceTests | `xcode_project_with_ios_app_and_cas()` | 18s | No |

## Investigation & Fixes

### Fix 1: Matcher.register Thread-Safety Crash (10 unit tests)

**Affected tests:** All 8 `ShareCommandServiceTests` + `AnalyticsUploadCommandServiceTests` + `HashSelectiveTestingCommandServiceTests`

**Failure message:** `Crash: xctest at Matcher.register<A>(_:)`

**Investigation process:**

Using `tuist test case run show`, we found that all 10 tests failed in the same test run with the same crash. The failure details showed:
- `issue_type: "assertion_failure"`
- `message: "Crash: xctest at Matcher.register<A>(_:)"`
- `line_number: 0`, `path: ""` (process crash, not assertion)

This wasn't individual test flakiness — the entire test process crashed.

**Root cause: Thread-unsafe Matcher.register called from parallel test init()**

The tests used `Matcher.register([GraphTarget].self)` in their `init()` method. Under Swift Testing, test struct `init()` runs in parallel. The `Matcher` class in the Mockable framework uses a plain `private var matchers: [MatcherType] = []` with no synchronization — concurrent `append()` calls cause a data race crash.

From Mockable's source (`Matcher.swift`):
```swift
public class Matcher {
    private var matchers: [MatcherType] = []
    #if swift(>=6)
    nonisolated(unsafe) private static var `default` = Matcher()
    #endif

    private func register<T>(_ valueType: T.Type, match: @escaping Comparator<T>) {
        matchers.append((mirror, match as Any))  // NOT thread-safe
    }
}
```

**Fix: Remove redundant Matcher.register calls**

All the registered types (`GraphTarget`, `XCActivityIssue`, `XCActivityBuildFile`, `XCActivityTarget`) are `Equatable`. Mockable automatically handles `Equatable` types and `Equatable` sequences — no explicit registration needed. The calls were redundant and causing crashes.

**Files changed:**
- `cli/Tests/TuistKitTests/Services/ShareCommandServiceTests.swift` — removed `Matcher.register([GraphTarget].self)`
- `cli/Tests/TuistKitTests/Services/Inspect/InspectBuildCommandServiceTests.swift` — removed 3 `Matcher.register` calls

**Verification:** 5 iterations with `--run-tests-until-failure`, 0 failures.

### Fix 2: InitCommandServiceTests Shared Manifest Cache (1 quarantined test)

**Affected test:** `InitCommandServiceTests/generatesTheRightConfiguration_whenGeneratedForOrganization_andConnectedToServer`

**Failure message:**
```
Error Domain=NSCocoaErrorDomain Code=4 "couldn't be removed."
NSFilePath=/Users/runner/.cache/tuist/Manifests/1.75e47a76431312c6b98975b5bdf1bda7
NSUnderlyingError=NSPOSIXErrorDomain Code=2 "No such file or directory"
```

**Investigation process:**

Using `tuist test case run show`, we found a real error (not a crash) at the FileSystem library level. The error came from a different test run than the Matcher crash — this was a genuine file system race.

**Root cause: Test using a real InitGeneratedProjectService that hits the shared manifest cache**

The test used a real `InitGeneratedProjectService` instead of a mock. This service triggers a chain of real dependencies:

```
InitGeneratedProjectService.run()
  → TemplateLoader.loadTemplate()
    → ManifestLoader.current (@TaskLocal → CachedManifestLoader())
      → CacheDirectoriesProvider() → ~/.cache/tuist/Manifests/
```

Multiple parallel tests sharing the same global cache directory caused a TOCTOU race in `CachedManifestLoader.write()` — a check-then-remove pattern where the file could be deleted between the existence check and the removal attempt.

**Fix: Mock InitGeneratedProjectService to isolate the test from the manifest cache**

The test only verifies the `Tuist.swift` content written by `InitCommandService` directly — it doesn't need the real template scaffolding. Replacing `InitGeneratedProjectService()` with `MockInitGeneratedProjectServicing()` eliminates access to the shared manifest cache entirely.

```swift
// Before: real service that hits ~/.cache/tuist/Manifests/
private let startGeneratedProjectService = InitGeneratedProjectService()

// After: mock that returns immediately
private let startGeneratedProjectService = MockInitGeneratedProjectServicing()
```

**File changed:** `cli/Tests/TuistKitTests/Services/InitCommandServiceTests.swift`

**Verification:** 5 iterations with `--run-tests-until-failure`, 0 failures.

### Not Fixed: Acceptance Tests (6 tests, server/network issues)

**Affected tests:** ShareAcceptanceTests (4), TuistCacheEEAcceptanceTests (2)

**Failure patterns identified:**
- `.unknownError(502)` — Server 502 errors
- `NSURLErrorDomain Code=-1005 "The network connection was lost"` — Transient network failures
- `.conflict("An app build with the same binary ID already exists")` — Test retries re-upload the same build
- `.appNotFound(...)` — Preview URL not yet available after retry upload

These failures are all server/network infrastructure issues that occur during test retries. The second repetition of an acceptance test tries to re-upload the same app, causing conflicts. These aren't fixable in the test code — they would require either server-side idempotency or changes to the test retry infrastructure.

## Summary

| Category | Tests Fixed | Root Cause | Fix Type |
|----------|-----------|------------|----------|
| Matcher.register crash | 10 | Thread-unsafe static mutation in parallel Swift Testing | Removed redundant calls |
| InitCommandServiceTests cache | 1 | Real service hitting shared manifest cache | Mock InitGeneratedProjectService |
| Acceptance test server issues | 0 (6 total) | Network/server infrastructure | Not fixable in test code |

**Total: 11 out of 17 flaky tests fixed** by addressing 2 root causes.

## Reproduction Attempts

Neither race condition could be reproduced locally, despite multiple strategies:

| Strategy | Matcher.register | CachedManifestLoader TOCTOU |
|----------|-----------------|----------------------------|
| 20 iterations, parallel testing | No failure | No failure |
| Thread Sanitizer (single suite) | No detection | N/A |
| Thread Sanitizer (full module) | No detection | N/A |
| Broad scope (all TuistKitTests) | No failure | N/A |

Race conditions are inherently timing-dependent. The Matcher crash appeared once across hundreds of CI runs. CI runners have different parallelism levels, resource contention, and scheduling than local development machines. Both fixes are validated by code analysis: the Mockable `Matcher` provably mutates shared state without synchronization, and the TOCTOU pattern is a textbook race condition.

## Skill Updates

Based on this experience, the skill was updated with:

1. **Discovery section** — `tuist test case list --flaky` to find all flaky tests when no specific test is provided, with triage strategy guidance
4. **Reproducing race conditions** — New verification section with strategies: increased parallelism, broader test scope, Thread Sanitizer, and guidance for when races can't be reproduced locally
5. **Reproducing before fixing** — New section encouraging reproduction attempts before applying fixes, while noting that some scenarios (race conditions, CI-specific timing) may not reproduce locally and fixes based on code analysis are still valid

## Skill Feedback

The `fix-flaky-tests` skill workflow was effective. Some observations:

1. The `tuist test case list --flaky` command was the perfect starting point — it immediately surfaced all 17 flaky tests
2. The `tuist test case run show` command was critical for getting failure messages and distinguishing between process crashes vs real test failures
3. The `--flaky` filter on `tuist test case run list` helped focus on problematic runs
4. Having the test case identifier format documented (`Module/Suite/TestCase`) was helpful
5. The "Common Flaky Patterns" section in the skill correctly identified both patterns we found (shared state / race conditions)
