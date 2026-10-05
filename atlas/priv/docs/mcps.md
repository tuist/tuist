Atlas can bring tools from other [Model Context Protocol servers](https://modelcontextprotocol.io/docs/learn/architecture) into its authenticated tool endpoint. An administrator adds a server once, and each person authorizes Atlas to use that server on their behalf. Atlas then offers the permitted upstream tools alongside its own tools. A fresh installation starts with no upstream servers.

## What this feature does

Atlas acts as a proxy between a tool client and the external server. It discovers the external server's tools for the current person and forwards permitted calls using that person's saved authorization. Servers added through Atlas expose only tools that the upstream marks as read-only. If the upstream marks no tools as read-only, Atlas exposes none; this classification comes from the upstream itself.

The server definition is shared across the workspace, while authorization is separate for each person. An administrator can add, edit, or remove a definition without restarting Atlas. Changing its settings or removing it also deletes the saved authorization sessions for that server, so each person must reconnect.

## When to use it

Use this when your team wants to reach tools from another service through Atlas, with each person's own access to that service. For example, an external service can provide search or diagnostics tools to an agent already connected to Atlas. Add the server in Atlas when its tool endpoint supports per-user authorization and you only need its read-only tools.

If the connection needs shared credentials, custom request headers, or a privileged identity header, configure it at deployment instead. Those options are intentionally unavailable to runtime-managed servers.

## Permissions

The `/admin/mcps` dashboard requires `admin:read` to open. Adding, editing, and removing servers requires `admin:write`; the available management tools require that same write scope. Each person who uses a server must authorize their own upstream session. The connection route requires an authenticated Atlas account.

## Ways to manage servers

The `/admin/mcps` dashboard lists configured upstream servers and each person's connection status. Administrators with write access can use **Add server** to enter the server's public `https://` tool address and authorization and token endpoints. The registration endpoint and requested scopes are optional. **Edit** opens the same form with the saved settings. Saving changed settings disconnects all users of that server, who must reconnect; saving the form without changes preserves their connections. **Remove** deletes a runtime-managed server and all its saved sessions. **Connect** starts per-user [Open Authorization 2.0](https://oauth.net/2/); **Reconnect** repeats it when needed.

Tool clients can send [Model Context Protocol requests](https://modelcontextprotocol.io/specification/2025-06-18/basic) to Atlas's authenticated `/mcp` endpoint. The server-management tools are available only with `admin:write`. These are the currently supported operations:

| Operation | Dashboard | Tool call |
| --- | --- | --- |
| Create | **Add server** | `create_mcp_server` with `name`, `url`, `authorization_url`, `token_url`, and optional `registration_url` and `scopes` |
| Read | Server list and connection status | `get_mcp_connection_status` with `server` checks one permitted server's live connection and tools; there is no tool for reading saved server definitions |
| Update | **Edit** opens the server form with its saved settings | No update tool is available |
| Delete | **Remove** | `delete_mcp_server` with `name` |

For tool clients, create and delete are `tools/call` requests sent to `POST /mcp`. For example, a create request has this shape:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "create_mcp_server",
    "arguments": {
      "name": "example",
      "url": "https://tools.example.org/mcp",
      "authorization_url": "https://tools.example.org/oauth/authorize",
      "token_url": "https://tools.example.org/oauth/token",
      "scopes": ["tools:read"]
    }
  }
}
```

The delete call uses the same request envelope with `"name": "delete_mcp_server"` and `"arguments": {"name": "example"}`. Atlas does not expose separate create, read, update, and delete web routes for these definitions. Deployment-configured servers are read-only in the dashboard and management tools; they can include shared credentials or headers that runtime-managed servers cannot set.
