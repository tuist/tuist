# Vcs (Context)

This context owns VCS models and GitHub App integrations.

## Responsibilities
- Model VCS entities (comments, users, installations, repositories).
- GitHub Enterprise installations retain `client_url` as the canonical browser/instance identity. Optional `api_url` is a full REST base URL for server-side transport only; resolve it with `VCS.installation_api_url/1`. Nil preserves existing URL derivation. Keep URL validation, signed registration state, and data-export documentation aligned.
- Provide workers for VCS-related background tasks.
- Render the pull request run report (`Tuist.VCS.post_vcs_pull_request_comment/1`). Its Tests section shows Xcode runs per scheme (the newest run of each). Every other build system gets one roll-up row for its latest commit, the way coverage reports a commit: the newest run per scheme on that commit, runs without a scheme included, and `Tuist.Tests.Analytics.test_case_counts/2` counting distinct test cases across them, failed when any run failed one.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
