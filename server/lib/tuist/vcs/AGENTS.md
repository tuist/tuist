# VCS

## Origin reporting
- Shared report rendering supports GitHub and native Origin through separate clients and account-owned installation records. See `../origin/AGENTS.md` for Origin authentication and lifecycle handling.
- A failed comment-list request must propagate an error to Oban, not masquerade as an empty list and create a duplicate report. Match both the provider's app identity and the Tuist report prefix before updating.

## Responsibilities
- Model VCS entities (comments, users, installations, repositories).
- GitHub Enterprise installations retain `client_url` as the canonical browser/instance identity. Optional `api_url` is a full REST base URL for server-side transport only; resolve it with `VCS.installation_api_url/1`. Nil preserves existing URL derivation. Keep URL validation, signed registration state, and data-export documentation aligned.
- Provide workers for VCS-related background tasks.
- Render the pull request run report (`Tuist.VCS.post_vcs_pull_request_comment/1`). Its Tests section shows Xcode runs per scheme (the newest run of each). Every other build system gets one roll-up row for its latest commit, the way coverage reports a commit: the newest run per scheme on that commit, runs without a scheme included, and `Tuist.Tests.Analytics.test_case_counts/2` counting distinct test cases across them, failed when any run failed one.

## Guardrails
- PR comments use only authenticated or historical reports, never network-trusted submissions, including cross-run flaky details. Unsigned telemetry must not replace a scheme's result or select the latest commit for a build-system roll-up.
