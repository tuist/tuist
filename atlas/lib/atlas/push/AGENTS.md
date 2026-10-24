# Native push notifications

`Atlas.Push` separates product intent from platform delivery. Product code calls
`notify_user(user_id, "activity", {screen, record_id})` with a fixed kind from
`@kinds` (`activity`, 24-hour lifetime; `self_test`, 10 minutes;
`orbit_completed`, one hour) and a destination
accepted by `AtlasWeb.NativeLinks.for_open/1`. It never supplies text, tokens, or
devices. Activity and self-test alerts remain generic. Orbit completion is an
explicit content-preview exception described below. Adding a kind means adding it
to `@kinds` with a delivery lifetime; there is no HTTP or MCP path that sends
arbitrary text or targets another user. The only MCP entry point is `send_test_push_notification`, which sends the
self-test kind to the caller's own registrations under a per-user rate limit.

## Orbit completion

- The successful, authorized branch of `Orbit.Runs.finish!` queues only for the
  run's `acting_user_id`, with destination `{"orbit", thread.id}` and
  `message_id: final_agent_message.id`. The existing attempt/cancellation/access
  fence covers reply, succeeded status and job insertion in one transaction.
  Rollback retries cannot duplicate jobs; replay after success is stale. Failed,
  interrupted, empty, cancelled, superseded and unauthorized runs do not notify.
- Existing native registrations are the opt-in: no registrations, retired/ended
  sessions or unconfigured providers enqueue no deliveries and never block a reply.
  There is no new per-kind preference, infrastructure, or externally callable send.
- Every delivery attempt reloads the active thread, user, exact agent message and
  its succeeded run. Membership and ratcheted scopes must still authorize the
  user; message and run must both belong to that thread, and the run's acting
  user must match the registration owner. Missing/archived/deleted/inaccessible
  sources cancel as `destination_unavailable`, without retiring the registration
  or contacting providers. Never substitute the latest reply from another run.
- The alert title is fixed to "Pip finished". The body contains the thread title
  (80 Unicode codepoints) and a plain-text final-reply preview (160 codepoints),
  with ellipses, whitespace/control-character cleanup, and no Markdown links,
  HTML tags or fenced code. Codepoint bounds also cap UTF-8 bytes, even for
  combining-mark-heavy text. Only the authorized final agent body is used, never
  tool cards, raw tool results, checkpoints or diagnostics. Jobs/audits retain
  IDs only, not preview text. The preview goes to APNs/FCM and can appear on a
  lock screen according to the user's OS preview settings.
- `orbit_completed` accepts only an Orbit UUID destination and requires a UUID
  `message_id` option; neither HTTP nor MCP accepts arbitrary notification text.
  Other kinds keep their existing destination/delivery semantics.

## Registrations

- `push_installations` is keyed by the client-generated `installation_id` (lowercase
  UUID). `id` is the server registration ID returned to clients and carried in
  payloads so Android can drop messages for an older registration.
- Tokens are encrypted with the Cloak vault. `token_hash` is SHA-256 of
  `platform:token` and enforces one live owner per device token through a partial
  unique index. Responses, logs, audits and Oban arguments never contain tokens.
- Retired rows are tombstones: owner and token cleared, installation ID kept, and
  any later registration of that ID returns `:retired`. Clients rotate the UUID
  after a successful DELETE or a 409 `installation_retired`. Deleting an unknown ID
  inserts a tombstone, so a registration that arrives after its deletion cannot
  create the row.
- Ownership never moves between users. A live row owned by someone else may only be
  retired (`owner_changed`) by the same OAuth client or the same device token, which
  proves the same app installation; the caller then rotates. Otherwise `:conflict`.
  The same token under another installation ID retires the older row (`superseded`).
- DELETE retires when the caller owns the row or presents the same OAuth client,
  which lets the next signed-in user on that app clean up after an offline sign-out.
  Other users' rows are untouched, and the response is identical either way.
- Concurrency: a transaction-scoped advisory lock per installation ID serializes
  requests, including first inserts. Users keep at most ten live rows (oldest are
  `evicted`). `Push.Workers.Prune` retires rows not refreshed for 60 days (`stale`)
  and deletes tombstones after 180 days.

## Session binding

A registration is deliverable only while the OAuth client it was registered through
still holds an active refresh grant for the same user in `oauth_tokens`: an
`access_token` row with a refresh token, null `revoked_at` and
`refresh_token_revoked_at`, and `inserted_at + oauth_clients.refresh_token_ttl` in the
future (timezone-less UTC wall time, as in `Atlas.OAuth.AccessTokens`). Refresh
rotation inserts the new row and consumes the previous one in one transaction, so
normal rotations keep exactly one active grant. Revocation, an expired refresh TTL,
or a client the app discarded after a rejected refresh ends the grant. Fan-out skips
such rows, the worker retires them as `session_ended` at send time without
contacting providers, and `Push.Workers.Prune` sweeps up to 1,000 per run. The
lookup is an `EXISTS` bounded by the `(client_id, value)` unique index.

Residual: if a client loses a rotated refresh token that the server did commit (for
example a crash between rotation and secure persistence), the server still sees an
active grant until its refresh TTL expires. The native app's local disabled state
and Android registration filtering cover delivery display in that window.

## Delivery

- `Workers.Deliver` (queue `push`) holds IDs, kind, destination and expiry only. Each
  attempt revalidates the kind/destination, reloads the row and requires it to be
  live and owned by the job's user; sign-out, account switches and invalidation
  therefore cancel queued work. The worker declares uniqueness on
  `[registration_id, notification_id]`; `Oban.insert_all/1` on the Basic engine does
  not enforce it, so fan-out relies on a fresh notification ID per call and one job
  per registration.
- Payloads (`Message`) use the fixed title "Atlas" and body "You have a new
  notification" for activity/self-test, or the authorized Orbit context above.
  Both use `schema_version` 1, `registration_id`, and `url` from
  `NativeLinks.native_url/1` (configured origin, never the request Host). APNs puts
  them at the payload root with a numeric version; FCM sends data-only, high-priority
  messages with string values plus `notification_id`, which the app uses as the
  local notification tag. FCM gets no `collapse_key` (only four are kept per
  device); APNs uses the notification ID as `apns-collapse-id`.
- Invalidation is compare-and-retire on `id`, `token_hash` and `environment` (and, for
  APNs 410, a `last_registered_at` older than Apple's timestamp, because the same
  token may be re-registered after it was invalidated). Only APNs 410 / `BadDeviceToken`
  and FCM `UNREGISTERED`, `SENDER_ID_MISMATCH`, or `INVALID_ARGUMENT` naming
  `message.token` retire. Other 4xx responses are configuration or payload errors:
  the job is cancelled and registrations are kept.
- 429/500/503 and transport failures retry with exponential backoff (5 attempts) or
  snooze for `Retry-After` while the notification is still useful; anything past
  `expires_at` is cancelled, and APNs/FCM receive the remaining lifetime.
- `Credentials` caches APNs ES256 provider JWTs for 50 minutes and FCM OAuth tokens
  until five minutes before expiry, per node and per credential identity. Misses
  take a node-local `:global.trans` lock per key and recheck, then generate in the
  caller's process; expired-credential responses drop the entry. `Atlas.HTTP` always adds dedicated HTTP/2 pools for both APNs hosts.
- `Config.parse!/1` reads `ATLAS_APNS_TEAM_ID`, `ATLAS_APNS_KEY_ID`,
  `ATLAS_APNS_PRIVATE_KEY` (the `.p8` PEM), `ATLAS_APNS_ENVIRONMENT` and `ATLAS_FCM_SERVICE_ACCOUNT_JSON`. APNs defaults to `production`; choose `sandbox` for a sandbox-only key or `both` only for a legacy key explicitly authorized for both. Registration rejects unsupported environments, and send-time checks prevent older queued sandbox jobs from using a production-only key without retiring their device tokens.
  Providers are all-or-nothing; malformed values fail boot without echoing key
  material. The FCM token endpoint is fixed, never taken from the JSON. The APNs
  topic is fixed to `dev.tuist.atlas`. Unconfigured platforms are reported as
  unavailable; normal builds and tests need no credentials.

## Audit

`push_installation.registered` (creation, token rotation or environment change;
plain refreshes are not audited), `push_installation.retired` (reason, platform),
`push_installation.pruned` (counts), `push_notification.queued` (notification ID,
kind, screen, record ID, count) and `push_notification.delivery` (terminal outcome,
reason, kind, platform, environment). Metadata never contains tokens or alert text.

## Tests

`test/atlas/orbit/runs_test.exs` (transactional completion enqueue, opt-in and
no-notify fences), `test/atlas/push_test.exs` (registry semantics), `test/atlas/push/workers/deliver_test.exs`
(provider requests, classification, caching, send-time checks against a Req plug),
`test/atlas/push/config_test.exs`, `test/atlas_web/controllers/push_devices_controller_test.exs`
and `test/atlas/mcp/tools/send_test_push_notification_test.exs`. Tests stub
`Atlas.Push.Config` with Mimic rather than changing the application environment.
