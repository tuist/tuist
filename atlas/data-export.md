# Atlas personal data

Atlas's personal LLM connections are separate from Tuist Server customer data and from Atlas's operator-configured inference providers.

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

## Conversations with the assistant

Conversations store people's messages to each other and to the Atlas assistant. They use the workspace's conversations inference profile, not personal AI accounts.

- `conversations`: kind (`private`/`shared`), title, status, optional signal summary and source type/ID, owner (`owner_id`, cleared on user deletion), the scopes its history requires (`required_scopes`), the latest sequence number, and timestamps. Each person has at most one private thread.
- `conversation_participants`: conversation and user references, role (`owner`/`member`), and join time. User deletion cascades.
- `conversation_messages`: message kind (`human`, `agent`, `tool`, `system`), Markdown body, author reference and an author-name snapshot, the client's idempotency UUID, whether the assistant was addressed, run reference, ordering numbers, and timestamps. Tool messages store the tool name, status, and redacted, bounded renderings of the input (≤2,000 characters) and output (≤4,000 characters). Values under credential-like or signed-link keys are replaced before storage. While a run is active, a completed tool card also holds the bounded result given to the model (`tool_result`, encrypted with Atlas's Cloak vault) and a hash of the call (`tool_call_key`), so a run resumed after a deploy does not execute the call again. The encrypted result is cleared when the run finishes. User deletion clears the author reference but keeps the message, its author-name snapshot, and the conversation history of other participants.
- `conversation_runs`: assistant run status, acting and initiating users, inference profile, trigger position, attempt counter, error category, cancellation and timing fields, the attempt's Condukt session ID, and `checkpoint`. The checkpoint is the exact model protocol messages at the start of the run's latest turn, including the request transcript and tool results, encrypted with Atlas's Cloak vault. It exists only while a run is queued or running and is cleared when the run finishes.
- `conversation_viewers`: short-lived viewing leases with a random connection ID, conversation and user references, typing expiry, and database-clock expiry. They are not audited, are renewed every ten seconds, and are swept after expiry. User and conversation deletion cascade. Drafts never reach the server.

Conversation run audit rows in `agent_sessions` store only a `conversation_run:<id>` label, a redacted result marker and fixed error categories. `agent_session_events` keep tool names, statuses and timings. Tool calls produce `mcp.tool_called` audit events with the conversation and run IDs but without arguments. Membership changes, creation and signals produce `conversation.*` audit events. Inference usage rows follow the existing relay retention.

Native rich result cards are data-only projections of the existing redacted `conversation_messages.tool_output`, with no additional database rows, files, retention period or customer data collection. Their server-provided fallback is the same bounded evidence; export the source messages, not client renderer packages or caches.

There is no automatic expiry for conversations or messages. Administrators cannot read private threads through Atlas interfaces, but database operators and backups can. For a verified data request, select the user's private conversation and every conversation where they participate, and export all `conversation_messages` for those conversations. Messages authored by others are part of shared history and may require redaction before disclosure. Also include `conversation_runs` where the user is the initiating or acting user (excluding encrypted checkpoints, which are transient caches), any current `conversation_viewers` rows, and related audit events by `actor_id` or conversation target. The paginated native API returns only conversations the user can currently read and is not a complete legal export.
