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
