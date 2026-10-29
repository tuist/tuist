# Atlas personal data

Atlas's personal LLM connections are separate from Tuist Server customer data and from Atlas's operator-configured inference providers.

## Personal GitHub, Slack and Google connections

`user_connections` stores one personal OAuth grant per Atlas `user_id` and provider (`github`, `slack`, `google`). It references `users.id` with cascade deletion. Fields include provider user ID, display/account name, optional Slack workspace ID, granted scopes, token expiry, needs-authorization flag, and creation/update timestamps. Access and refresh tokens use Atlas's Cloak encrypted binary type and are redacted from struct inspection. These grants are separate from Google sign-in, workspace integrations and personal AI accounts. No real grants or tokens are seeded.

Credentials remain until reconnect/replacement, disconnect or user deletion. Reconnect to another external identity never inherits the old identity's refresh token. Disconnect deletes Atlas's stored grant, not the provider's authorization; users must revoke that separately at the provider. Definitive refresh rejection marks the grant as needing authorization; transient failure retains it without returning an expired access token. Existing database backup retention applies.

`user_connection_authorizations` stores only a SHA-256 provider nonce hash, user foreign key (cascade delete), provider and expiry for atomic, cross-replica callback replay prevention. Authorizations expire after ten minutes, are deleted on validated callback before token exchange (including denied consent), and expired rows are swept when another authorization begins. Abandoned expired rows can remain until that sweep or user deletion. Browser signed-cookie pending data contains user/provider, provider nonce/PKCE verifier and, for native handoff, the native user/provider/client ID/state context. It contains no provider credentials. Native prepare tickets are signed, expire after ten minutes, and cannot authenticate a browser; the existing browser user must match. The fixed `dev.tuist.atlas://connections-callback` returns only native state, provider and connected/error status. OAuth redirects exchange grant codes with the selected provider; that provider receives the requested scopes, callback and ordinary OAuth request metadata under its own retention policy.

`connection.connected`, `.disconnected`, `.refreshed` and `.needs_authorization` audit events retain actor/interface, connection target, provider and `/settings/connections` dashboard path, never tokens or raw provider bodies. They follow existing audit retention and may outlive a disconnected grant. MCP `manage_account_connections` permits metadata listing and caller-only disconnect; it accepts no credentials. HTTP, browser and MCP metadata expose only provider/name/configured/account_name/scopes/status. Provider tokens never appear in native returns, agent prompts or tool responses.

For a verified export, select **all** `user_connections` and `user_connection_authorizations` by `user_id`, with related `audit_activities` by actor/connection target and `mcp.tool_called` records for `manage_account_connections`. Export non-secret identity, scope, lifecycle metadata and authorization expiry, never live tokens, PKCE verifiers, tickets or native handoff secrets through dashboard/API/MCP/email. Offer disconnect/reconnect instead of copying credentials. No object-storage paths or Tuist Server customer tables are added; Atlas's separate database and encrypted backups retain these records under the existing backup policy. The three-row settings/API metadata listing is not a complete legal export.

## Engineering error alert rules

`alert_rules` belongs to `projects` through `project_id` and stores operator-authored names, trigger/tier, enabled state, event-count threshold, nullable `threshold_window_minutes` (1–60 for `event_spike`), exact environment, minimum severity, cooldown, and Slack or webhook destination settings. Receiver URLs can contain authentication credentials; signing secrets are also sensitive stored configuration. Rules remain until explicitly deleted or their project is deleted. Project deletion cascades rules and their notification records; existing backups retain their normal policy.

`alert_notifications` references `alert_rules` and stores the error-issue subject UUID, firing time, sent/failed/skipped status, failure diagnostic and metadata. Spike metadata adds environment, distinct event count, window minutes and evaluation time alongside the existing lifetime issue count. There is no automatic notification expiry. `oban_jobs` stores rule IDs for independent spike evaluations and rule/issue IDs, reason and environment for queued deliveries; existing Oban pruning applies. Historical previews read retained `errors_events` without copying events or sending notifications, and add no event collection or retention policy.

Webhook destinations receive issue ID/title/culprit/severity/status, lifetime count, first/last seen times and dashboard URL; project/rule IDs, rule name/tier/trigger/reason; environment, window counts, evaluation/send timestamps, random delivery UUID and stable rule/issue/environment grouping key. Slack receives the corresponding formatted issue and count information. These configured external services retain delivery data under their own policies. Atlas sends only `alert.fired`, not recovery events.

`alert_rule.created`, `.updated` and `.deleted` audits retain actor/interface, rule/project IDs, rule label, dashboard path and non-secret configuration changes. Notification rows retain delivery outcomes. The `save_error_alert_rule` tool audit omits all submitted arguments, including rejected inputs, to avoid retaining receiver credentials; list results and edit forms never expose saved webhook URLs or signing secrets. Audit history can outlive deleted rules.

For a verified organizational export, select all `alert_rules` by project ID and join all `alert_notifications` through rule ID. Include related queued jobs and audits by rule target or actor. Export non-secret destination metadata, never live receiver URLs or signing secrets through dashboard/MCP/email. Fetch retained source events separately from ClickHouse by project/issue ID. The management list and point-in-time preview are not complete legal exports. No object-storage paths are added.

## Tuist feature flag operation audits

Atlas stores no local feature flag rules or evaluation snapshots. Tuist Server owns the persisted gates and authoritative, atomic change audit. Atlas sends the authenticated operator's Atlas user UUID and email, the execution interface (`mcp`, `worker` or `api`), change UUID, reason, expected revision, operation/scope and any Tuist account/project ID or rollout percentage to the internal Tuist feature flag API. These are operator actions, not end-user analytics.

`audit_activities` stores `tuist_feature_flag.listed`, `.inspected`, `.evaluated` and `.updated` request outcomes: actor identity, interface, flag-name target (when applicable), status, and for updates the supplied operation/scope, account/project IDs or percentage, expected revision, reason, change UUID and resulting revision when successful. Resource evaluations retain the requested Tuist account or project ID and outcome, but not the returned flag decisions or an evaluation snapshot. Shared-identity Slack execution is denied locally; its rejected request-outcome audits may retain `interface=slack`, but no flag request is forwarded to Tuist. The ordinary `mcp.tool_called` audit also retains tool arguments and outcome under existing tool-audit rules. No workload tokens, raw transport errors or remote response bodies are stored in these domain events. An Atlas error outcome does not prove the remote rules were unchanged; reconcile with Tuist's audit using the change UUID.

These rows follow Atlas's existing audit retention and backup policies; clearing a flag or deleting an account does not remove operator audit history. For a verified export, select `audit_activities` by `actor_id` (or actor email for historical identities), by `tuist_feature_flag` target/name, or by the relevant Tuist account/project IDs and change UUIDs in metadata. Include matching `mcp.tool_called` entries for these tool names; organizational exports must match IDs inside their argument metadata too. Retrieve authoritative rules and change audits separately from Tuist Server. There are no new Atlas tables, S3 paths or local credential copies.

## Moodboard resources

`moodboard_resources` stores shared references, articles, media links and original text: title, optional exact-unique resource URL, contributor's plain-text description/note (up to 2,000 characters), original text/excerpt (20,000), optional manual preview image URL, lowercase tags, creator (`created_by_id` referencing `users`), and creation/update timestamps. Server-owned discovery fields store the detected kind, source title/description, extracted plain text (20,000 characters), external image/video URLs, preview status, fetch timestamp, and a random revision used to fence stale jobs. Fetched source content remains separate from contributor notes and original text.

Native/MCP replay-safe captures additionally store a caller-generated `capture_id` UUID and SHA-256 `capture_hash` of the initially reviewed fields. These identify an actor's exact retry, not additional source content, and persist until resource deletion. Include them in resource exports. Suggested title/description/tags are only stored as ordinary reviewed fields when the person saves; suggestions alone create no resource. The suggestion endpoint fetches public link metadata under the same safe discovery policy and sends the submitted URL/text plus bounded fetched metadata/text to the server's configured global AI provider. This occurs when reviewing a share, before publication. Provider retention follows its configuration/terms. Audited `agent_sessions`/`agent_session_events` retain redacted prompts/results and operational metadata, not source or inferred text; include matching operational records in organizational exports. `moodboard_resource.suggested` audits retain actor/interface/generated status/path. MCP tool-call audits can retain the submitted source under the existing tool-audit policy even when the suggestion is never saved.

The iOS Share extension keeps up to 100 pending captures only on that device in a protected, backup-excluded App Group inbox: original URL/text, optional note, reviewed fields, capture UUID/time, a random recipient nonce and selected server origin, and whether a save is awaiting confirmation. OAuth credentials stay in the host's device-only Keychain, never the extension. Opening Atlas offers review; explicit Save uploads the reviewed capture. Confirmation/discard removes the local copy; sign-out/new sign-in purges the previous recipient's inbox. Pending local-only captures cannot be exported from the server and must be retrieved from the device before discard/sign-out. Local media files are not accepted.

`moodboard_comments` stores plain-text discussion bodies (4,000 characters), resource foreign key, author (`author_id` referencing `users`), and creation/update timestamps. All authenticated teammates can browse and comment. Only the contributor can edit/delete a resource or refresh its preview; only a comment's author can remove that comment. Resource deletion cascades its discussion and removes search projections. User deletion clears resource/comment attribution while preserving shared content. These rows have no automatic expiry; backups follow the deployment's existing retention.

Saving a public HTTPS link queues passive, credential-free metadata fetching from its host and validated redirects. Public X/Twitter posts use X's own syndication/embed endpoint, not a third-party proxy or authenticated API. These hosts receive the saved URL/query, Atlas server IP and fixed user agent, not the user's Atlas identity, cookies or auth. Do not put private credentials in shared links. Atlas stores bounded plain extracted content, not fetched HTML, downloaded image/video files or screenshots. Browsers request external images directly without a referrer; videos/posters use the browser's document referrer policy and videos request no preload and do not autoplay. External media hosts can see the viewer's IP and applicable request metadata. No analytics or visit-history tracking is added.

`search_records` contains rebuildable `moodboard_resource` and `moodboard_comment` projections: source IDs, resource title, notes/original/source text or comment body, resource path, and creator/author/resource identifiers in metadata. The existing asynchronous embedding pipeline may send bounded projected text to the configured embedding provider; derived vectors and source identifiers go to the configured vector service. Indexing is best-effort, not necessarily immediately visible. Resource/comment removal queues vector deletion; pending upserts reload committed search rows and cannot recreate deleted content. `oban_jobs` discovery arguments retain resource ID and preview revision; vector jobs retain operation and search-record ID, not source text or URLs. Existing job pruning/backup policies apply.

Domain `moodboard_resource.created`, `.updated`, `.deleted`, `.preview_requested` and `moodboard_comment.created`/`.deleted` audits retain actor identity, interface, target ID, resource title when applicable, and resource/dashboard path, not content snapshots. Ordinary `mcp.tool_called` events can retain submitted URLs, tags, notes, original text and comment bodies under the existing tool-audit policy. Audit history can outlive deleted resources.

For a verified export, select **all** `moodboard_resources` by `created_by_id` and `moodboard_comments` by `author_id` for a person, including their comments on other people's resources. For an organizational collection export, include both whole tables. Include matching `search_records` by source type/source ID (and retained creator/author metadata for cleared identities), derived vector identifiers, relevant `oban_jobs`, and `audit_activities` by actor and resource/comment target plus MCP tool-call events. The bounded dashboard/MCP list is not a complete legal export; cleared foreign keys alone cannot establish historical authorship. There are no new object-storage paths.

## Personal profile context

`users.description` stores optional self-authored information about the person's role, personality and communication preferences, up to 4,000 Unicode codepoints / 16,000 UTF-8 bytes. Only the authenticated person can update it through native Profile or the caller-only `update_my_profile` MCP tool; `get_my_profile` reads the same person's profile. Profile-update tool arguments are omitted from audit metadata.

The saved description remains until cleared or the user is deleted, and belongs in exports of that user's `users` row. Pip reloads it for the acting user's private thread only, as untrusted background, never as permission or system instructions. Shared Orbit threads never load this field. Private inference sends it to the acting person's connected ChatGPT account, then Claude, or the workspace's configured Orbit provider on fallback; encrypted active-run checkpoints can retain a prior version until the run finishes. Native editor drafts remain in memory. Database backups follow the deployment's existing retention.

## Portable signals and business routing profiles

`users.business_profile` is separate, explicitly shared routing metadata: an opt-in
boolean (default false), business role (100 characters), expertise tags (20 × 100)
and exact responsibility subject identifiers (20 × 200, such as `account:<UUID>`).
Only the caller can replace it through `/api/me/business-profile` or the matching
MCP tools; shared-identity Slack cannot use those tools. Private descriptions are
never searched for routing. Disabling prevents future automatic matching but does
not remove existing thread membership or previously recorded routing reasons.
The profile remains until replaced or user deletion. Include it in user exports.

`signal_sources` stores the owner's user UUID, pinned Automation revision, name,
disabled-by-default enabled flag, immutable reader UUID ceiling, required scopes,
fallback business-role tags and timestamps. `signals` stores source, execution and
optional Orbit thread references, provider external ID, correlation key, event
type/schema version, occurrence/observation times, status, priority, decision and
timestamps. The normalized envelope (12,000 JSON bytes maximum) is encrypted with
the Cloak vault and includes title, summary, subject/topic tags and provider data;
it must not contain credentials. Decisions retain priority/reason and up to three
routed user UUIDs with responsibility/expertise/role matches. Sources and signals
have no automatic expiry or public deletion operation. Owner deletion cascades
sources and signals; deleting runs/threads clears their signal references, not the
signal itself. Reader/routing UUID arrays are attribution, not cascading user FKs.

An optional immutable `signal_sources.event_receiver` stores the upstream MCP
event name, exact scalar data filters, correlation field, fixed title/summary and
subject/topic routing tags. These can contain organization/project references and
belong in authorized exports. `signing_secret` stores a generated 32-byte HMAC key
encrypted by Cloak, redacted from inspection and omitted from later API/MCP reads
and exports. Creation returns the `whsec_` credential once in a virtual `delivery`
field; a requesting MCP client may retain that response. The upstream event
publisher receives the key and Atlas callback URL during separate operator
enrollment. Atlas stores no upstream subscription ID, credential or renewal state.
Signed callbacks retain only normalized event data in the existing encrypted
envelope, not signature headers or the verification challenge. Pausing stops
admission; recreating a source replaces its immutable receiver/key. The same
source/owner deletion and backup retention apply; no automatic credential expiry
or provider enrollment/renewal worker is added.

Optional personal Gmail/Slack monitors store the immutable query, provider and
connection UUID/external identity/workspace binding in Cloak-encrypted, redacted
`signal_sources.poll_config`. The encrypted `poll_state` holds a UTC watermark,
fixed in-progress query window and pagination token/page. Public source metadata
includes interval seconds, next-poll timestamp and a bounded `poll_error` category;
API/MCP serializers omit both encrypted polling fields. Monitoring requires an
explicit source audience and activation. Gmail separately requires read-only email
consent; ordinary Google connections still request no Gmail scope. Slack uses the
owner's personal search grant, never the shared operator/bot identity.

The provider receives the query, date window, pagination parameters and personal
OAuth token. Gmail collection includes message/thread IDs, occurrence time,
subject/from headers and bounded snippets, not full mail bodies or attachments.
Slack collects message/channel/timestamp, optional parent timestamp and a bounded
text excerpt; a content digest distinguishes edits. These become ordinary encrypted
signal envelopes and may be copied into authorized Orbit history and model context
under the rules below. Polling is best-effort search, not a lossless event log.
Disconnect/account switching/current scope loss stops admission; an in-flight
provider request cannot be recalled. Existing evidence is not erased by disconnect.
Queries/checkpoints remain with the source until owner/source deletion under its
existing no-expiry/backup policy. A schema rollback removes polling configuration
and progress, not already-admitted signals/history.

Authorized operator exports must decrypt the applicable sources' query and binding
configuration, plus their watermark/window metadata. Exclude opaque upstream page
tokens and OAuth credentials. Poll jobs contain only source UUIDs; `.polled` audits
store actor/interface/source and admitted count, never queries or provider bodies.

Automation admissions and results carry opaque signal IDs/status only. Opening
copies bounded evidence, priority/reason and routed IDs/reason categories into an
ordinary shared Orbit system message; it also stores the source reader ceiling in
`orbit_threads.signal_reader_ids`. Those copies follow Orbit's existing history,
provider-sharing and deletion rules, including retention after owner deletion.
Pip receives the bounded transcript, not necessarily every byte of provider data.
No source, personal monitor, telemetry collection or provider grant is enabled
automatically; source owners explicitly configure and enable ingestion.

`signal_source.created`, `.updated`, `signal.received`, `.decided` and
`user.business_profile_updated` audits retain actor/interface and resource IDs,
not evidence/profile text. Corresponding MCP ingest/decision/profile-update
arguments are omitted from tool audits. Generic one-hour `orbit_signal` push jobs
contain the exact signal UUID and existing registration/user/thread IDs, never
evidence, title or routing text. Apple/Google receive only the generic attention
alert and native destination. Existing seven-day Oban pruning applies.

For verified exports, include the user's business profile and sources owned by or
whose `reader_ids` contain that user, then all signals by source. Also match users
inside `signals.decision.routing`; organizational/customer requests must inspect
the authorized decrypted envelopes for subject IDs or provider-specific references,
not just source ownership. Decrypt through Atlas's configured Cloak vault in the
authorized operator export, never a public query or log. Include linked Automation
revisions/runs/attempts, full Orbit history and `signal_reader_ids`, related jobs
and audits by actor or `signal_source`/`signal` targets. Apply third-party redaction.
Bounded API/MCP lists and current access are not complete legal exports. There are
no new object-storage paths; encrypted backups retain the existing backup policy.

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
- `orbit_runs`: assistant run status, nullable transient `activity` (`compacting` while Condukt prunes context; cleared on completion/retry), acting and initiating users, inference profile, trigger position, attempt counter, error category, cancellation and timing fields, the attempt's Condukt session ID, and `checkpoint`. The checkpoint is the exact model protocol messages at the start of the run's latest turn, including the request transcript, tool results and provider reasoning items (including opaque encrypted Codex state), encrypted with Atlas's Cloak vault. Reasoning is continuation state, not user-visible reply content or audit data, and is omitted before workspace-provider fallback. It exists only while a run is queued or running and is cleared when the run finishes.
- `orbit_viewers`: short-lived viewing leases with a random connection ID, thread and user references, typing expiry, and database-clock expiry. They are not audited, are renewed every ten seconds, and are swept after expiry. User and thread deletion cascade. Drafts never reach the server.

Thread run audit rows in `agent_sessions` store only an `orbit_run:<id>` label, a redacted result marker and fixed error categories. `agent_session_events` keep tool names, statuses and timings. Tool calls produce `mcp.tool_called` audit events with the thread and run IDs but without arguments. Membership changes, creation and signals produce `thread.*` audit events. Inference usage rows follow the existing relay retention.

`orbit_messages.suggestions` stores up to three model-authored follow-up prompts (120 Unicode codepoints / 480 UTF-8 bytes each) with the final agent reply. They are generated in the same provider turn from the same authorized conversation context, not a separate inference request. Suggestions inherit their message's thread access, indefinite history retention, deletion and backup policies. Include this string array when exporting applicable thread messages, including archived history and third-party redaction review. Native suggestion selection changes only an in-memory draft; only explicit Send creates a human message. Suggestions are not copied into audit metadata, push payloads or the durable native inbox cache.

`orbit_threads.model` stores the owner's optional model preference: null means Automatic, `workspace` selects the configured Orbit profile, and `chatgpt:<model-id>` selects that exact model using the acting person's account. `orbit_runs.model` freezes that preference at admission, including resumed and child work. Explicit selection never falls back to a different provider. These identifiers contain no credentials; they follow the thread/run retention and deletion rules and belong in their legal exports. Changes record `thread.model_changed` with actor, interface, thread target and the new model identifier. The live account model catalog is fetched on request, projected to identifiers/names/provider, and not stored in the database; upstream instructions, account claims and provider bodies never enter native responses or audits. Native catalog/selection state remains session-local; the durable preference stays on the thread.

Condukt's before/after pruning events no longer write transient `activity` rows or announce compaction without removed content. Actual pruning retains a generic system notice under ordinary message retention; no additional transcript or provider payload is stored.

Owner-only archive/restore changes the existing `orbit_threads.status` (`active`/`archived`) and records `thread.status_changed` with the new status, not message/file content. Archive is not deletion or a retention cutoff: messages, memberships and attached files remain protected and exportable as before. Active runs are cancelled/finalized, clearing encrypted checkpoints and tool-result caches under their existing terminal-run policy; delayed workers cannot revive them after restore. Restore does not start inference. Native lists default to active and offer an archived filter, but legal exports must include both statuses. No new customer-data columns or storage categories are introduced.

Native rich result cards are data-only projections of the existing redacted `orbit_messages.tool_output`, with no additional database rows, files, retention period or customer data collection. Their server-provided fallback is the same bounded evidence; export the source messages, not client renderer packages or caches.

Explicit native mentions store selected user UUIDs in `orbit_messages.mentioned_user_ids` (at most ten; empty for old messages). They are persistent attribution, not membership: removed/deleted users' UUIDs remain in the source message, and delivery always rechecks current access. Include these UUIDs in message exports and assess third-party redaction as for the other shared history. An owner mentioning a new eligible person promotes a private conversation to participant-scoped shared history, never public or company-wide visibility. All invitees must hold every ratcheted history scope. Earlier versions appended shared `notice_kind = "handoff"` excerpts; new invitations use the recipient-specific copies described below. Excerpts duplicate already-retained source text, not a generated summary or a new provider call. Promotion and invitations have `thread.promoted` / `thread.participant_added` audits. Name-only mention search stores no query or new directory records. A promoted thread retains its creation UUID: a private-creation replay conflicts safely rather than creating a second conversation.

New invitations (manual, explicit mentions, or automatic signal routing) append a shared `notice_kind = "joined"` naming the newcomer and a separate `private_handoff` addressed by `recipient_id`. The recipient's catch-up contains bounded initial-request/latest-Pip-reply excerpts, not generated prose. Its text is Cloak-encrypted in `private_body`; ordinary `body` is empty, including for older servers during rollout or image rollback. Only the recipient, while still authorized to read the thread, receives its decrypted presentation. Other participants, shared model transcripts, channels, audits and notification jobs receive no catch-up content. Historical `handoff` notices remain shared under their original retention policy. Private copies have no automatic expiry; thread deletion or recipient deletion cascades them, and schema rollback discards them rather than publishing their text. Shared join notices remain with history after a person leaves or is deleted.

`orbit_threads.priority` is nullable `now`/`today`/`later` signal queue metadata. Correlated signals can escalate priority, never silently lower it. Native inboxes order priorities before recency and filter active/archived before pagination; archive is recoverable queue resolution, not deletion.

For a verified personal-data request, also locate messages with the requester's UUID in `mentioned_user_ids` (`user_id = ANY(mentioned_user_ids)`) and private catch-ups with `recipient_id = user_id`, including after membership removal. Exclude every other recipient's private copies from an ordinary participant export; decrypt only the requester's private bodies through authorized operator tooling. Review third-party content before disclosure; current native read permissions are not a complete operator-level legal export.

Research helpers use the same run and durable tool-message history in both private and shared threads. Optional `orbit_messages.parent_message_id` links nested lookups to their task card in the same thread/run. There is no separate child conversation store, final reply or notification. Export parent and child messages with the thread; encrypted tool results retain the existing active-run lifetime.

`orbit_attachments` records private uploaded files: thread/message/uploader references, sanitized filename, content type, byte size, private object key, staging/expiry/deletion state, upload replay UUID, immutable payload digest and timestamps. Objects live at `orbit/threads/<thread-id>/attachments/<attachment-id>` in the existing private object store, not Documents. Pending uploads are uploader-only and expire after 24 hours; claimed files inherit the thread's current access and remain with its history. Discarded, expired and orphaned objects are deleted by the 15-minute cleanup worker; failed object deletions retain their ledger for retry. Removing a user does not remove files already shared into retained history. Deleting a message/thread retains the deletion ledger until its object is reclaimed.

An export must include attachment rows and actual object bytes for exported messages, plus the requester's unclaimed uploads and outstanding deletion-ledger rows where identifiable. Download bytes using the stored private object key through the operator's authorized storage tooling; do not generate public links. Native attachment APIs are access-filtered and are not a complete legal export. Pip sends recognized images and bounded text/PDF excerpts to the acting person's connected provider or the configured Orbit fallback; unsupported formats remain downloadable but are explicitly not read by the agent. Provider inputs exist in memory and encrypted active-run checkpoints, not audit or delivery-job payloads. Native downloaded previews use protected temporary files and are removed on dismissal/navigation; native drafts and retry bytes remain in memory.

The terminology migration renames the original draft tables and foreign keys in place, preserving IDs, history, encrypted execution caches and membership. Historical message text and audit events are not rewritten.

There is no automatic expiry for threads or messages. Administrators cannot read private threads through Atlas interfaces, but database operators and backups can. For a verified data request, select all the user's private conversations and every thread where they participate, and export shared `orbit_messages` plus only that user's recipient-specific copies for those threads, including each thread's creation replay UUID and priority where present. Messages authored by others are part of shared history and may require redaction before disclosure. Also include `orbit_runs` where the user is the initiating or acting user (excluding encrypted checkpoints, which are transient caches), any current `orbit_viewers` rows, and related audit events by `actor_id` or thread target. The paginated native API returns only threads the user can currently read and is not a complete legal export; the optional `kind=private` list filter intentionally omits shared threads but does not change direct-read authorization.

## Personal execution environments

`personal_environments` stores the owner's UUID (deletion cascades), immutable
native OAuth client UUID, installation UUID, bounded device name, opt-in enabled /
terminal / display booleans, and up to 100 project UUID/name pairs. Absolute local
project paths and OS permissions stay on the device and are never registered.
Version, current connection UUID and 20-second online expiry fence stale leases;
there is no navigation/activity history. Disable keeps an offline row, and no
automatic expiry is currently applied. Include disabled rows in legal exports.

`orbit_threads` additionally stores selected `environment_id`, its name snapshot,
`project_id`, and the permanent `personal_environment_dispatched` privacy marker.
`orbit_runs.environment_id` / `project_id` freeze selection when a run is created;
deployment/resume does not retarget existing commands. Shared threads cannot
dispatch personal commands. A thread that has dispatched cannot subsequently be
promoted/shared, even after clearing its selection. Selection alone may be cleared
on promotion without dispatching or collecting local content.

`environment_commands` is the at-most-once ledger for an Orbit tool card:
environment/version, thread/run/message UUIDs, fixed tool name, encrypted JSON
arguments (file-relative path or terminal command, plus the frozen opaque project UUID),
SHA-256 payload digest (binding command/environment/version/project/timeout),
single claim UUID, status, and timestamps. File commands retain their original
60-second expiry. Terminal additionally retains frozen environment/project display
labels and project UUID, fixed
600-second dispatch expiry, 1,800-second execution policy, execution and
result-delivery deadlines (five-minute grace), cancellation-request boolean,
monotonic progress sequence, encrypted UTF-8 tail output (48 KiB maximum), and the
continuation notice message UUID. The final UTF-8 output is bounded to 64 KiB and
stored as encrypted JSON `{success, output}`. Neither progress nor retries extend deadlines.
No claim is reassigned after disconnect/deployment/timeout. Known results are
retained; missing claimed outcomes are explicitly unknown, never presumed stopped
or silently retried. Owner cancellation cannot claim a disconnected process stopped.
Terminal dispatch requires the owner's explicit per-Mac terminal opt-in, without
per-command decisions. OAuth installation binding restricts claim/progress/result
to the original Mac.

`orbit_messages.device_input` / `device_output` retain encrypted, redacted bounded
native tool-card renderings (same 2,000/4,000 character budgets as other cards),
instead of copying paths/commands/file contents into plaintext card columns.
Active-run model results/checkpoints retain their existing encrypted transient
lifetime. Accepted ledger results and encrypted renderings follow message/thread
history retention, with no automatic expiry. Thread/run/message deletion cascades
the ledger; owner deletion cascades registrations and their ledger. Backups follow
the existing database policy. Authorized local content may appear in private final
replies and be sent to the acting person's selected model provider under Orbit's
existing provider policy; device execution does not move orchestration or model
credentials off-server. File tools are contained in the selected project. Terminal
commands (at most 8,000 UTF-8 bytes) start
in that project, but run as the macOS user without a folder sandbox and can access
outside it. The display setting does not enable screen capture or control tools.

Confirmed terminal completion updates its original encrypted card and appends one
generic system notice carrying bounded encrypted/redacted `device_output` evidence
(4,000 characters). The command's continuation notice UUID deduplicates completion
under the thread lock. Output is not stored in the plaintext notice body, Oban
arguments, audits or telemetry. The existing addressed-message/follow-up run and
Oban job recovery continue the conversation using current selection, possibly
server-only or another Mac, while the command retains its original source. A
bounded outbox sweep recovers unconsumed completion notices if a replica dies
before follow-up creation. Archive permanently retires their addressed flag.
Cancellation/unknown do not trigger inference; automatic continuation
reauthorizes history and source configuration. Notices/evidence use ordinary Orbit
history retention and legal-export authorization. The owner activity API exposes
only terminal metadata and bounded output (32 entries, 48 KiB per tail, 256 KiB
aggregate, additionally bounded for JSON escaping), without claim tokens or local
project roots. This is not a complete legal export.

For a verified legal export, select every `personal_environments.owner_id` row,
the selected/frozen metadata on that person's Orbit threads/runs, and every
associated `environment_commands` row, including decisions/deadlines/progress and
continuation notice relationships. Decrypt arguments/results/progress and message
device renderings with the operator-authorized Atlas vault tooling, not public
URLs. Treat local files, terminal output and any third-party content as sensitive.
Include `environment.*` and `thread.environment_selected` audits by actor/target;
these contain IDs, permission booleans, project counts and fixed action/tool names,
never command/argument/output payloads. Native environment and thread endpoints
are currently access-filtered and are not a complete operator-level legal export.

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
