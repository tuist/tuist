# Atlas personal provider connection data

Atlas's personal LLM connections are separate from Tuist Server customer data and from Atlas's operator-configured inference providers.

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
