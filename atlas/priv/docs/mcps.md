Atlas can bring tools from other [Model Context Protocol servers](https://modelcontextprotocol.io/docs/learn/architecture) into its authenticated tool endpoint. An administrator adds a server once, and each person connects their own account to it. Atlas then makes the permitted upstream tools available alongside its own tools. A fresh installation starts with no upstream servers.

## Add a server

Sign in with `admin:write` access and open `/admin/mcps`. Select **Add server** to open the form. Give the server a name, its public `https://` tool address, and its authorization and token endpoint addresses. The registration endpoint and requested authorization scopes are optional. Select **Add server** again to save it. Atlas lists the server immediately, without a restart.

Servers added in Atlas use per-user [Open Authorization 2.0](https://oauth.net/2/). They expose only tools that the upstream marks as read-only. A server that marks no tools as read-only exposes none; Atlas relies on the upstream's own classification.

## Connect your account

Find the server on `/admin/mcps` and select **Connect**. Complete the upstream's authorization flow to give Atlas access on your behalf. Each person has a separate saved session. If authorization expires or is revoked, use **Reconnect** on the same page.

## Manage servers with tools

Authenticated clients with `admin:write` access can use `create_mcp_server` and `delete_mcp_server` instead of the page. Creation takes the server name and addresses, plus an optional array of scopes; deletion takes the name. Administrators with `admin:read` access can inspect the page but cannot add or remove servers, and these management tools are not available to them.

## Remove a server

Select **Remove** on `/admin/mcps`, or call `delete_mcp_server`. Removal also deletes every person's saved authorization session for that server. If you add the server again, each person must connect again.

Servers supplied by deployment configuration cannot be removed from the page or with the tool. Shared credentials, custom request headers, and privileged identity headers are deployment settings rather than administrator-managed options.

## Deployment configuration

The `MCP_PROXY_SERVERS` deployment setting can provide upstream servers that need options unavailable in the page. An unset or empty value starts with none; the default for a new self-hosted installation is `[]`. Servers added in Atlas are stored separately and work alongside deployment-configured servers. Their names cannot duplicate a deployment-configured name.

Tuist's managed production deployment explicitly sets `MCP_PROXY_SERVERS=tuist-managed` to retain its Tuist, Grafana, and Sentry connections. An older installation that depended on those servers appearing when the setting was unset must set this value before upgrading. Other installations can keep `[]` and add servers in Atlas as needed.
