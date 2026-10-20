# Shared native authentication

This crate owns OAuth discovery (RFC 8414), dynamic public-client registration
(RFC 7591), authorization code + S256 PKCE, callback validation, token exchange,
and refresh. Atlas provides the required endpoints; native apps use server-owned
browser authentication rather than implementing Google sign-in themselves. The
optional `begin` command's `provider: "google"` appends an allowlisted provider hint
to the discovered authorization URL, skipping the server's provider-selection page.
It never changes the origin, issuing client, callback, state, or PKCE requirements;
omitting it preserves generic browser login, including self-hosted providers.

## Boundaries

- Rust owns all OAuth HTTP requests and protocol decisions. `transport.rs` uses
  one connection-pooled HTTPS client, rejects redirects, and bounds request time
  and response size. Endpoint origins must match the selected server. Do not
  disable certificate validation or cache token responses as build artifacts.
- `bridge.rs` accepts JSON commands (`begin`, `complete`, `restore`, `ai_accounts`, `time_off`). `accounts.rs` implements only the fixed, owner-scoped `/api/me/llm-providers` lifecycle routes. It validates sessions without refreshing, uses bearer authentication, filters responses through metadata/device-login types, validates OpenAI verification links and polling intervals, and returns fixed error messages. Never accept arbitrary API paths, owner IDs, or raw provider response objects. Pending grants,
  registrations, and sessions are opaque JSON to native storage adapters. Tokens,
  state, and verifiers must not appear in logs, Debug implementations, errors, or
  analytics. Errors expose fixed categories/messages, never raw transport bodies.
- `time_off.rs` implements only the fixed owner-scoped `/api/me/time-off` list/create/update/cancel routes. It validates calendar dates and request IDs before networking, filters responses through personal request/public-holiday types, and never accepts owner/status/approval parameters or an arbitrary path. The API transport has feature-specific fixed error mappings so holiday errors do not become account-login expiry errors. Keep Rust sources in both production Once targets and test sources in the host test target.
- C inputs are borrowed NUL-terminated strings. Outputs are owned allocations and
  must be freed exactly once using `atlas_auth_free`. JNI uses VM-managed strings.
- The calling native coordinator owns secure storage and serializes credential
  mutations. Rust does not persist anything or call platform APIs. This keeps
  platform SDKs out of host tests and avoids a global runtime/session lock.
- iOS presents ASWebAuthenticationSession; Android presents the system browser
  and receives its registered custom-scheme callback. Rust validates the complete
  callback destination, state, duplicate parameters, and ten-minute login lifetime.
  Ignore URL fragments, including an empty `#`, as AppAuth does: code, state, and
  errors come exclusively from the query. Fragment parameters must never supply,
  override, or repair missing/invalid query parameters or bypass other checks.
  Destination, path, expiry, and state rejections use `invalid_callback`
  with distinct fixed messages. Never include the callback URL or its parameters
  in diagnostics.
  Android stores pending grants encrypted so callbacks survive process recreation;
  invalid callbacks must not discard another pending login.
- Sessions persist server origin, token endpoint, issuing client ID, tokens, and
  expiry together. Refresh uses that issuing client, preserves a refresh token when
  omitted by rotation, and distinguishes definitive OAuth rejection from temporary
  server/transport failure. Native adapters persist rotated credentials before
  exposing a signed-in state. Authenticated API calls restore through the same coordinator to avoid concurrent refresh-token reuse. Both native adapters persist rotated credentials before making an API request, including when that request subsequently fails. iOS queues requests/sign-out on the main-actor coordinator; Android uses its existing single worker and drains pending login cancellation before shutdown.

## Build and test

The root Once graph has independent host, iOS and Android Cargo dependency targets,
then compiles each dependency as a separate cacheable crate. Navigation and the CLI
have no dependency on this crate. Auth tests live in `src/tests.rs` and `src/accounts_tests.rs`, excluded from
production targets' declared sources, so test-only changes do not invalidate native
libraries. Do not replace this with a single cached Cargo shell action. Third-party sources are materialized from Cargo.lock with
`mise run prepare:rust`, not committed.

Run `ONCE_CACHE_PROVIDER=local mise run test:core` and `mise run lint:rust` from
`atlas-native/`. Mock transport tests exercise discovery/registration/exchange/
refresh without network access or environment changes. Swift tests exercise the
owned-string bridge, Keychain query/accessibility configuration, update/delete
semantics, and secure-storage failure handling through a process-local adapter.
Once runs iOS tests in an unhosted XCTest agent without Keychain access;
app-hosted tests are not implemented in that release. The simulator app has its
own Keychain entitlement. Real device/browser login and secure-storage smoke
checks remain part of preview validation.
