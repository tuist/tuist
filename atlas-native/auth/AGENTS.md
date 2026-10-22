# Shared native authentication

This crate owns OAuth discovery (RFC 8414), dynamic public-client registration
(RFC 7591), authorization code + S256 PKCE, callback validation, token exchange,
and refresh. Atlas already provides the required endpoints; native apps use the
existing server login page rather than implementing Google sign-in themselves.

## Boundaries

- Rust owns all OAuth HTTP requests and protocol decisions. `transport.rs` uses
  one connection-pooled HTTPS client, rejects redirects, and bounds request time
  and response size. Endpoint origins must match the selected server. Do not
  disable certificate validation or cache token responses as build artifacts.
- `bridge.rs` accepts JSON commands (`begin`, `complete`, `restore`, `native`). Pending grants,
  registrations, and sessions are opaque JSON to native storage adapters. Tokens,
  state, and verifiers must not appear in logs, Debug implementations, errors, or
  analytics. Errors expose fixed categories/messages, never raw transport bodies.
- C inputs are borrowed NUL-terminated strings. Outputs are owned allocations and
  must be freed exactly once using `atlas_auth_free`. JNI uses VM-managed strings.
- The calling native coordinator owns secure storage and serializes credential
  mutations. Rust does not persist anything or call platform APIs. This keeps
  platform SDKs out of host tests and avoids a global runtime/session lock.
- iOS presents ASWebAuthenticationSession; Android presents the system browser
  and receives its registered custom-scheme callback. Rust validates the complete
  callback destination, state, duplicate parameters, and ten-minute login lifetime.
  Android stores pending grants encrypted so callbacks survive process recreation;
  invalid callbacks must not discard another pending login.
- Sessions persist server origin, token endpoint, issuing client ID, tokens, and
  expiry together. Refresh uses that issuing client, preserves a refresh token when
  omitted by rotation, and distinguishes definitive OAuth rejection from temporary
  server/transport failure. Native adapters persist rotated credentials before
  exposing a signed-in state. Future authenticated API calls must restore through
  the same coordinator to avoid concurrent refresh-token reuse.

## Native API and forms

`api.rs` owns an allowlisted Automation request enum, same-origin bearer HTTP and
bounded TLS Phoenix subscriptions. Credentials travel in the WebSocket subprotocol,
never query parameters. Each watch returns on a changed durable sequence or a bounded
wait; native lifecycle cancellation and reconnect reconciliation own presentation.
HTTP/watch waits do not hold a global session lock. Fixed error categories/messages
never copy arbitrary response bodies. Responses/frames are limited to 1 MiB; protected
result reads are separate and oversized-result errors direct users to web. Approval
payloads and results arrive as server-serialized JSON strings, not numeric maps to
round-trip through platform JSON number types; preserve that text verbatim.

`form.rs` conservatively projects at most 32 scalar controls and four object levels.
Strings/text, string enums, dates, booleans and numbers are supported; required object
groups preserve missing/false/zero distinctions. Unsupported unions, arrays, references,
optional object groups and required empty groups fall back to web. Native validation
is only usability: the pinned server contract remains authoritative.

## Build and test

The root Once graph has independent host, iOS and Android Cargo dependency targets,
then compiles each dependency as a separate cacheable crate. Navigation and the CLI
have no dependency on this crate. Auth tests live in `src/tests.rs`, excluded from
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
