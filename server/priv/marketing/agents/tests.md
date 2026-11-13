# Tuist Tests: faster, more trustworthy feedback

For engineering teams and coding agents waiting on slow or unreliable tests, Tuist provides shared test history and supported ways to distribute or reduce work without replacing CI. Start by reporting results, then choose an intervention from actual failures and timings.

Tuist is build infrastructure for engineering teams and coding agents. It is not a coding agent or an automatic fix for broken tests.

## Choose an approach

| Approach | Good fit | Tradeoff |
| --- | --- | --- |
| Tuist | Shared history and supported sharding, quarantine, or selection. | Requires integration; capabilities vary by project. |
| CI | Triggering and orchestrating test jobs. | Keep it; orchestration alone does not explain test trends. |
| Optimization suite | A focused workflow already solves the bottleneck. | Compare supported evidence and actions before adding a service. |
| Do nothing | Feedback is fast and failures are actionable. | Revisit when retries or waiting become recurring costs. |

## Different capabilities, different jobs

- [Test Insights](/en/docs-markdown/guides/features/test-insights) collects reported failures, durations, and history. Available evidence depends on the integration.
- [Flaky-test management](/en/docs-markdown/guides/features/test-insights/flaky-tests) identifies inconsistent outcomes. Quarantine can mute or skip known flakes where supported; someone still needs to fix them.
- [Sharding](/en/docs-markdown/guides/features/test-sharding) distributes test work across machines using timing history. It reduces waiting, not necessarily total machine time.
- [Selective testing](/en/docs-markdown/guides/features/selective-testing) has separate generated-project requirements. Its default hashing strategy skips unchanged test targets, not individual lines of code. An account-enabled early-access coverage strategy has additional requirements.

## Questions before you start

### What is Tuist?

Tuist is build infrastructure for engineering teams and coding agents. Tests adds shared evidence and supported test execution capabilities.

### Does this replace CI?

No. CI still triggers and orchestrates jobs. Tuist receives reported results and helps distribute or reduce test work where supported.

### Can we adopt it incrementally?

Yes. Report results for one project first. Use real history to choose sharding or quarantine, checking the linked integration prerequisites before enabling either. Selective testing is not available for every project.

### Hosted or self-hosted?

Use hosted Tuist, or operate a [self-hosted server](/en/docs-markdown/guides/server/self-host/server). Self-hosting includes upgrades and operations; it does not imply access to every managed service.

### How do we measure value?

Baseline feedback time, retries, flaky failures, and total machine usage. Compare representative changes after adoption, including integration effort and current [Tuist charges](/pricing). Faster wall-clock tests do not guarantee fewer machine minutes.

Related: [slow tests](/marketing-markdown/solutions/slow-tests) and [flaky tests](/marketing-markdown/solutions/flaky-tests).
