Atlas can bring tools from other [MCP servers](https://modelcontextprotocol.io/docs/learn/architecture) into its authenticated tool endpoint. An administrator adds a server once, choosing per-user OAuth or a shared API key. For OAuth, each person authorizes Atlas to use that server on their behalf. Atlas then offers the permitted upstream tools alongside its own tools. A fresh installation starts with no upstream servers.

## How Atlas proxies tools

Atlas acts as a proxy between a tool client and the external server. It discovers the external server's tools and forwards permitted calls using the current person's saved OAuth authorization or the server's shared API key. Servers added through Atlas expose only tools that the upstream marks as read-only. If the upstream marks no tools as read-only, Atlas exposes none; this classification comes from the upstream itself.

The server definition is shared across the workspace. OAuth authorization is separate for each person; a shared API key gives every permitted Atlas caller the same upstream access. An administrator can add, edit, or remove a definition without restarting Atlas. Changing its settings or removing it also deletes the saved OAuth sessions for that server, so OAuth users must reconnect.

## When to add an upstream server

Use this when your team wants to reach tools from another service through Atlas, with each person's own access to that service. For example, an external service can provide search or diagnostics tools to an agent already connected to Atlas. Add the server in Atlas when its tool endpoint supports OAuth or an `Authorization: Bearer` API key and you only need its read-only tools. Use a shared key only when its permissions are appropriate for everyone who can use the server through Atlas.

If the connection needs custom request headers or a privileged identity header, configure it at deployment instead. Those options are intentionally unavailable to runtime-managed servers.

## Who can manage servers

The `/admin/mcps` dashboard requires `admin:read` to open. Adding, editing, and removing servers requires `admin:write`; the available management tools require that same write scope. Each person who uses an OAuth server must authorize their own upstream session. Shared-key servers need no per-user connection. The connection route requires an authenticated Atlas account.

## Configure and connect servers

The `/admin/mcps` dashboard lists configured upstream servers and each person's connection status. Administrators with write access can use **Add server** to enter a lowercase server name (for example, `integral`) and the server's public `https://` tool address, then choose **Authentication**:

- **OAuth (per user)** requires authorization and token endpoints. The registration endpoint and requested scopes are optional.
- **Bearer token (shared API key)** requires only the API key, without the `Bearer ` prefix. Atlas adds the authorization header automatically. The key is stored encrypted and is never prefilled in the edit form. Leave the key blank when editing to keep it, or enter a replacement to rotate it. Switching to OAuth deletes the saved key. Keys must follow the [standard bearer-token syntax](https://www.rfc-editor.org/rfc/rfc6750#section-2.1) and contain no whitespace.

**Edit** opens the same form with the saved settings. Saving changed settings disconnects saved OAuth sessions, whose users must reconnect; saving the form without changes preserves their connections. Shared-key changes take effect immediately without a connection step. **Remove** deletes a runtime-managed server and all its saved sessions. **Connect** starts per-user [OAuth 2.0](https://oauth.net/2/); **Reconnect** repeats it when needed.

For shared keys, **Key configured** means Atlas has saved the credential, not that the upstream has accepted it. Use `get_mcp_connection_status` to check live discovery and the currently available tools.

Tool clients can send [MCP requests](https://modelcontextprotocol.io/specification/2025-06-18/basic) to Atlas's authenticated `/mcp` endpoint. The server-management tools are available only with `admin:write`. These are the currently supported operations:

| Operation | Dashboard | Tool call |
| --- | --- | --- |
| Create | **Add server** | `create_mcp_server` with `name` and `url`; OAuth (default) also requires `authorization_url` and `token_url`, with optional `registration_url` and `scopes`; for a shared key, set `auth_type` to `bearer_token` and supply `bearer_token` |
| Read | Server list and connection status | `get_mcp_connection_status` with `server` checks one permitted server's live connection and tools; there is no tool for reading saved server definitions |
| Update | **Edit** opens the server form with its saved settings | No update tool is available |
| Delete | **Remove** | `delete_mcp_server` with `name` |

Deployment-configured servers can be viewed here, but their settings stay in deployment configuration. They cannot be edited or removed from the dashboard or management tools.

## Personal AI providers

Personal Claude and ChatGPT connections are separate from upstream MCP servers and Atlas's installation-wide inference providers. They belong to the signed-in Atlas user, not the workspace. Any authenticated user can manage their own connections without administrator scopes; neither the dashboard nor the tools let you choose another owner. Saving these connections is groundwork for user-triggered agent sessions; it does not start or enable agent execution by itself.

Open your avatar menu, choose **Account settings**, then **AI providers** at `/settings/llm-providers`. **Add provider** opens a provider dropdown whose selection changes the setup form. Saved connections appear in a table; use a row's **Update credentials** action to replace a connection, or **Disconnect** to delete Atlas's saved copy.

For Claude, install [Claude Code](https://code.claude.com/docs/en/setup), run `claude setup-token` on your computer, and paste the resulting subscription token into the Claude form. This is not an Anthropic API key. Atlas validates the token's format, but saving it does not verify upstream access. Provider terms and subscription eligibility still apply.

For ChatGPT, select **ChatGPT**, start sign-in, and open the displayed OpenAI verification URL yourself. Enter the one-time code only if you initiated that sign-in. Atlas never asks for your OpenAI password. The device sign-in expires after 15 minutes, and Atlas waits for authorization before saving or replacing credentials. Closing the modal or selecting a different provider cancels the pending sign-in and preserves any previous connection.

The authenticated `/mcp` endpoint exposes these create, read, update, and delete operations:

| Operation | Tool call | Result |
| --- | --- | --- |
| Create or update Claude | `connect_claude_provider` with `token` | Creates the caller's connection or replaces its saved token; returns configuration status only |
| Create or update ChatGPT | `start_chatgpt_provider_login` with no arguments | Returns `login_id`, `user_code`, `verification_url`, `interval` in seconds, and `expires_at`; an existing saved connection stays unchanged until authorization succeeds |
| Complete ChatGPT sign-in | `poll_chatgpt_provider_login` with `login_id` | Returns `status: pending` or `status: connected`; successful authorization saves or replaces credentials internally |
| Cancel ChatGPT sign-in | `cancel_chatgpt_provider_login` with `login_id` | Clears that pending sign-in without removing previously saved credentials |
| Read | `list_llm_provider_connections` with no arguments | Lists Claude and ChatGPT metadata: `provider`, `credential_configured`, `login_available`, `expires_at`, and `updated_at` |
| Delete | `disconnect_llm_provider` with `provider: claude` or `provider: chatgpt` | Removes the caller's saved credentials and pending sign-in from Atlas |

Ask the user before starting authorization or replacing credentials. After `start_chatgpt_provider_login`, show the returned verification URL and code to the user, then wait at least `interval` seconds between polls with the same `login_id`. Stop on `connected`. A pending sign-in blocks another start until completion, cancellation, or expiry. Atlas permits at most five start attempts per user in five minutes. Transient polling failures can be retried after the interval; an expired or missing sign-in needs a new start.

Prefer the browser form for Claude credential entry. Using `connect_claude_provider` sends the token through your MCP client and potentially its model or conversation history, even though Atlas omits the complete argument payload from its audit record. The ChatGPT tools return only user-facing authorization instructions and an owner-scoped login handle, never access tokens, refresh tokens, upstream device IDs, or PKCE material. Atlas encrypts saved credentials and never returns them through read tools, APIs, or prefilled forms.

**Disconnect** deletes Atlas's copy; it does not revoke access at Claude or OpenAI. Revoke access separately in the provider's account settings when needed.

## Enable ChatGPT sign-in

If the form says ChatGPT sign-in has not been enabled, this is an installation prerequisite, not a missing personal account setting. An operator must supply `ATLAS_CHATGPT_CLIENT_ID` and restart Atlas. The client must be authorized for Atlas and have OpenAI's required device authorization flow enabled. Do not reuse Codex's or another application's client ID, and do not substitute an OpenAI API key. This feature is not available merely by creating a standard API key; if you do not have an appropriately authorized client, leave ChatGPT sign-in disabled. Claude setup-token connections do not require this setting.

For a [self-hosted installation](/docs/self-hosting), put the authorized client ID in the application's environment. With Compose, add it to the deployment's private `.env` file; with Helm, include it in the Secret referenced by `appSecretName`. Restart the application after changing it. The personal-provider MCP tools cannot change installation-wide OAuth client configuration. A configured client enables the sign-in UI, but real-account authorization still depends on the provider's eligibility and authorization policies.
