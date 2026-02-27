---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP endpoint to give AI agents access to your project's test insights and more."
}
---
# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) is a standard for LLMs to interact with development environments.
MCP makes LLM-powered applications such as [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), and editors like [Zed](https://zed.dev), [Cursor](https://www.cursor.com), or [VS Code](https://code.visualstudio.com) interoperable with external services and data sources.

Tuist hosts a server-side MCP endpoint at `https://tuist.dev/mcp`. By connecting your MCP client to it, AI agents can access your Tuist project data, including test insights, flaky test analysis, and more.

## MCP vs Skills

MCP and <LocalizedLink href="/guides/features/agentic-coding/skills">Skills</LocalizedLink> can overlap in what they do. Given the current overlap between the two, choose one approach per workflow and use it consistently (either MCP or skills) instead of mixing both in the same flow.

## Configuration

Add `https://tuist.dev/mcp` as a remote MCP server in your client. Authentication happens through OAuth automatically.

::: details Claude Code
Run:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```
:::

::: details Claude Desktop
Open **Settings → Connectors → Add custom connector**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

Complete OAuth in the browser when prompted.
:::

::: details Cursor
Open **Cursor Settings → Tools & Integrations → MCP Tools** and add:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`
:::

::: details VS Code
Use **Command Palette → MCP: Add Server**, then configure an HTTP server with:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`
:::

::: details Zed
Open **Agent panel → Settings → Add Custom Server**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`
:::

## Capabilities

### Tools

The following tools are available through the Tuist MCP server:

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_projects` | List all projects accessible to the authenticated user. | None |
| `list_test_cases` | List test cases for a project (supports filters like `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Get detailed metrics for a test case including reliability rate, flakiness rate, and run counts. | `test_case_id` or `identifier` + `account_handle` + `project_handle` |
| `get_test_run` | Get detailed metrics for a test run. | `test_run_id` |
| `get_test_case_run` | Get failure details and repetitions for a specific test case run. | `test_case_run_id` |

#### `list_projects`

Returns all projects the authenticated user has access to, including each project's `id`, `name`, `account_handle`, and `full_handle`.

#### `list_test_cases`

Returns test cases for a given project. Supports pagination through `page` and `page_size`, and optional filters such as `flaky=true`, `quarantined=true`, `module_name`, `suite_name`, and `name`.

#### `get_test_case`

Returns detailed metrics for a specific test case: reliability rate (success percentage), flakiness rate (over the last 30 days), total and failed run counts, last status, and average duration. Accepts either a `test_case_id` (UUID) or an `identifier` in `Module/Suite/TestCase` or `Module/TestCase` format together with `account_handle` and `project_handle`.

#### `get_test_run`

Returns detailed test run context: status, duration, CI metadata, and aggregate counts (total/failed/flaky). Use `get_test_case_run` to drill into individual failures or crashes.

#### `get_test_case_run`

Returns the full details of a specific test case run, including failure messages with file paths and line numbers, repetition results, git branch, commit SHA, and whether the run was on CI.

### Prompts

| Prompt | Description |
|--------|-------------|
| `fix_flaky_test` | Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction. |

The `fix_flaky_test` prompt accepts optional arguments:

- `account_handle` and `project_handle`: scope the investigation to a specific project.
- `test_case_id`: jump directly to investigating a specific flaky test case by UUID (`list_test_cases[].id`) or identifier (`Module/Suite/TestCase` or `Module/TestCase`).

When invoked without arguments, the prompt guides the agent through discovering flaky tests across all accessible projects.
