Manage the signed-in user's Claude and ChatGPT connections through [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/learn/architecture) tools at Atlas's authenticated `/mcp` endpoint. For dashboard instructions, see [Connect Claude or ChatGPT](/docs/ai-accounts).

Any authenticated user can manage their own AI accounts without administrator scopes. These tools cannot select another owner or change installation-wide inference configuration. Saving a connection does not start or enable agent execution.

## Tools

| Operation | Tool call | Result |
| --- | --- | --- |
| Create or update Claude | `connect_claude_provider` with `token` | Creates the caller's connection or replaces its saved token; returns configuration status only |
| Start ChatGPT sign-in | `start_chatgpt_provider_login` with no arguments | Returns `login_id`, `user_code`, `verification_url`, `interval` in seconds, and `expires_at`; an existing saved connection stays unchanged until authorization succeeds |
| Complete ChatGPT sign-in | `poll_chatgpt_provider_login` with `login_id` | Returns `status: pending` or `status: connected`; successful authorization saves or replaces credentials internally |
| Cancel ChatGPT sign-in | `cancel_chatgpt_provider_login` with `login_id` | Clears that pending sign-in without removing previously saved credentials |
| List connections | `list_llm_provider_connections` with no arguments | Lists Claude and ChatGPT metadata: `provider`, `credential_configured`, `login_available`, `expires_at`, and `updated_at` |
| Disconnect | `disconnect_llm_provider` with `provider: claude` or `provider: chatgpt` | Removes the caller's saved credentials and pending sign-in from Atlas; does not revoke upstream access |

## ChatGPT authorization

Ask the user before starting authorization or replacing credentials. After `start_chatgpt_provider_login`, show the returned verification URL and code to the user, then wait at least `interval` seconds between polls with the same `login_id`. Stop on `connected`.

A pending sign-in blocks another start until completion, cancellation, or expiry. Sign-in expires after 15 minutes. Atlas permits at most five start attempts per user in five minutes. Transient polling failures can be retried after the interval; an expired or missing sign-in needs a new start.

If `login_available` is false, an administrator must [enable ChatGPT sign-in](/docs/self-hosting#enable-chatgpt-sign-in). These tools cannot change installation-wide authorization-client configuration.

## Credential privacy

Prefer the browser form for Claude credential entry. Using `connect_claude_provider` sends the token through your MCP client and potentially its model or conversation history, even though Atlas omits the complete argument payload from its audit record. Obtain explicit user approval before submitting a token.

The ChatGPT tools return only user-facing authorization instructions and an owner-scoped login handle, never access tokens, refresh tokens, upstream device IDs, or authorization proof material. Atlas encrypts saved credentials and never returns them through read tools, authenticated endpoints, or prefilled forms.

Disconnecting deletes Atlas's copy. To revoke access, the user must also visit their Claude or OpenAI account settings.
