# Atlas personal data

Atlas's personal LLM connections are separate from Tuist Server customer data and from Atlas's operator-configured inference providers.

## Engineering error alert rules

`alert_rules` belongs to `projects` through `project_id` and stores operator-authored names, trigger/tier, enabled state, event-count threshold, nullable `threshold_window_minutes` (1–60 for `event_spike`), exact environment, minimum severity, cooldown, and Slack or webhook destination settings. Receiver URLs can contain authentication credentials; signing secrets are also sensitive stored configuration. Rules remain until explicitly deleted or their project is deleted. Project deletion cascades rules and their notification records; existing backups retain their normal policy.

`alert_notifications` references `alert_rules` and stores the error-issue subject UUID, firing time, sent/failed/skipped status, failure diagnostic and metadata. Spike metadata adds environment, distinct event count, window minutes and evaluation time alongside the existing lifetime issue count. There is no automatic notification expiry. `oban_jobs` stores rule/issue IDs, reason and environment for queued deliveries; existing Oban pruning applies. Historical previews read retained `errors_events` without copying events or sending notifications, and add no event collection or retention policy.

Webhook destinations receive issue ID/title/culprit/severity/status, lifetime count, first/last seen times and dashboard URL; project/rule IDs, rule name/tier/trigger/reason; environment, window counts, evaluation/send timestamps, random delivery UUID and stable rule/issue/environment grouping key. Slack receives the corresponding formatted issue and count information. These configured external services retain delivery data under their own policies. Atlas sends only `alert.fired`, not recovery events.

`alert_rule.created`, `.updated` and `.deleted` audits retain actor/interface, rule/project IDs, rule label, dashboard path and non-secret configuration changes. Notification rows retain delivery outcomes. The `save_error_alert_rule` tool audit omits all submitted arguments, including rejected inputs, to avoid retaining receiver credentials; list results and edit forms never expose saved webhook URLs or signing secrets. Audit history can outlive deleted rules.

For a verified organizational export, select all `alert_rules` by project ID and join all `alert_notifications` through rule ID. Include related queued jobs and audits by rule target or actor. Export non-secret destination metadata, never live receiver URLs or signing secrets through dashboard/MCP/email. Fetch retained source events separately from ClickHouse by project/issue ID. The management list and point-in-time preview are not complete legal exports. No object-storage paths are added.

## Tuist feature flag operation audits

Atlas stores no local feature flag rules or evaluation snapshots. Tuist Server owns the persisted gates and authoritative, atomic change audit. Atlas sends the authenticated operator's Atlas user UUID and email, the execution interface (`mcp`, `worker` or `api`), change UUID, reason, expected revision, operation/scope and any Tuist account/project ID or rollout percentage to the internal Tuist feature flag API. These are operator actions, not end-user analytics.

`audit_activities` stores `tuist_feature_flag.listed`, `.inspected`, `.evaluated` and `.updated` request outcomes: actor identity, interface, flag-name target (when applicable), status, and for updates the supplied operation/scope, account/project IDs or percentage, expected revision, reason, change UUID and resulting revision when successful. Resource evaluations retain the requested Tuist account or project ID and outcome, but not the returned flag decisions or an evaluation snapshot. Shared-identity Slack execution is denied locally; its rejected request-outcome audits may retain `interface=slack`, but no flag request is forwarded to Tuist. The ordinary `mcp.tool_called` audit also retains tool arguments and outcome under existing tool-audit rules. No workload tokens, raw transport errors or remote response bodies are stored in these domain events. An Atlas error outcome does not prove the remote rules were unchanged; reconcile with Tuist's audit using the change UUID.

These rows follow Atlas's existing audit retention and backup policies; clearing a flag or deleting an account does not remove operator audit history. For a verified export, select `audit_activities` by `actor_id` (or actor email for historical identities), by `tuist_feature_flag` target/name, or by the relevant Tuist account/project IDs and change UUIDs in metadata. Include matching `mcp.tool_called` entries for these tool names; organizational exports must match IDs inside their argument metadata too. Retrieve authoritative rules and change audits separately from Tuist Server. There are no new Atlas tables, S3 paths or local credential copies.

## Moodboard resources

`moodboard_resources` stores shared references, articles, media links and original text: title, optional exact-unique resource URL, contributor's plain-text description/note (up to 2,000 characters), original text/excerpt (20,000), optional manual preview image URL, lowercase tags, creator (`created_by_id` referencing `users`), and creation/update timestamps. Server-owned discovery fields store the detected kind, source title/description, extracted plain text (20,000 characters), external image/video URLs, preview status, fetch timestamp, and a random revision used to fence stale jobs. Fetched source content remains separate from contributor notes and original text.

`moodboard_comments` stores plain-text discussion bodies (4,000 characters), resource foreign key, author (`author_id` referencing `users`), and creation/update timestamps. All authenticated teammates can browse and comment. Only the contributor can edit/delete a resource or refresh its preview; only a comment's author can remove that comment. Resource deletion cascades its discussion and removes search projections. User deletion clears resource/comment attribution while preserving shared content. These rows have no automatic expiry; backups follow the deployment's existing retention.

Saving a public HTTPS link queues passive, credential-free metadata fetching from its host and validated redirects. Public X/Twitter posts use X's own syndication/embed endpoint, not a third-party proxy or authenticated API. These hosts receive the saved URL/query, Atlas server IP and fixed user agent, not the user's Atlas identity, cookies or auth. Do not put private credentials in shared links. Atlas stores bounded plain extracted content, not fetched HTML, downloaded image/video files or screenshots. Browsers request external images directly without a referrer; videos/posters use the browser's document referrer policy and videos request no preload and do not autoplay. External media hosts can see the viewer's IP and applicable request metadata. No analytics or visit-history tracking is added.

`search_records` contains rebuildable `moodboard_resource` and `moodboard_comment` projections: source IDs, resource title, notes/original/source text or comment body, resource path, and creator/author/resource identifiers in metadata. The existing asynchronous embedding pipeline may send bounded projected text to the configured embedding provider; derived vectors and source identifiers go to the configured vector service. Indexing is best-effort, not necessarily immediately visible. Resource/comment removal queues vector deletion; pending upserts reload committed search rows and cannot recreate deleted content. `oban_jobs` discovery arguments retain resource ID and preview revision; vector jobs retain operation and search-record ID, not source text or URLs. Existing job pruning/backup policies apply.

Domain `moodboard_resource.created`, `.updated`, `.deleted`, `.preview_requested` and `moodboard_comment.created`/`.deleted` audits retain actor identity, interface, target ID, resource title when applicable, and resource/dashboard path, not content snapshots. Ordinary `mcp.tool_called` events can retain submitted URLs, tags, notes, original text and comment bodies under the existing tool-audit policy. Audit history can outlive deleted resources.

For a verified export, select **all** `moodboard_resources` by `created_by_id` and `moodboard_comments` by `author_id` for a person, including their comments on other people's resources. For an organizational collection export, include both whole tables. Include matching `search_records` by source type/source ID (and retained creator/author metadata for cleared identities), derived vector identifiers, relevant `oban_jobs`, and `audit_activities` by actor and resource/comment target plus MCP tool-call events. The bounded dashboard/MCP list is not a complete legal export; cleared foreign keys alone cannot establish historical authorship. There are no new object-storage paths.

## Personal profile context

`users.description` stores optional self-authored information about the person's role, personality and communication preferences, up to 4,000 Unicode codepoints / 16,000 UTF-8 bytes. Only the authenticated person can update it through native Profile or the caller-only `update_my_profile` MCP tool; `get_my_profile` reads the same person's profile. Profile-update tool arguments are omitted from audit metadata.

The saved description remains until cleared or the user is deleted, and belongs in exports of that user's `users` row. Pip reloads it for the acting user's private thread only, as untrusted background, never as permission or system instructions. Shared Orbit threads never load this field. Private inference sends it to the acting person's connected ChatGPT account, then Claude, or the workspace's configured Orbit provider on fallback; encrypted active-run checkpoints can retain a prior version until the run finishes. Native editor drafts remain in memory. Database backups follow the deployment's existing retention.

## Live availability and viewing presence

`presence_connections` stores a user foreign key, random connection ID, current allowlisted resource (and optional record UUID), and database-clock expiry. These are short-lived availability hints, not edit locks or a navigation log. The directory reuses `users` names and emails and exposes online/offline only. A same-page viewer receives only matching users' `here` flags, never another person's location, raw path, record name, draft, or device details. Rust's native connection handles, latest snapshots and reconnect state remain in memory; no mobile presence database is created.

Active server connections renew a 20-second lease. Hidden browser tabs and background native apps leave; crashed connections expire and are removed by a five-second cleanup sweep. Old locations are overwritten rather than appended. Heartbeats and location changes are not audit events. User deletion cascades leases. Availability changes use payload-free PostgreSQL notifications, not retained events. Outages can delay physical cleanup, but reads ignore expired rows. Database backups may retain historical copies until the deployment's existing backup retention ends.

For a verified export, select all `presence_connections` by `user_id`, including any expired but not yet swept rows, alongside the user's name/email. There is no browsing-history export because Atlas does not maintain one. Neither the People directory nor its matching-page flags are a complete personal-data export.

## Storage and ownership

`user_llm_connections` contains one row per Atlas user and provider (`claude` or `chatgpt`). `user_id` references `users.id`; deleting the user cascades to these rows.

Stored fields:

- Provider identifier, connection creation/update timestamps, and ChatGPT access-token expiry.
- Access token and, for ChatGPT, refresh token, encrypted with Atlas's existing Cloak vault.
- During ChatGPT sign-in: an encrypted JSON device authorization record containing the opaque login ID, provider device ID, user code, OAuth client ID, verification URL, and polling interval. The row also stores the pending login expiry and next allowed poll time.

No passwords, ID tokens, model prompts, completions, agent-session content, or local files are collected by this feature.

## Retention and deletion

Saved credentials remain until replacement, disconnect, rejected refresh, or user deletion. Disconnect deletes the entire provider row, including pending sign-in data. Cancellation clears pending sign-in data while preserving existing saved credentials. Successful sign-in clears pending data. Device authorizations expire after 15 minutes and cannot be used thereafter; expired pending fields are cleared on the next poll or replaced on the next sign-in. Abandoned expired pending ciphertext can remain until one of those actions, disconnect, or user deletion. There is no automatic cleanup worker for it.

Provider disconnect deletes Atlas's credentials but does not revoke upstream authorization; users must revoke access separately at the provider. Transient refresh failures retain credentials for a later retry, without returning an expired token.

Connection lifecycle audit events in `audit_activities` store actor identity, interface, provider, and dashboard path. They never contain tokens or raw provider responses. Audit events follow Atlas's existing audit retention policy and are not deleted by disconnect.

MCP can accept a Claude setup token for create/update, but Atlas omits the complete argument payload from the tool-call audit on both success and failure. ChatGPT start/poll/cancel tool arguments are omitted too, so login handles are not retained in tool audits. Provider tokens are never included in tool responses. A user's MCP client or model may retain submitted Claude tokens independently of Atlas; prefer the browser credential form when that is a concern.

## Export

For a verified data request, select connection rows by the requesting user's `user_id`, and audit records by `actor_id` or the `user_llm_connection` target and user ID. Ordinary API/MCP exports include only explicit connection metadata (`provider`, `credential_configured`, `login_available`, `expires_at`, `updated_at`). Never export live bearer credentials, refresh tokens, or pending device secrets through dashboard, API, MCP, logs, or email. Offer disconnect/reconnection rather than copying authentication secrets. Database backups include encrypted credential columns and follow the deployment's existing backup retention.

## Employee time off

`users.time_off_location_id` references the employee's public-holiday calendar, currently defaulted to Berlin. It is a calendar assignment, not a verified physical address. `time_off_locations` stores shared calendar names, country/subdivision codes, imported years, and timestamps. `time_off_holidays` stores calendar references, holiday names/dates, manual/provider provenance, and timestamps.

`time_off_bookings` belongs to a user and snapshots their calendar. It stores inclusive first/last dates, pending/approved/rejected/cancelled status, cancellation time, reviewer identity/time, and creation/update timestamps. There are no medical reasons, free-text leave reasons, allowances, or external employee identifiers. Native apps use the same authenticated owner-scoped records; there is no additional mobile database or calendar synchronization. Native request drafts and loaded history are held in memory for the signed-in session, not written to device preferences.

Requests remain in history after cancellation or rejection and have no automatic expiry. Deleting a user cascades their bookings; shared calendars/public holidays remain. Reviewers deleted later are cleared from the reference. Domain audit events retain actor, interface, dashboard path, target, and relevant transition metadata, including previous dates and reviewer metadata on edits. Audits follow Atlas's existing retention policy and can outlive the booking.

For an export, select the user's calendar assignment and **all** `time_off_bookings` by `user_id`, including rejected/cancelled entries. Join their current and snapshotted `time_off_locations`, export the corresponding `time_off_holidays`, and include relevant `audit_activities` by booking/assignment targets. Neither the bounded calendar, the paginated dashboard, nor `/api/me/time-off` is a complete legal export. See `lib/atlas/time_off/AGENTS.md` for date/count, access, and synchronization semantics.

## Manual finance bookkeeping

Manual invoices share `finance_invoices` with imported vendor invoices. They store vendor name, invoice number, invoice/due dates, total amount and original currency, review status, and timestamps. Atlas owns the provenance in `metadata`: `source = "manual"` and `created_by_id` (the Atlas user's ID). HTTP/MCP callers cannot set or replace these metadata keys or document/bank transaction references through manual bookkeeping actions. Manual creation needs no document upload and makes no payment or bank write. Imported entries, including entries whose document was removed, do not become manual or writable.

Entries remain until explicit deletion; there is no automatic manual-invoice expiry. The creator ID is provenance in JSON, not a foreign key, and remains after user deletion. Mutation events in `audit_activities` retain actor identity, interface, target, finance dashboard path, amount and currency under the existing audit retention policy, even after the invoice is deleted. Existing backups follow the deployment's backup retention. Native clients store no additional server-side copy.

For a verified data request, select **all** matching `finance_invoices`, including metadata and timestamps. Creator-owned entries can be selected with `metadata->>'created_by_id' = <user ID>` and `metadata->>'source' = 'manual'`; vendor invoices relevant to an organizational request may require additional vendor/business matching. Include associated audit events by `finance_invoice` target or `actor_id`. The native paginated list and monthly aggregate are not complete exports. These records reuse existing database storage; no new S3 paths or uploaded files are introduced.

## Orbit threads

Orbit threads store people's messages to each other and to Pip, Atlas's fixed-name assistant and mascot. Model turns prefer the acting person's connected ChatGPT account, then Claude, then the workspace's explicitly configured Orbit inference profile. Each turn reloads only that person's credentials; other participants' accounts are never used. Conversation context and authorized tool results can be sent to those providers, including fallback providers after an unsuccessful attempt. Disconnect stops future credential lookup but cannot retract content already sent upstream. Provider retention follows that provider's terms; ChatGPT requests explicitly disable response storage.

- `orbit_threads`: kind (`private`/`shared`), title, status, optional signal summary and source type/ID, owner (`owner_id`, cleared on user deletion), an optional owner-scoped private-creation replay UUID (`request_id`), the scopes its history requires (`required_scopes`), the latest sequence number, and timestamps. Each person may have multiple independent owner-only private conversations. Their default title is "New conversation" until the first nonempty human prompt supplies a whitespace-normalized title bounded to 200 Unicode codepoints. The multi-conversation migration derives titles for legacy default-titled private threads from their existing first prompt without rewriting messages or IDs. Creation UUIDs remain with the thread for its lifetime; native uncertain-creation IDs and per-thread drafts are memory-only and cleared at sign-out.
- `orbit_participants`: thread and user references, role (`owner`/`member`), and join time. User deletion cascades.
- `orbit_messages`: message kind (`human`, `agent`, `tool`, `system`), Markdown body, author reference and an author-name snapshot, the client's idempotency UUID, whether the assistant was addressed, run reference, ordering numbers, and timestamps. Tool messages store the tool name, status, and redacted, bounded renderings of the input (≤2,000 characters) and output (≤4,000 characters). Values under credential-like or signed-link keys are replaced before storage. While a run is active, a completed tool card also holds the bounded result given to the model (`tool_result`, encrypted with Atlas's Cloak vault) and a hash of the call (`tool_call_key`), so a run resumed after a deploy does not execute the call again. The encrypted result is cleared when the run finishes. User deletion clears the author reference but keeps the message, its author-name snapshot, and the thread history of other participants.
- `orbit_runs`: assistant run status, nullable transient `activity` (`compacting` while Condukt prunes context; cleared on completion/retry), acting and initiating users, inference profile, trigger position, attempt counter, error category, cancellation and timing fields, the attempt's Condukt session ID, and `checkpoint`. The checkpoint is the exact model protocol messages at the start of the run's latest turn, including the request transcript and tool results, encrypted with Atlas's Cloak vault. It exists only while a run is queued or running and is cleared when the run finishes.
- `orbit_viewers`: short-lived viewing leases with a random connection ID, thread and user references, typing expiry, and database-clock expiry. They are not audited, are renewed every ten seconds, and are swept after expiry. User and thread deletion cascade. Drafts never reach the server.

Thread run audit rows in `agent_sessions` store only an `orbit_run:<id>` label, a redacted result marker and fixed error categories. `agent_session_events` keep tool names, statuses and timings. Tool calls produce `mcp.tool_called` audit events with the thread and run IDs but without arguments. Membership changes, creation and signals produce `thread.*` audit events. Inference usage rows follow the existing relay retention.

Owner-only archive/restore changes the existing `orbit_threads.status` (`active`/`archived`) and records `thread.status_changed` with the new status, not message/file content. Archive is not deletion or a retention cutoff: messages, memberships and attached files remain protected and exportable as before. Active runs are cancelled/finalized, clearing encrypted checkpoints and tool-result caches under their existing terminal-run policy; delayed workers cannot revive them after restore. Restore does not start inference. Native lists default to active and offer an archived filter, but legal exports must include both statuses. No new customer-data columns or storage categories are introduced.

Native rich result cards are data-only projections of the existing redacted `orbit_messages.tool_output`, with no additional database rows, files, retention period or customer data collection. Their server-provided fallback is the same bounded evidence; export the source messages, not client renderer packages or caches.

Explicit native mentions store selected user UUIDs in `orbit_messages.mentioned_user_ids` (at most ten; empty for old messages). They are persistent attribution, not membership: removed/deleted users' UUIDs remain in the source message, and delivery always rechecks current access. Include these UUIDs in message exports and assess third-party redaction as for the other shared history. An owner mentioning a new eligible person promotes a private conversation to participant-scoped shared history, never public or company-wide visibility. All invitees must hold every ratcheted history scope. Audience expansion appends a system message with `notice_kind = "handoff"`: clearly labeled, bounded conversation-so-far excerpts from the first human request and latest Pip reply, not a generated summary or a new provider call. Excerpts duplicate already-retained source text and follow the same history retention/export controls. Promotion and invitations have `thread.promoted` / `thread.participant_added` audits. Name-only mention search stores no query or new directory records. A promoted thread retains its creation UUID: a private-creation replay conflicts safely rather than creating a second conversation.

For a verified personal-data request, also locate messages with the requester's UUID in `mentioned_user_ids` (`user_id = ANY(mentioned_user_ids)`), including after membership removal. Review third-party content before disclosure; current native read permissions are not a complete operator-level legal export.

Research helpers use the same run and durable tool-message history in both private and shared threads. Optional `orbit_messages.parent_message_id` links nested lookups to their task card in the same thread/run. There is no separate child conversation store, final reply or notification. Export parent and child messages with the thread; encrypted tool results retain the existing active-run lifetime.

`orbit_attachments` records private uploaded files: thread/message/uploader references, sanitized filename, content type, byte size, private object key, staging/expiry/deletion state, upload replay UUID, immutable payload digest and timestamps. Objects live at `orbit/threads/<thread-id>/attachments/<attachment-id>` in the existing private object store, not Documents. Pending uploads are uploader-only and expire after 24 hours; claimed files inherit the thread's current access and remain with its history. Discarded, expired and orphaned objects are deleted by the 15-minute cleanup worker; failed object deletions retain their ledger for retry. Removing a user does not remove files already shared into retained history. Deleting a message/thread retains the deletion ledger until its object is reclaimed.

An export must include attachment rows and actual object bytes for exported messages, plus the requester's unclaimed uploads and outstanding deletion-ledger rows where identifiable. Download bytes using the stored private object key through the operator's authorized storage tooling; do not generate public links. Native attachment APIs are access-filtered and are not a complete legal export. Pip sends recognized images and bounded text/PDF excerpts to the acting person's connected provider or the configured Orbit fallback; unsupported formats remain downloadable but are explicitly not read by the agent. Provider inputs exist in memory and encrypted active-run checkpoints, not audit or delivery-job payloads. Native downloaded previews use protected temporary files and are removed on dismissal/navigation; native drafts and retry bytes remain in memory.

The terminology migration renames the original draft tables and foreign keys in place, preserving IDs, history, encrypted execution caches and membership. Historical message text and audit events are not rewritten.

There is no automatic expiry for threads or messages. Administrators cannot read private threads through Atlas interfaces, but database operators and backups can. For a verified data request, select all the user's private conversations and every thread where they participate, and export all `orbit_messages` for those threads, including each thread's creation replay UUID where present. Messages authored by others are part of shared history and may require redaction before disclosure. Also include `orbit_runs` where the user is the initiating or acting user (excluding encrypted checkpoints, which are transient caches), any current `orbit_viewers` rows, and related audit events by `actor_id` or thread target. The paginated native API returns only threads the user can currently read and is not a complete legal export; the optional `kind=private` list filter intentionally omits shared threads but does not change direct-read authorization.

## Native push notification registrations

`orbit_mentioned` jobs additionally carry the exact human `orbit_messages` ID, never source text. The generic alert is "Atlas" / "You were mentioned in an Orbit conversation" and includes only the existing native thread destination. Fan-out commits with the human message/promotion/invitation transaction, once per recipient's opted-in registrations; replays enqueue nothing. Send-time checks require the same active shared thread, current membership and all history scopes, and the recipient's explicit UUID in that exact human source message. Removed/revoked/missing sources cancel. Mentions have the same one-hour delivery lifetime and seven-day Oban pruning as completions; they add no per-kind preferences or new device data and do not disclose a conversation title, author name or message content to Apple/Google.

`push_installations` stores one row per native app installation that enabled notifications on this server: the client-generated installation UUID, the owning `user_id`, the OAuth client ID the app registered, platform (`ios`/`android`), APNs environment, the provider device token encrypted with Atlas's Cloak vault, a SHA-256 hash of that token for uniqueness, and token-update, last-registration and creation/update timestamps. There is no device name, model, OS version, location, phone number, or advertising identifier. Notification content is not copied into delivery jobs: `oban_jobs` holds only registration/user/notification IDs, a fixed kind, an allowlisted destination (screen and optional record UUID), an expiry and, for `orbit_completed`, the exact final `orbit_messages` ID. Activity/self-test alerts read "Atlas" / "You have a new notification". Orbit completion alerts use the cleaned conversation title (80 Unicode codepoints), a Pip subtitle and plain-text final-reply preview (160 codepoints), derived at delivery from the existing thread/message after rechecking access and its succeeded run. APNs groups them by thread and offers a fixed Open conversation action. This adds no content storage or retention beyond the source Orbit records. Completed and cancelled jobs follow Oban's seven-day pruning; Orbit deliveries expire after one hour.

Sign-out, opt-out, account switches on the same app, an ended app session (the app's OAuth refresh grant was revoked or expired), provider invalidation, eviction beyond ten devices, and 60 days without a refresh retire a row: its token, token hash and owner are cleared, keeping only the installation UUID, OAuth client ID, platform, environment, reason and timestamps as a tombstone that blocks reuse of that installation UUID. Tombstones are deleted after 180 days. Deleting a user cascades their live rows; tombstones no longer reference a user.

Every delivery shares data with the platform provider, Apple Push Notification service for iOS or Firebase Cloud Messaging (Google) for Android. They receive the device token, the title/body, the server registration UUID, the notification UUID (as the APNs collapse ID, or in the FCM data), and the destination link. That link carries the Atlas server origin, the native screen name and, for record destinations, the record UUID (task, account, invoice or Orbit thread). Activity/self-test alerts do not disclose names, email addresses, record titles or contents. Opted-in Orbit completion is an explicit exception: Apple/Google receive the bounded thread title and final-reply preview, which may contain business or personal information from that authorized reply. OS notification-preview settings govern lock-screen display. Raw tool results, checkpoints and diagnostics are never used as alert content. Apple and Google retain their own delivery records under their terms, outside Atlas's deletion and export controls.

For a verified data request, select live `push_installations` by `user_id` and export platform, environment and timestamps. Never export device tokens: they are delivery credentials, not user content, and users can remove them by disabling notifications or signing out. Tombstones are not attributable to a user and are not part of a personal export. Database backups include encrypted token columns and follow the deployment's existing backup retention.

## Pip Live Activity registrations

`orbit_live_activities` stores an app-generated registration UUID (not Apple's
`Activity.id`), owning `user_id`, native OAuth client ID, encrypted APNs
per-activity update token and redacted SHA-256 hash, sandbox/production environment,
eight-hour expiry, retirement, last-delivery and reconciliation timestamps, the
last APNs Unix timestamp and a hash of the last authorized projection. There
are no device descriptors or stored content snapshots. PUT cannot transfer a
binding between users/clients or extend its original eight-hour lifetime. A new
aggregate for the same user/client retires its predecessor. Ordinary notification
permissions and `push_installations` remain independent.

Apple receives the update token, registration UUID as collapse ID, and only a
freshly authorized aggregate: total current eligible run count, at most three
thread UUIDs with bounded stored conversation titles, generic
queued/running/compacting/using-tools statuses, real
start/queue Unix timestamps, counts of actually finished tool calls, and an update
timestamp. Titles are an explicit contextual exception to the previous
content-free contract: the existing `orbit_threads.title` is whitespace/control/
format-character cleaned, trimmed and bounded to 80 Unicode codepoints, with
`Conversation` for blank values. Apple receives these titles, which may contain
business or personal information and can appear on the Lock Screen. Raw prompts,
tool names/inputs/results, replies, author names, sound and alerts remain excluded.
No prompt/latest-message lookup, inferred summary or new model request supplies a
title. Generic phase labels are drawn on the device. Titles are recomputed under
the same authorization fences for each send, never logged or persisted as delivery
snapshots. Apple retains delivery records under its own terms. Data sent before
access removal cannot be recalled; the two-minute stale date limits freshness
claims if end delivery is lost.

Jobs hold only the registration UUID, not a token or snapshot, and have Oban's
existing seven-day retention. Every send rechecks the current refresh grant,
actor, active thread, membership and all history scopes. Last-work completion,
cancellation/archive, logout/grant expiry, access loss or lifetime expiry removes
ineligible work and ends an empty aggregate. DELETE tombstones even an unknown
UUID. Retirement forbids any further content update; the encrypted token is kept
only for best-effort empty end delivery, then token/hash/owner are cleared on end
success, provider invalidation/permanent rejection, five failed attempts or a
two-minute end retry window. A bounded sweep detects missed events. User deletion
clears the owner reference so the sweep sends an empty end and drops the token.
Tokenless tombstones retain registration/client IDs and timestamps for 180 days
to block delayed PUTs. Audit rows (`orbit_live_activity.registered`, `.retired`,
`.updated`, `.ended`, `.invalidated`) carry IDs and fixed outcomes only and follow
existing audit retention; backups contain encrypted tokens under existing backup
retention.

For a verified export, select `orbit_live_activities` by `user_id`, including
pending-end rows, and export registration/client IDs, environment, lifecycle and
delivery timestamps, excluding token, token hash and projection hash (delivery
credentials/internal caches, not content). Related audit rows can be located by
actor or `target_type = 'orbit_live_activity'` and registration UUID. Completed
tombstones have no user reference; use audit records for attributed historical
lifecycle events where required. Export run/message history from the Orbit
tables under their existing rules, not from this native status projection.
