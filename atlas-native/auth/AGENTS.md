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
- `bridge.rs` accepts JSON commands (`begin`, `complete`, `restore`, `native`, `ai_accounts`, `time_off`, `business`, `presence`, `push`, `orbit_session`, and theme commands). `accounts.rs` implements only the fixed, owner-scoped `/api/me/llm-providers` lifecycle routes. It validates sessions without refreshing, uses bearer authentication, filters responses through metadata/device-login types, validates OpenAI verification links and polling intervals, and returns fixed error messages. Never accept arbitrary API paths, owner IDs, or raw provider response objects. Pending grants,
  registrations, and sessions are opaque JSON to native storage adapters. Tokens,
  state, and verifiers must not appear in logs, Debug implementations, errors, or
  analytics. Errors expose fixed categories/messages, never raw transport bodies.
- `time_off.rs` implements only the fixed owner-scoped `/api/me/time-off` list/create/update/cancel routes. It validates calendar dates and request IDs before networking, filters responses through personal request/public-holiday types, and never accepts owner/status/approval parameters or an arbitrary path. The API transport has feature-specific fixed error mappings so holiday errors do not become account-login expiry errors. Keep Rust sources in both production Once targets and test sources in the host test target.
- `orbit_session.rs` is the shared thread feature model. `open` creates an opaque session-scoped handle; authenticated `request` commands update its credential snapshot and execute feature actions. Local `draft`, `active`, `next`, and `close` actions never require credential serialization. Draft, send, and leave carry the originating thread ID so late UI actions cannot target a newly selected thread; send also captures the text at tap time, while Rust owns its stable retry key. The model owns pagination, deduplication and ordering by server sequence, retained drafts and stable retry IDs, stale-selection fencing, and revocation cleanup. Swift/Kotlin render its monotonically sequenced snapshots rather than reimplementing those rules. `orbit.rs` filters the fixed `/api/native/orbit/threads` contract; `orbit_live.rs` uses the same authenticated WSS endpoint as presence but joins only the fixed inbox topic `orbit:me` or a validated `orbit:thread:<uuid>`. Inbox invalidations reload the authorized list, so monitored sessions appear without client polling. Live notifications invalidate authoritative HTTP history; they are not the durable event log. A refresh request replaces expired credentials and reopens live viewing. All handles are memory-only and must close at sign-out.
- Direct `orbit_session` `select` accepts a validated UUID even outside loaded pages and reads only fixed `Messages { id, page: 1 }`. Additive snapshot `selection_id` is a navigation intent for Back/Retry, never authoritative metadata; `selected` stays null until matching protected history succeeds. Do not synthesize Thread metadata or page the list to resolve a link. `has_drafts` reports retained nonblank drafts across threads for platform protected-work guards. Unavailable reads revoke cached rows, history, presence and that thread's drafts/retry IDs, retain the target for explicit Retry, and invalidate older list/detail results; superseded failures cannot revoke a newer selection. Shared state tests inject transport at the actual typed route boundary, including unseen IDs, denial, mismatched metadata, retry, supersession and close.
- `orbit_components.rs` filters the server-authored `result_table` v1 contract: at most three columns, five rows, bounded strings, one `show_evidence` action, no extra executable/navigation fields. Invalid/unknown versions drop only the component and preserve original tool evidence. Local `orbit_session` `component_action` events require the current active selected thread and a matching succeeded tool message's server-provided action; the sole effect reveals existing source evidence. No model run, business mutation, arbitrary request or thread state is authored by the client.
- `themes.rs` implements `themes` (fixed public GET on the selected origin), `validate_themes` (including cached catalogs), and `default_themes` (bundled Atlas). Treat this as optional appearance data, never an authentication requirement. Public transport attaches no bearer token and never maps 401/403/404/501 to rejected credentials. Validate the version, stable IDs, limits, opaque colors, radii and WCAG contrast; serialize only allowlisted fields. Native adapters own per-origin preferences and cache, using separate workers and generation guards. Do not add theme networking to the credential queue.
- `push.rs` implements only bearer-authenticated PUT/DELETE `/api/me/push-devices/:installation_id` through the `push` bridge command. Register accepts platform, token and environment (`sandbox|production`, Android production only), never an owner/app/topic/endpoint selector. UUID/token validation precedes networking; responses expose only registered/deleted status and the server registration UUID, never the token. Native coordinators own opt-in, device-only installation storage and logout cleanup. A deleted installation ID is terminal: clients rotate it only after successful cleanup. Keep this source in all three production Once targets.
- `business.rs` implements allowlisted tasks/accounts/invoices CRUD and task completion under `/api/native`, plus read-only caller Profile. Validate fields/IDs/dates before networking and filter response fields; preserve decimal strings and currency-separated summaries. Server contexts remain authoritative for scopes, manual-invoice provenance and audit attribution. Keep feature networking independent after serialized session refresh/persistence so unrelated work can run in parallel.
- Optional account `details` and invoice `finance_overview` are typed read-only projections. Filter every related record's fields, drop account details from non-account resources and bank overview from non-invoice resources, and never expand write allowlists to include them. Preserve nullable metrics and exact converted decimal strings. Missing additions remain compatible with older servers; the server owns document-summary permissions and FX conversion.
- Orbit HTTP/live snapshots retain typed optional `agent_status`. Apply every authorized live status update to the selected thread even when the message revision is unchanged; never synthesize activity from elapsed time or leak status after selection/access-loss fences. `account_card` v1 shares existing bounds/actions but requires exact `Field`/`Value` columns; unknown/malformed types retain original evidence.
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
  exposing a signed-in state. Authenticated API calls restore through the same coordinator to avoid concurrent refresh-token reuse. Both native adapters persist rotated credentials before making an API request, including when that request subsequently fails. iOS shares the main-actor credential coordinator and session identity across Automation and business features; Android's application-scoped coordinator shares its credential worker across activities and drains pending login cancellation before shutdown. Keep Automation HTTP/watch waits on separate bounded workers, not the refresh queue.

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

## Orbit attachments and tool hierarchy

`orbit_session` authenticated request commands include `upload_attachment`
(`id`, `filename`, `content_type`, standard-base64 `data`; optional `client_id`),
`retry_upload`/`discard_upload` (`id`), and `delete_attachment`/`download_attachment`
(`id`, `attachment_id`). Rust generates the upload UUID, retains one bounded uncertain
payload in memory, and reuses exactly that UUID/payload on retry. Submit picker batches
sequentially. Snapshot additions are `draft_attachments` (typed metadata),
`attachment_busy`, `upload_pending`, and nullable `upload_filename`; no bytes belong in
snapshots. Local text `draft` preserves uploaded files. `has_drafts` includes files and
uncertain uploads across threads. Send captures optional `attachment_ids` (default:
current draft), supports attachment-only messages, and blocks unresolved uploads.
Retry identity covers both text and files; a successful send removes sent files but
preserves newer typing. Close/revocation releases pending bytes and retry state.

All attachment routes are fixed `/api/native/orbit/threads/<uuid>/attachments[/<uuid>]`
with the selected session's bearer token. Only upload bridge envelopes and typed
attachment download HTTP responses may exceed the normal 1 MiB cap: their cap is
7 MiB + 64 KiB, with decoded files independently limited to 5 MiB and four files per
message. Validate base64, UUIDs, bounded names/types/sizes before mutation and filter
returned metadata. Accept validated server-canonical filenames (120 codepoints), not
an exact echo of the requested display name; require exact uploaded size/content type.
No public URLs, arbitrary routes, local paths, or bytes in errors/logs are allowed.
Download returns `{thread_id, attachment:{id,filename,content_type,byte_size,data}}`
instead of a snapshot, only for known protected message/draft metadata and the current
foreground selection. Selection, lifecycle, close, and revocation fence late bytes.
Discarding an uncertain upload releases local state; without a confirmed remote ID it
cannot promise synchronous remote deletion. Known pending chips use authenticated DELETE.

Messages default missing `attachments` to empty. Optional `parent_message_id` is UUID
metadata, never inferred from tool names/output; malformed linkage drops only the
link, preserving evidence. Platform trees must keep orphan/off-page, cyclic, and
deeper-than-one-level claims inspectable rather than silently hiding child messages.
Rust tests inject the actual typed transport/state boundary and exercise the real
bounded HTTP response reader, not a parallel imitation of session behavior.
