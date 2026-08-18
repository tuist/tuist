---
{
  "title": "Plugins",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Install Tuist's plugin for Cursor or the vendor-neutral Agent Plugins package."
}
---

# Plugins

Tuist packages its agent skills and hosted [Model Context Protocol](https://modelcontextprotocol.io/) server as plugins so you can install both together. Choose the package that matches your coding agent.

## Cursor

Install the [Tuist plugin for Cursor](https://github.com/tuist/cursor-plugin) from the [Cursor Marketplace](https://cursor.com/marketplace):

1. Open **Customize** in the Cursor sidebar.
2. Search for **Tuist**.
3. Select **Install**, then choose whether to install it for the current project or your user account.

You can also type `/add-plugin` in Cursor to open the same installation flow. The plugin provides Tuist skills and connects Cursor to the hosted Model Context Protocol server.

If your organization manages Cursor marketplaces, import `https://github.com/tuist/cursor-plugin` from **Settings → Plugins → Team Marketplaces → Import Marketplace** first.

## Other coding agents

The [Tuist Agent Plugin](https://github.com/tuist/agent-plugin) follows the open, vendor-neutral [Agent Plugins](https://agent-plugins.org/) standard. Point a compatible client at the repository, following that client's instructions for installing or referencing plugin directories:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

It installs Tuist skills and registers `https://tuist.dev/mcp` as a remote Model Context Protocol server. For clients that do not yet support Agent Plugins, install the [skills](/guides/features/agentic-coding/skills) or configure the [Model Context Protocol server](/guides/features/agentic-coding/mcp) separately.

## Authentication

Most skills use the Tuist command-line interface, so authenticate it once before asking an agent to access your project data:

```bash
tuist auth login
```

The hosted Model Context Protocol server requests its own sign-in when needed. See the [Model Context Protocol guide](/guides/features/agentic-coding/mcp) for client-specific setup and authentication details.
