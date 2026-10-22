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
- `bridge.rs` accepts JSON commands (`begin`, `complete`, `restore`, `ai_accounts`, `time_off`, `business`). `accounts.rs` implements only the fixed, owner-scoped `/api/me/llm-providers` lifecycle routes. It validates sessions without refreshing, uses bearer authentication, filters responses through metadata/device-login types, validates OpenAI verification links and polling intervals, and returns fixed error messages. Never accept arbitrary API paths, owner IDs, or raw provider response objects. Pending grants,
  registrations, and sessions are opaque JSON to native storage adapters. Tokens,
  state, and verifiers must not appear in logs, Debug implementations, errors, or
  analytics. Errors expose fixed categories/messages, never raw transport bodies.
- `time_off.rs` implements only the fixed owner-scoped `/api/me/time-off` list/create/update/cancel routes. It validates calendar dates and request IDs before networking, filters responses through personal request/public-holiday types, and never accepts owner/status/approval parameters or an arbitrary path. The API transport has feature-specific fixed error mappings so holiday errors do not become account-login expiry errors. Keep Rust sources in both production Once targets and test sources in the host test target.
- `themes.rs` implements `themes` (fixed public GET on the selected origin), `validate_themes` (including cached catalogs), and `default_themes` (bundled Atlas). Treat this as optional appearance data, never an authentication requirement. Public transport attaches no bearer token and never maps 401/403/404/501 to rejected credentials. Validate the version, stable IDs, limits, opaque colors, radii and WCAG contrast; serialize only allowlisted fields. Native adapters own per-origin preferences and cache, using separate workers and generation guards. Do not add theme networking to the credential queue.
- `business.rs` implements allowlisted tasks/accounts/invoices CRUD and task completion under `/api/native`, plus read-only caller Profile. Validate fields/IDs/dates before networking and filter response fields; preserve decimal strings and currency-separated summaries. Server contexts remain authoritative for scopes, manual-invoice provenance and audit attribution. Keep feature networking independent after serialized session refresh/persistence so unrelated work can run in parallel.
- `presence.rs` implements `presence` actions `open` (validated session), `update` (allowlisted resource/record), `next` (local bounded wait after a sequence), and idempotent `close`. A Rust worker owns one persistent `/presence/websocket?vsn=2.0.0` WSS connection per opaque in-memory handle, joins `presence:team`, sends Phoenix heartbeats, and reconnects with bounded backoff. The access token is a Phoenix bearer subprotocol, never a query parameter. No native HTTP snapshot polling or Swift/Kotlin WebSocket SDK is used. Only the latest sanitized snapshot is retained; `location` echoes the caller's own requested location so views reject stale navigation results. `needs_session` asks the native coordinator to close, refresh/persist, and reopen when access credentials expire. Event waits run independently of credential serialization; close must wake an in-flight wait. The server preserves authenticated availability without same-location hints for inaccessible/deleted locations, returning the existing snapshot shape so clients can navigate again on the same connection; cover this fallback in the mock WebSocket tests.
- Business `list` accepts optional default-empty `filters: BTreeMap<String, String>`. Validate resource-specific keys and values before networking, then encode each as an ordinary top-level query parameter alongside page/search, never nested `filters[...]`. Tasks allow status (`open`, `completed`), assignee UUID, reminder (`overdue`, `upcoming`, `none`), and `group_by=reminder`; accounts allow schema segment/status/deal-stage enums; invoices allow schema status. Keep these allowlists aligned with the [server contract](../../atlas/lib/atlas_web/controllers/AGENTS.md). Empty values mean All/no grouping only for allowed keys. Unknown/wrong-resource keys, including page/query overrides, must fail locally. Profile accepts no filters. Forward task `reminder_group` as a read-only response field, never a mutation attribute. The server owns the UTC cutoff and global grouping before 25-row pagination; native feature models append pages without recomputing groups or filtering partial data.
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
