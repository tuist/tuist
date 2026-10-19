# Home Activity

Shared iOS/macOS Home models, authenticated API adapter, and SwiftUI activity cards. Recent previews remain owned by the existing preview models.

- Show at most three build failures, failed test runs, and newly flaky tests for the selected project over a rolling seven-day window. These are historical outcomes, not unresolved incidents. New flaky means the test entered its current flaky state during the window, not that it ran recently or is new to this user.
- The API contract and supported build systems are documented in `server/home-activity.md`. Do not infer features from deployment version metadata or scan paginated history on older servers. An unavailable section is not a healthy empty result; preserve previews and successful siblings.
- Capture the session server URL, credentials store, and API cache at model construction. Share the shell's `ProjectContext`, immediately hide mismatched project data and published authentication errors, and reject late results/errors. Keep macOS requests in its Keychain/in-process environment, not CLI filesystem defaults.
- Preserve existing rows during refresh failures, permit explicit per-section retry, and keep cancellation silent. Forward current authentication failures to the platform's existing error/sign-out handler; stale failures must not affect the current project.
- Open existing web details and use native sharing, with 44-point share hit targets on iOS. Dashboard paths are deployment-relative: retain the complete server base path/port and reject foreign origins, other projects, and traversal. Do not attach native tokens to browser/share URLs or add CI retries without an authorized integration.
- `HomeActivityService` is a stateless value type. The model owns only in-memory view state; no background polling or new persistence.
- Tests live in `app/Tests/TuistHomeTests`, run with the macOS `TuistHome` scheme or selected through `TuistApp`. They are unhosted, use injected transports/services and storage, and must not read developer credentials. Use production views with clearly labeled sample data for screenshots.
