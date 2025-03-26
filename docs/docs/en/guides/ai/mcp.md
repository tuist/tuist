---
title: Model Context Protocol (MCP)
titleTemplate: :title · AI · Guides · Tuist
description: Learn how to use Tuist's MCP server to have a language-based interface for your app development environment.
---

# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) is a standard proposed by [Claude](https://claude.ai) for LLMs to interact with development environments.
You can think of it as the USB-C of LLMs.
Like shipping containers, which made cargo and transportation more interoperable,
or protocols like TCP, which decoupled the application layer from the transport layer,
MCP makes LLM-powered applications such as [Claude](https://claude.ai/) and editors like [Zed](https://zed.dev) or [Cursor](https://www.cursor.com) interoperable with other domains.

Tuist provides a local server through its CLI so that you can interact with your **app development environment**.
By connecting your client apps to it, you can use language to interact with your projects.

In this page you'll learn about how to set it up and its capabilities.

> [!NOTE]
> Tuist MCP server uses Xcode's most-recent projects as the source of truth for projects you want to interact with.

## Set it up

### [Claude](https://claude.ai)

If you are using [Claude desktop](https://claude.ai/download), you can run the <LocalizedLink href="/cli/mcp/setup/claude">tuist mcp setup claude</LocalizedLink> command to configure your Claude environment.

Alternatively, can manually edit the file at `~/Library/Application\ Support/Claude/claude_desktop_config.json`, and add the Tuist MCP server:

:::code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
:::

## Cursor

If you are using [Cursor](https://www.cursor.com), you can run the <LocalizedLink href="/cli/mcp/setup/cursor">tuist mcp setup cursor</LocalizedLink> command to configure your Claude environment.

Alternatively, can manually edit the file at `.cursor/mcp.json`, and add the Tuist MCP server:

:::code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
:::
