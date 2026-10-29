# Native mobile HTTP boundary

## Personal account connections

Bearer-only `GET /api/me/connections` returns `{connections: [{provider, name, configured, account_name, scopes, status}]}`; `DELETE /api/me/connections/:provider` returns `{disconnected: true}` idempotently for the caller. Both use the `:native` no-store pipeline but accept non-native bearer clients too. `POST /api/me/connections/:provider/authorize` additionally runs `NativeOAuthClient` and accepts exactly `{state: <43-character base64url native nonce>}`. It returns `{authorization_url: <configured HTTPS origin>/connections/:provider/authorize?native=<signed ticket>}`; malformed inputs or missing HTTPS origin return 422. Request host headers and arbitrary redirect/callback input never select the destination.

The ticket binds bearer user, provider, native OAuth client ID and native state for 600 seconds. Browser authorize/callback retain `RequireAuth`; tickets never sign a browser in and a different browser user cannot link accounts. Provider state and PKCE are independent from native state. Validated native context is kept in the signed pending session. Provider callbacks use a PostgreSQL one-use nonce hash in addition to signed state/session matching, so replay of an old signed cookie cannot exchange twice. Valid native flows return only fixed `dev.tuist.atlas://connections-callback?state=...&provider=github|slack|google&status=connected|error`, including denial/provider failure/unconfigured providers. Invalid tickets/user mismatch fail safely on the web. Normal web flows return `/settings/connections` inside the existing account layout. Tests live in `connection_controller_test.exs`; retention/export details are in `data-export.md`.

`AtlasWeb.NativeController` serves `/api/native/tasks`, `/api/native/accounts`, and `/api/native/invoices`. The router sets `Cache-Control: no-store` before bearer authentication, including on authorization failures. Browser sessions are not accepted. Tasks are shared by all signed-in teammates. Accounts require `accounts:read`/`accounts:write`; invoices require `finance:read`/`finance:write`. Existing role helpers make write imply read. Resource names come from path parameters, never body/query parameters.

List responses contain `items`, `page`, `total_pages`, `total_count`, `can_write`, `options` (users, accounts, segments, statuses, deal_stages), and `summary`. Pages default to 1 and have 25 items, validated/run through Flop; malformed pages/search shapes return 422. `query` searches literal case-insensitive text. Records contain `id`, `fields`, `can_edit`, `can_delete`. Every field value is a string; missing optional values are empty strings, decimals are exact decimal strings, dates are YYYY-MM-DD, and reminders are UTC ISO 8601. Mutations accept top-level editable fields, not nested records. Show/create/update/complete return `{item: record}`; delete returns `{deleted: true}`.

Account show adds optional `item.details`: allowlisted string maps for overview, address, billing and signatory, plus related `{id, fields}` collections for contacts, terms, customer invoices, document metadata, activity, outcomes, service levels and children. `accounts:read` authorizes the account projection; document summaries additionally require `documents:read` and are omitted otherwise. Storage paths, document bytes and arbitrary metadata are never included. List records add read-only derived `contract_value`/`contract_currency`, `contacts_count` and `poc_end_date`; these do not expand editable fields. See [native projections](../../atlas/native/AGENTS.md).

Invoice page 1 adds optional `finance_overview`, independent of invoice search/filters. It contains `currency`, `as_of`, `account_count`, nullable `available_cash`/`monthly_burn`/`runway_months`, nullable `fx_published_on`, `excluded_currencies`, and six calendar `months` with exact decimal-string `income`/`expense`. These are the web dashboard's bank analytics in the configured reporting currency, not invoice totals; internal transfers are excluded from income/expenses. No connected accounts or missing FX produces null metrics and no months, never plausible partial totals. Later pages omit the overview value; clients preserve page 1's value while appending and replace it on refresh. Older clients retain the unchanged `summary` contract, and newer clients must tolerate older servers without these additions.

List filters are ordinary top-level URL query parameters, applied with search before Flop counts and pages. Tasks accept `status=open|completed`, `assignee_id=<UUID>`, `reminder=overdue|upcoming|none`, and `group_by=reminder`. Accounts accept `segment`, `status`, and `deal_stage` from the current account schema enums; invoices accept their schema `status`. Empty/omitted filters mean All/no grouping. Unknown or resource-inappropriate keys, invalid values, and nested/array shapes return sanitized 422 responses, even if an unknown key's value is empty. `page` and `query` remain the only common list parameters; clients cannot override page size. Invoice summaries remain unfiltered.

Task records add read-only `fields.reminder_group=overdue|upcoming|none|completed`. Capture one UTC cutoff per list request and reuse it for filtering, ordering, and every record. Completed tasks always belong to `completed`; open tasks with `remind_at <= cutoff` are overdue, those strictly after it are upcoming, and nil reminders are `none`. Neither `due_on` nor notification delivery determines the group. Grouped SQL ordering is globally overdue/upcoming/none/completed, then reminder ascending (nulls last), then ID ascending, before pagination; ungrouped requests retain the existing inserted-at/ID descending ordering. Native clients append pages for infinite scrolling rather than grouping an incomplete dataset locally. This is a read projection, not stored task metadata or a change to Slack scheduling.

Task status and display names are not editable. Blank/omitted assignees default to the caller on creation. Completion uses `POST /api/native/tasks/:id/complete`. Account enum options come from the schema. Finance mutations go through the provenance-checked manual invoice context; imported records remain read-only even for finance writers. Manual invoices require a vendor, invoice date, total and currency, default to `needs_review`, and accept optional invoice number/due date. Amounts must fit the existing 15,2 storage without rounding. Summary is unfiltered, unpaginated monthly invoice totals by original currency, not cashflow.

Invalid/missing path UUIDs return 404. Invalid fields return 422 with sanitized optional `fields`; database conflicts return 409. Missing/invalid bearer tokens return 401; scope denial and imported invoice writes return 403. The controller supplies caller/interface `api` audit context, including account operations whose domain reads that context; domain contexts own mutation audit events.

`GET /api/native/profile` returns `{server_version, user: {name, email, description}, push_notifications: {ios, android}}` for the bearer caller. `PATCH /api/native/profile` accepts exactly `{description: string}` and returns that same envelope. Only the caller's optional role/personality/preferences text is writable (4,000 Unicode codepoints / 16,000 bytes; empty clears it). Reject selectors, identity/role fields, nested/null values and NUL; it grants no other profile/settings writes. Older servers/clients may omit the additive description field. The push map reports which providers this server has credentials for; older servers omit it, which clients treat as unavailable. Its version is the running OTP application's `Application.spec(:atlas, :vsn)`, compiled from `ATLAS_VERSION` in `mix.exs`; do not substitute MCP's protocol version or invent a revision. AI connections reuse `/api/me/llm-providers`.

Controller regressions live in `test/atlas_web/controllers/native_controller_test.exs`. Profile descriptions use `users.description`; see the retention/provider/export rules in `data-export.md`.

## Business routing profile

`GET`/`PUT /api/me/business-profile` use the bearer-only no-store pipeline and
return `{business_profile: {enabled, role, expertise, responsibilities}}`. PUT
requires exactly those four fields; unknown selectors, NUL and invalid shapes
return 422. This opt-in shared routing profile is separate from private Pip
description/identity and has matching caller-only MCP tools; no native editor is
added yet. Signal source/ingest/queue/decision endpoints share Automation's existing
API/MCP inventory under `/api/automation` and add source-specific authorization.

## Native Moodboard capture

`NativeMoodboardController` uses the same bearer-only `no-store` pipeline, before dynamic resource routes. POST `/api/native/moodboard/suggestions` accepts only `url`/`content`, returns `{suggestions: {title, description, tags, generated}}`, and never publishes. Invalid source is 422; per-user throttling is 429. PUT `/api/native/moodboard/captures/:request_id` accepts top-level editable resource fields and returns `{saved: true, resource_id}`. Actor-scoped exact retries are replay-safe while the resource exists; altered reuse is 409, invalid/duplicate URL fields are 422. No owner selector or model-authored URL is accepted. Route dispatch logging is disabled to avoid recording source bodies. Domain/provider boundaries are in [Moodboard](../../atlas/moodboard/AGENTS.md).

## Native Orbit

The list also accepts optional `query` (literal, case-insensitive title/summary
search, at most 200 UTF-8 bytes without controls) and `domain` (a catalogue ID or
`unclassified`). Apply both before counts/pagination and after authorization;
unknown parameters return 422. Additive `assistant.searchable: true` and
`assistant.domains: [{id, name}]` advertise support; older servers omit them.
Thread projections include nullable `domain`. Search terms are not persisted.

`GET /api/native/orbit/models` returns `{models: [{id, name, provider}], error: null|provider_auth|provider_unavailable}` for the caller's account plus the configured workspace model, without credentials or upstream instructions. `PATCH /api/native/orbit/threads/:id/model` accepts exactly `{model: null|"workspace"|"chatgpt:<validated-model-id>"}` and returns `{thread}` with optional nullable `model`. Only a currently readable active owner may change the preference; members get 403, unreadable/missing IDs 404, active runs 409 `model_run_active`, and invalid selections/extra fields 422. The choice freezes on each run, and explicit selections never change providers on failure. Catalog failure is optional-feature state, not lost access to protected history.

`AtlasWeb.NativeOrbitController` serves fixed routes under `/api/native/orbit/threads`, declared before the dynamic native resource routes and protected by the same bearer-only, `no-store` pipeline. Older servers answer the list route with the dynamic resource's 404, which clients treat as unsupported. Domain rules live in [Orbit](../../atlas/orbit/AGENTS.md). Threads a caller cannot read return `404 {"error":"not_found"}`, indistinguishable from missing ones.

- `GET /api/native/orbit/threads?page=N&kind=private|shared&status=active|archived` returns `{assistant: {name, configured, can_create_private: true}, threads: {items, page, total_pages, total_count}}`. Status defaults to active. Optional kind and status filters apply before pagination/counts. There are 25 items per page ordered by nullable priority (`now`, `today`, `later`, then unprioritized), `updated_at DESC, id DESC` across kinds; private threads do not take precedence. Context callers omitting the optional status argument retain the legacy all-status, private-first behavior. `assistant.name` is always `Pip`, the fixed mascot/assistant identity. `configured` includes the caller's connected ChatGPT/Claude accounts or the enabled Orbit role. The additive `can_create_private` capability advertises distinct UUID-replay-safe creation independently of inference configuration; older clients ignore it. New clients default an absent flag to false, refresh typed list metadata before attempting distinct creation, and show an update-and-retry explanation if it remains false. They never silently fall back to legacy `/private`, which could reopen an existing conversation. This supports staggered native/server releases and recovery in the same native session after a server upgrade.
- `PATCH /:id {status: "archived" | "active"}` returns 200 `{thread}`. Only a currently authorized private/shared owner may archive/restore (readable members get 403; malformed, missing and inaccessible IDs get the same generic 404). Extra fields never change owner/audience/title. Same-status requests are idempotent. Real transitions increment the thread revision and publish normal list/history invalidations. Archive atomically cancels/finalizes queued/running work, clears checkpoints/tool results and fences delayed callbacks; restore starts no run or pre-archive follow-up. History and attached downloads remain readable under unchanged permissions, while sends/uploads remain blocked while archived. Use existing authoritative `owner_id` for native action eligibility, not a new capability flag. Regressions: `native_orbit_archive_controller_test.exs` and the real-worker archive test in `runs_test.exs`.
- `POST /api/native/orbit/threads/private` returns the caller's latest private conversation, creating only on first use: 201 initially and 200 afterwards.
- `POST /api/native/orbit/threads` with `{kind: "private", request_id: UUID}` creates a distinct owner-only conversation: 201 initially, 200 on same-owner UUID replay. Extra ownership/participant fields never grant access. `{title (≤200 chars, non-blank), participant_ids (≤30 UUIDs), kind?: "shared"}` retains shared creation; malformed or unknown IDs return 422 `fields.participant_ids`.
- Private creation whose original request UUID now belongs to a promoted shared conversation returns `409 {error: "thread_promoted"}`. It never creates a duplicate or returns a shared record as a successful private creation. Refresh the ordinary thread list to find that conversation; its ID and creation UUID remain unchanged.
- `GET /:id/people?query=...` returns `{people: [{id, name}]}` only (no email/profile/role metadata), max 20, excluding self. Query is optional literal case-insensitive name text, at most 100 UTF-8 bytes; malformed/nested/oversized query returns 422 `fields.query`. Owners discover only people holding every history scope; other current readers get only eligible existing participants. Unreadable/missing threads return 404, archived readable threads 409. Choices grant no authority and are revalidated at send time.
- `GET /:id/messages?page=N` returns `{thread, messages: {items, page, total_pages, total_count}, latest_seq}`. There are 50 items per page; page 1 is the newest, and items are chronological within a page. Shared and caller-recipient rows are filtered before counts/pagination; only the authorized recipient's encrypted catch-up is projected into response `body`.
- `POST /:id/messages` with `{body (≤16,000 bytes), client_id (UUID), address_agent?, attachment_ids? (≤4 UUIDs), mention_ids? (≤10 UUIDs)}` returns 201 `{message}`, or 200 with the original message when the `client_id` is retried. Body may be blank only with attachments. Claim only the caller's same-thread, unexpired pending attachments, atomically with the message/run; replay never substitutes new files or mentions. Mentions are explicit selected IDs, never parsed `@names`. Only an owner may add new eligible participants and promote private to participant-scoped shared history in that transaction; members may ping existing readers. Unknown/ineligible mentions return the same 422 `fields.mention_ids: ["invalid"]`, rolling back everything. Each new participant gets a shared join notice and a recipient-only catch-up of labeled factual excerpts, not an AI-generated summary; existing-member pings add neither. A missing `address_agent` defaults to true; threads still private after mentions always address the assistant.
- `POST /:id/attachments` stages one file with `{client_id: UUID, filename, content_type, data: base64}` (5 MiB decoded). The replay UUID belongs to the uploader/thread and must retain the same payload. `GET /:id/attachments/:attachment_id` returns `{attachment: metadata + data}` after current authorization; `DELETE` discards only the caller's pending attachment. Metadata is `{id, filename, content_type, byte_size}`, never a storage key or URL. Staging expires after 24 hours. Downloads recheck access after storage reads; attached files inherit history access, including archived readable threads.
- `POST /:id/participants {user_id}` (owner only) returns 201 `{participant: {id, name}}`. It returns 422 `fields.user_id: ["missing_access"]` when the person lacks the scopes the history requires. `DELETE /:id/participants/:user_id` returns `{removed: true}`. `POST /:id/runs/:run_id/cancel` (initiator or owner) returns 202 `{run: {id, status}}`.
- Thread fields: `id`, `title` (stored conversation title; private titles derive from the first nonempty prompt, bounded to 200 codepoints), `kind`, `status` (`active`/`archived`), `summary`, `origin` (`manual`/`signal`), nullable `priority` (`now`/`today`/`later`), `owner_id`, `participants` (`[{id, name}]`), `agent_status` (`idle`, `queued`, `running`, `compacting`, `unconfigured`), `latest_seq`, `updated_at`.
- Message fields: `id`, `kind` (`human`, `agent`, `tool`, `system`), `body`, `author_id` (humans only), `author_name`, `inserted_at`, `tool_name`, `tool_status` (`running`, `succeeded`, `failed`, `cancelled`), `tool_input`/`tool_output` (redacted bounded strings, `""` when absent), optional `parent_message_id` (research lookup's same-thread/run task card), `attachments` (metadata array), `seq` (stable creation order). Older payloads may omit the additive hierarchy/attachment fields. A tool message keeps its ID and `seq` while its status changes; the change moves the thread revision. Both private and shared threads support bounded read-only research helpers; children never append final replies or completion notifications.
- Additive message fields `notice_kind: null | "handoff" | "joined" | "private_handoff"` and `mentioned_user_ids: [UUID]` distinguish legacy shared handoffs, public-to-participants join notices, recipient-only catch-up and selected mentions. Older clients ignore them; older payloads default to null/empty. Catch-ups never use kind `agent` or claim generated/model-authored summaries. Recipient IDs and encrypted storage fields are not serialized. POST still returns only its human message; refetch page 1 / the thread list on the normal revision notification for notices and updated metadata.
- Additive `suggestions: [String]` holds zero to three contextual follow-ups on an agent reply, each at most 120 Unicode codepoints/480 bytes. Non-agent/legacy messages have an empty array; older servers may omit it. Invalid optional metadata must not break protected history. These are server-generated editable draft text, not executable actions; POST never accepts client-authored suggestion metadata. They share their message's access and retention.
- A succeeded tool message may add `component: {type: "result_table" | "account_card", version: 1, data: {title, columns, rows}, actions: [{id: "show_evidence", label}], fallback}`. The server projects it only from already-redacted durable tool output, under the same thread authorization. Limits are 120-character title, 1–3 columns, 1–5 rows, 160-character labels/cells, 40-character action label and 4,000-character fallback. No code, URLs or arbitrary styles/actions are sent. Absent/unknown components retain the original `tool_output`; they must not break history. Source reveal is local presentation of existing evidence, not a new server operation or authorization grant.
- Errors use the native envelope: 401 for an invalid token, 403 for a forbidden membership action, 404, 409 for an archived thread, 422 `invalid_params`/`validation_failed`, and 429 `rate_limited` (30 messages per minute per person).

The presence socket (`/presence/websocket`, bearer subprotocol) also routes:

- `orbit:thread:<uuid>` (`AtlasWeb.OrbitThreadChannel`). A join replies with, and the server pushes `snapshot` with, `{revision, people: [{id, name, typing}], agent_status}`. `revision` equals `latest_seq`; clients refetch page 1 when it moves. Apply `agent_status` even when revision is unchanged, since compaction progress does not create a message until pruning actually changes context. `people` lists current viewers, including the caller. The client pushes `typing {typing: bool}`; typing lapses after eight seconds. Leases last 20 seconds and are renewed every ten. Joins, pushes, typing and renewals re-check the OAuth grant and read access; losing either stops the channel. Joins without access reply `{reason: "unavailable"}`.
- `orbit:me` (`AtlasWeb.OrbitInboxChannel`) replies with, and pushes, `{revision, people: []}`, where `revision` is a non-negative fingerprint of the caller's authorized list. It hears ID-free invalidations, recomputes before pushing, coalesces bursts, and renews every ten seconds to cover missed notifications.

Coverage lives in `test/atlas_web/controllers/native_orbit_controller_test.exs` and `test/atlas_web/orbit_thread_channel_test.exs`.

## Personal execution environments

All endpoints are bearer-only and `no-store`; browser sessions are not accepted.
`GET /api/me/environments` returns `{owner_id: UUID, providers: [{id, name}], environments: [{id,
name, enabled, online, terminal, display, provider, provider_state, projects: [{id, name}]}]}` for the caller.
There is no server environment row: null/absent selection means server execution.
The Orbit list's additive `assistant.environments: true` advertises support.
Hosted selection accepts exactly `{provider: configured_id}` at the existing
private-thread environment PATCH route. It starts/resumes asynchronously;
deselection/archive queues a pause. Native-ID selection cannot select hosted rows.
Hosted registration uses an inaccessible synthetic OAuth binding, so native
claim/poll/result routes cannot impersonate it. The owner catalog/selection and
terminal activity retain their ordinary authorization. See
[`docs/environment-providers.md`](../../../docs/environment-providers.md).

All following `/api/me/environments/:id` operations additionally require the
existing native OAuth callback-shape gate (`native_client_required`, 403).
Owner/client binding is immutable; no body field can override either.

- `PUT` accepts exactly `{name: string, enabled: boolean, terminal: boolean,
  display: boolean, projects: [{id: UUID, name: string}]}`. At most 32 registrations
  per owner and 100 distinct projects per registration; names are nonblank, at
  most 100 Unicode characters / 400 UTF-8 bytes, without path separators or NUL.
  Missing/unknown keys, nested values and wrong booleans are rejected. Success
  is **200 `{environment: {id, name, enabled, online, terminal, display, projects}}`**,
  using exactly the same environment projection as GET, no synthetic ack fields.
- `DELETE` disables only the matching owner/client registration and is idempotent
  for valid UUIDs, including missing/foreign records. Success is **200
  `{disabled: true}`**. Old socket renewals cannot re-enable it.
- `GET /commands` refreshes a 20-second online lease and returns exactly
  `{commands: [{id: UUID, tool: string, arguments: object,
  execution_timeout_seconds: integer, digest: string}]}`.
  Timeout is 1,800 for terminal, 60 for files. Only unclaimed, unexpired, currently authorized
  calls are returned. `arguments.project_id` is the run's frozen project UUID.
  Digest is an opaque 64-character lowercase SHA-256 value, copied back exactly;
  it binds command ID, environment ID/version, project, arguments and policy timeout.
  Terminal is delivered only while the owner's per-Mac terminal permission is enabled.
- `POST /commands/:command_id/claim` accepts exactly `{digest: string}`.
  A successful atomic claim returns 200 `{command: {id, tool, arguments,
  execution_timeout_seconds, digest, claim_token: UUID}}`.
  Extra fields, including `approved`, are rejected.
  Repeated claims return 409
  `command_claimed_or_settled`, never a second lease/token.
- `POST /commands/:command_id/progress` accepts exactly `{claim_token: UUID,
  sequence: integer >= 1, output: UTF-8 string <= 49,152 bytes}` and returns 200
  `{received: true, cancel_requested: boolean}`. Output is an encrypted bounded
  tail, not an append log. Increasing sequences update it; stale sequences do not
  overwrite, identical duplicates succeed, changed same-sequence payloads conflict.
  Neither progress nor retry extends the fixed execution deadline.
- `POST /commands/:command_id/result` accepts exactly `{claim_token: UUID,
  success: boolean, output: string}` with valid UTF-8 output at most 65,536 bytes.
  Success is **200 `{received: true}`**, including identical payload replay.
  Changed replay returns 409 `command_result_conflict`. Late new results after
  expiry/cancellation/configuration changes are rejected. Previously stored
  acknowledgements do not revive a run or make a cancelled result usable.

Terminal reserves immediately with a queued durable model ticket, without per-command prompts.
Dispatch expires ten minutes from first reservation. Claim starts a fixed
1,800-second execution deadline and separate five-minute result-delivery grace;
it can outlive a succeeded model run but never cancellation/archive/revocation.
File calls retain synchronous bounded 60-second waits and known-result recovery.

`GET /api/native/orbit/threads/:thread_id/environment-commands` is owner-readable
private history and returns `{commands: [...]}`, terminal-only. All active items
come first, then recent settled items, at most 32 total; no pagination. Entries
have exactly `id`, `message_id`, `environment_id`, `environment_name`, `project_id`,
`project_name`, `digest`, `command`, `status`, `output`, `success`, `cancel_requested`,
`progress_sequence`, `execution_timeout_seconds` (1,800). UUIDs are lowercase;
name labels are at most 120 characters. No claim tokens or local project roots.
Statuses are `queued`, `claimed`, `settled`,
`cancelled`, `expired`, `unknown`. `success` is boolean only for settled, otherwise
null. Output is a valid UTF-8 tail at most 48 KiB each and 256 KiB aggregate;
encoded JSON is additionally bounded below the native 1 MiB reader, preserving
exact command text while trimming tails/older settled entries if necessary.

The same owner on any native OAuth installation may `POST
/:thread_id/environment-commands/:command_id/cancel` with exactly `{digest}`.
It returns exactly 200 `{received: true}`. There is no command decision endpoint;
execution requires the explicit per-Mac terminal opt-in.
Queued cancellation becomes cancelled immediately. Claimed cancellation
only persists `cancel_requested`: disconnected execution is not presumed stopped.
Only the device's actual result confirms its outcome; cancellation prevents
automatic inference. Missing claimed outcomes become unknown and never redispatch.
One active or unknown terminal per thread prevents duplicate dispatch across runs.
Confirmed completion atomically records encrypted evidence/a generic addressed
notice and uses existing Orbit follow-up/Oban recovery, behind any active run.

`PATCH /api/native/orbit/threads/:id/environment` accepts exactly
`{environment_id: UUID|null, project_id: UUID|null}` and returns 200 `{thread}`.
Only a currently readable private owner, active thread and no active run may
change it. A project requires an environment and must be in its current enabled
owned registration. Thread projection adds nullable `environment_id`,
`environment_name`, `project_id`; older clients may ignore them. Selection alone
does not block promotion; once a device command is reserved, sharing is blocked
permanently by `personal_environment_history` (409).

Other fixed errors: 404 `not_found` for missing/foreign bindings; 422
`invalid_params`; 409 `environment_limit`, `environment_disabled`,
`environment_offline`, `environment_terminal_disabled`,
`environment_project_unavailable`, `environment_run_active`,
`private_environment_required`, `command_digest_mismatch`,
`command_claim_mismatch`, `command_expired`, `command_cancelled`,
`command_progress_conflict`.

The existing presence socket also accepts `environment:<UUID>` for that bound
native client/owner. Join replies with `{commands: [...]}` and changes push event
`snapshot` with the same envelope. Authoritative reconciliation runs every two
seconds, rechecking grant, client binding, enabled/version state and audience;
renewals keep the 20-second lease alive. Closing clears that connection's lease.
HTTP commands is the authoritative fallback; clients need no new server loop.
No command/result payload is logged. DB state, not delivery hints, determines
whether a claim can succeed. Display permissions configure no tools in this slice.

## Push devices

`AtlasWeb.PushDevicesController` serves `PUT` and `DELETE /api/me/push-devices/:installation_id` behind `MCPAuth` plus `AtlasWeb.Plugs.NativeOAuthClient`, which accepts only tokens whose OAuth client registered exactly `dev.tuist.atlas://oauth-callback` (otherwise 403 `native_client_required`). Responses are `no-store`. `installation_id` is a lowercase UUID.

- `PUT` body is exactly `{platform, token, environment}`: `ios` with an even-length 32–512 character hex token (stored lowercase) and `sandbox` or `production`, or `android` with a 16–4096 character printable token and `production`. Unknown keys, including owner or app identifiers, return 400 `invalid_push_device`. Success is `{registered: true, registration_id}`.
- `DELETE` has no body and returns `{deleted: true}` for any valid ID, whether or not the caller could retire it.
- 409 `installation_retired` means the ID was deleted or reassigned; the client rotates its installation UUID and retries. 409 `installation_conflict` means another user's live installation. 503 `push_unavailable` means the platform's provider is not configured. 429 `rate_limited` caps each user at 120 requests per hour.

Semantics and delivery live in [push](../../atlas/push/AGENTS.md). Coverage is `push_devices_controller_test.exs`.

## Pip Live Activity

`AtlasWeb.OrbitLiveActivityController` serves bearer-only, `no-store` routes with
the same `NativeOAuthClient` gate as push devices; browser sessions and other
OAuth clients cannot use them. This registration is independent of ordinary
notification permission/opt-in. iOS locally starts one aggregate ActivityKit
activity and uploads its per-activity update token; Atlas never remotely starts
an activity or keeps an assistant/channel running in the background.

- `GET /api/me/orbit-live-activity` returns exactly `{available: boolean,
  content: {active_count: nonnegative integer, conversations: [{id: lowercase
  thread UUID, title: string (≤80 Unicode codepoints),
  status: queued|running|compacting|using_tools, started_at: Unix
  seconds integer, completed_steps: nonnegative integer}], updated_at: Unix
  seconds integer}}`. `available` means APNs is configured. Entries contain only
  the caller's own current eligible runs with current thread membership/history
  scopes; max three, earliest real run start (queue time before start) then run
  UUID. Count includes eligible work beyond the three shown. Completed steps
  count actually finished succeeded/failed tool calls. The stored `Thread.title`
  is trimmed after collapsing whitespace and Unicode control/format characters
  to spaces; blank titles become `Conversation`. This bounded contextual title
  is an explicit exception to the previous content-free contract: Apple receives
  it on every currently authorized send, and it can appear on the Lock Screen.
  No names, raw prompts/replies, tool names/arguments/results or percentage claims
  appear. No latest-message lookup, inferred summary, new model request, logging
  or persisted title snapshot is introduced. Older servers omit `title`; native
  clients accept missing/null titles without changing old serialized snapshots.
- `PUT /api/me/orbit-live-activity/:registration_id` accepts **exactly**
  `{token: even hex string, environment: sandbox|production}`. Token length is
  32–512 characters and is normalized lowercase. Success is `{registered: true}`.
  Registration ID is an app-generated lowercase UUID, **not** Apple's opaque
  `Activity.id`. It is immutable for that user **and** native OAuth client.
- `DELETE` on the same path returns `{deleted: true}` for any valid UUID,
  independent of whether the caller can retire it. It retires only an exact
  user/client binding. Unknown IDs become tombstones; a late PUT cannot resurrect
  them. Locally end the activity on logout even when DELETE is offline.
- 400 `invalid_live_activity` means malformed body/ID; 409
  `registration_retired` requires a new local activity and new registration UUID;
  409 `registration_conflict` is a foreign user/client or duplicate token;
  401 `session_ended` means no current refresh grant; 503
  `live_activity_unavailable` means unconfigured APNs/environment or registration
  persistence failure. PUT/DELETE are capped at 120 per user per hour (429
  `rate_limited`). Registration is best effort and must not block conversation UI.
  GET remains useful with `available: false`; older servers' 404 is unsupported.

The lifetime, delivery and retention fences are documented in
[push](../../atlas/push/AGENTS.md#pip-live-activities). Regressions live in
`orbit_live_activity_controller_test.exs` and `atlas/push/orbit_live_activity_test.exs`.

## Native link endpoints

`AtlasWeb.NativeLinksController` serves the app association files and the `/open` landing from the `:native_links` pipeline (secure headers only; no Accept negotiation, session, CSRF, or user lookup). Association files return 404 until `AtlasWeb.NativeLinks.Config` lists verified identities, and set public caching. The Android statement delegates `handle_all_urls` to the fixed `dev.tuist.atlas` package. `/open` validates `screen` and the optional UUID against `AtlasWeb.NativeLinks` and returns 404 otherwise, including encoded slashes and extra segments.

Orbit uses screen `orbit`, with an optional lowercase thread UUID. `/open/orbit` and `/open/orbit/<uuid>` are claimed native links and reveal no thread content. There is no Orbit web UI or `/orbit/<uuid>` record route in this checkout: browser escape goes to the authenticated dashboard `/`, and ordinary dashboard URLs are not mapped to Orbit. Completion push delivery separately reauthorizes the exact source reply before deriving preview content; the public link landing never does so.

Coverage lives in `test/atlas_web/native_links_test.exs` (allowlist, claimed paths, configuration parsing), `test/atlas_web/controllers/native_links_controller_test.exs` (association files, landing, host-header independence, demo denial), and `test/atlas_web/components/account_menu_test.exs` (header action across LiveView navigation and live patches within one LiveView). Tests stub `AtlasWeb.NativeLinks.Config` with Mimic rather than changing the application environment.

## Optional native themes

`GET /api/native/themes` is the sole public native route. Its JSON contains `schema_version: 1`, a nonempty `revision` (128 UTF-8 bytes maximum), `default_theme_id` referencing a catalog entry, and 1–16 unique `themes`. Themes contain `id` (lowercase letters/digits and hyphen-separated segments, at most 64 bytes; `server-default` is reserved locally), `name` (80 bytes), `description` (160 bytes), `typography` (`standard`, `strong`, `rounded`), `button_radius` (0–24), `card_radius` (0–32), and complete `light` and `dark` palettes. Radii are logical native units, not CSS pixels.

Each palette contains `background`, `surface`, `text`, `secondary_text`, `border`, `accent`, `on_accent`, and `tint`, all opaque `#RRGGBB` colors. Text, secondary text and tint need WCAG contrast ≥4.5:1 on both background and surface; on-accent needs ≥4.5:1 on accent. Tint also needs ≥4.5:1 against native row baselines (`#FFFFFF` in light mode, `#1C1C1E` in dark mode), because native controls retain system surfaces rather than company card colors. Rust independently validates/normalizes the same allowlist before native decoding. Unknown additive fields are ignored; unknown schema versions, malformed/duplicate IDs, missing tokens and unreadable palettes are rejected. No arbitrary styles, resources or script execution.

The fixed route avoids inventing an unregistered well-known suffix or mixing appearance into OAuth discovery. Fetches never attach bearer tokens, follow redirects, or interpret a theme error (including an old server's 401/404/501) as rejected OAuth credentials. Clients retain a validated per-origin catalog or their bundled Atlas theme. Local Profile selections and System/Light/Dark appearance are independent of server revisions and never sent to Atlas. Missing selections resolve to the current default while preserving the original preference.

Semantic roles and color modes follow [Theme UI's token approach](https://theme-ui.com/theming), not its React implementation. Pulse borrows teal `#088177` and small-corner geometry from the [N26 reference](https://www.shadcn.io/design/n26), not its proprietary fonts or marketing layout. Berlin pairs concrete/cobalt with acid-yellow dark accents; Habibi uses warm cream, plum and amber. Amrit pairs Indian-inspired saffron and indigo; Brigadeiro (stable ID `pelotas`) uses Brazilian greens, Atlantic teal and citrus yellow; Braník (`branik`) pairs Czech beer-inspired hop green, parchment and malt gold. iOS retains native forms, navigation, system text styles and row surfaces per the HIG; themes customize tint, content canvas and app-owned previews/actions. Increased contrast uses system styling. Geometry/typography tokens cannot resize touch targets, fonts, or native chrome. Endpoint coverage is in `native_themes_controller_test.exs`; catalog validation is in `atlas/native_themes_test.exs`.
