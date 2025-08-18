---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · AI · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
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
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```

:::

## Capabilities

In the following sections you'll learn about the capabilities of the Tuist MCP server.

### Recursos

#### Recent projects and workspaces

Tuist keeps a record of the Xcode projects and workspaces you’ve recently worked with, giving your application access to their dependency graphs for powerful insights. You can query this data to uncover details about your project structure and relationships, such as:

- What are the direct and transitive dependencies of a specific target?
- Which target has the most source files, and how many does it include?
- What are all the static products (e.g., static libraries or frameworks) in the graph?
- Can you list all targets, sorted alphabetically, along with their names and product types (e.g., app, framework, unit test)?
- Which targets depend on a particular framework or external dependency?
- What’s the total number of source files across all targets in the project?
- Are there any circular dependencies between targets, and if so, where?
- Which targets use a specific resource (e.g., an image or plist file)?
- What’s the deepest dependency chain in the graph, and which targets are involved?
- Can you show me all the test targets and their associated app or framework targets?
- Which targets have the longest build times based on recent interactions?
- What are the differences in dependencies between two specific targets?
- Are there any unused source files or resources in the project?
- Which targets share common dependencies, and what are they?

With Tuist, you can dig into your Xcode projects like never before, making it easier to understand, optimize, and manage even the most complex setups!
