# Authentication

This module owns the shared iOS/macOS authentication service, persisted account/server identity, and self-hosted OAuth registration.

- `WebAuthenticationSession` owns the system session and its presentation provider until completion. Start it on the main actor, check `start()`'s result, and complete rejected starts immediately instead of awaiting a callback that may never arrive.
- Only the system's cancelled-login error is silent. Surface presentation/start failures so the caller's signing-in state resets and the user can retry.
- Request identities isolate late callbacks and cancellation from subsequent attempts. Release completed sessions and cancel the system session when its task is cancelled.
- Use the system's callback-matching API, an ephemeral browser session, and an anchor from the app's window (or foreground iOS scene). Do not launch a separate custom browser or bypass system consent. Desktop sign-in exposes Cancel so an unresponsive browser never traps the welcome screen.
- Preserve PKCE, callback scheme/host/state validation, issuing OAuth client IDs, HTTPS validation, and server/account-scoped credential storage. Do not log authorization URLs, callback codes, or credentials.
- `AppServerInfoService` lazily reads optional deployment metadata from `/.well-known/tuist` for Profile/Account settings. Keep discovery independent of sign-in and capabilities: older servers, missing/null fields, unknown fields, arbitrary version strings, and failures must not block the app. Use a cookie/credential-free ephemeral session with normal TLS checks and no redirects. Keep the service a stateless `Sendable` struct, without an actor, singleton instance, or application-level metadata cache. Bound downloads while reading, not after allocating the entire response. Never attribute a cancelled or stale response to another session. The contract is documented in `server/server-info.md`.
- Test session startup, lifetime, cancellation, errors, and retries with injected session stubs, never a developer's browser or Keychain.
