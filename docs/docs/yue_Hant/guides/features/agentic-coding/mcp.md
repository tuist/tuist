---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) is a standard proposed
by [Claude](https://claude.ai) for LLMs to interact with development
environments. You can think of it as the USB-C of LLMs. Like shipping
containers, which made cargo and transportation more interoperable, or protocols
like TCP, which decoupled the application layer from the transport layer, MCP
makes LLM-powered applications such as [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code), and editors like
[Zed](https://zed.dev), [Cursor](https://www.cursor.com), or [VS
Code](https://code.visualstudio.com) interoperable with other domains.

Tuist provides a local server through its CLI so that you can interact with your
**app development environment**. By connecting your client apps to it, you can
use language to interact with your projects.

In this page you'll learn about how to set it up and its capabilities.

::: info
<!-- -->
Tuist MCP server uses Xcode's most-recent projects as the source of truth for
projects you want to interact with.
<!-- -->
:::

## Set it up

Tuist provides automated setup commands for popular MCP-compatible clients.
Simply run the appropriate command for your client:

### [Claude](https://claude.ai)

For [Claude desktop](https://claude.ai/download), run:
```bash
tuist mcp setup claude
```

This will configure the file at `~/Library/Application
Support/Claude/claude_desktop_config.json`.

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

For Claude Code, run:
```bash
tuist mcp setup claude-code
```

This will configure the same file as Claude desktop.

### [Cursor](https://www.cursor.com)

For Cursor IDE, you can configure it globally or locally:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

For Zed editor, you can also configure it globally or locally:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

For VS Code with MCP extension, configure it globally or locally:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Manual Configuration

If you prefer to configure manually or are using a different MCP client, add the
Tuist MCP server to your client's configuration:

::: code-group

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
<!-- -->
:::

## Capabilities

In the following sections you'll learn about the capabilities of the Tuist MCP
server.

### Resources

#### Recent projects and workspaces

Tuist keeps a record of the Xcode projects and workspaces you’ve recently worked
with, giving your application access to their dependency graphs for powerful
insights. You can query this data to uncover details about your project
structure and relationships, such as:

- What are the direct and transitive dependencies of a specific target?
- Which target has the most source files, and how many does it include?
- What are all the static products (e.g., static libraries or frameworks) in the
  graph?
- Can you list all targets, sorted alphabetically, along with their names and
  product types (e.g., app, framework, unit test)?
- Which targets depend on a particular framework or external dependency?
- What’s the total number of source files across all targets in the project?
- Are there any circular dependencies between targets, and if so, where?
- Which targets use a specific resource (e.g., an image or plist file)?
- What’s the deepest dependency chain in the graph, and which targets are
  involved?
- Can you show me all the test targets and their associated app or framework
  targets?
- Which targets have the longest build times based on recent interactions?
- What are the differences in dependencies between two specific targets?
- Are there any unused source files or resources in the project?
- Which targets share common dependencies, and what are they?

With Tuist, you can dig into your Xcode projects like never before, making it
easier to understand, optimize, and manage even the most complex setups!
