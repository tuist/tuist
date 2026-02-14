---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's server-hosted MCP endpoint to give AI agents access to your project's test insights and more."
}
---
# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) is a standard for LLMs to interact with development environments.
MCP makes LLM-powered applications such as [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), and editors like [Zed](https://zed.dev), [Cursor](https://www.cursor.com), or [VS Code](https://code.visualstudio.com) interoperable with external services and data sources.

Tuist hosts a server-side MCP endpoint at `https://tuist.dev/mcp`. By connecting your MCP client to it, AI agents can access your Tuist project data, including test insights, flaky test analysis, and more.

## Authentication

The MCP endpoint is protected by OAuth 2.0. MCP clients that support the OAuth-based authentication flow will handle the handshake automatically. The discovery endpoints are:

- **Authorization server metadata:** `https://tuist.dev/.well-known/oauth-authorization-server`
- **Protected resource metadata:** `https://tuist.dev/.well-known/oauth-protected-resource/mcp`

When your MCP client connects, it will:

1. Discover the authorization server via the metadata endpoints.
2. Redirect you to sign in through Tuist's OAuth flow.
3. Obtain an access token and use it for subsequent MCP requests.

## Configuration

Point your MCP client at the Tuist server endpoint. The exact configuration depends on your client, but it typically involves setting the MCP server URL to:

```
https://tuist.dev/mcp
```

Refer to your MCP client's documentation for how to add a remote (HTTP-based) MCP server.

## Capabilities

### Tools

The following tools are available through the Tuist MCP server:

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_projects` | List all projects accessible to the authenticated user. | None |
| `list_flaky_tests` | List flaky test cases for a project. | `account_handle`, `project_handle` |
| `get_test_case` | Get detailed metrics for a test case including reliability rate, flakiness rate, and run counts. | `test_case_id` |
| `get_test_case_run` | Get failure details and repetitions for a specific test case run. | `test_case_run_id` |

#### `list_projects`

Returns all projects the authenticated user has access to, including each project's `id`, `name`, `account_handle`, and `full_handle`.

#### `list_flaky_tests`

Returns flaky test cases for a given project. Each result includes the test case name, module, suite, flaky run count, and when it was last flaky. Supports pagination through `page` and `page_size` parameters.

#### `get_test_case`

Returns detailed metrics for a specific test case: reliability rate (success percentage), flakiness rate (over the last 30 days), total and failed run counts, last status, and average duration.

#### `get_test_case_run`

Returns the full details of a specific test case run, including failure messages with file paths and line numbers, repetition results, git branch, commit SHA, and whether the run was on CI.

### Prompts

| Prompt | Description |
|--------|-------------|
| `fix_flaky_test` | Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction. |

The `fix_flaky_test` prompt accepts optional arguments:

- `account_handle` and `project_handle`: scope the investigation to a specific project.
- `test_case_id`: jump directly to investigating a specific flaky test case.

When invoked without arguments, the prompt guides the agent through discovering flaky tests across all accessible projects.
