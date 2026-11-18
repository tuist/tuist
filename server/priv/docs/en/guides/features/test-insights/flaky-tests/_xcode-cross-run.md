### Cross-run detection {#cross-run-detection}

Even without test retries, Tuist can detect flaky tests by comparing results across different CI runs on the same commit, scheme, and reported destination (device name, platform, and OS version). If a test passes in one matching CI run but fails in another, the failing execution is marked as flaky. This works regardless of which result arrives first.

The same test can behave consistently differently across schemes or destinations. For example, passing on iOS 26 and failing on iOS 27 does not establish flakiness. Results from different schemes, devices, platforms, or OS versions do not flag each other as flaky.

Runs without destination metadata, or covering several destinations, are compared only with each other, so environment differences between them can still be reported as flaky. Retry-based detection still applies.

This is particularly useful for catching flaky tests that don't fail consistently enough to be caught by retries, but still cause intermittent CI failures.
