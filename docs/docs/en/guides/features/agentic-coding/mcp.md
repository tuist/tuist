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

Add `https://tuist.dev/mcp` as a remote MCP server in your client. Authentication happens through OAuth automatically. The MCP endpoint uses the `mcp` scope group, which grants read-only access to all your projects. See the <LocalizedLink href="/guides/server/authentication#scope-groups">scope groups documentation</LocalizedLink> for details.

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

::: details OpenCode
Add the Tuist MCP server to `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

Then authenticate the server:

```bash
opencode mcp auth tuist
```
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

#### Projects

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_projects` | List all projects accessible to the authenticated user. | None |

#### Xcode builds

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_xcode_builds` | List Xcode build runs for a project. | `account_handle`, `project_handle` |
| `get_xcode_build` | Get detailed information about a specific Xcode build run. Accepts a build ID or a Tuist dashboard URL. | `build_run_id` |
| `list_xcode_build_targets` | List build targets for a specific Xcode build run. | `build_run_id` |
| `list_xcode_build_files` | List compiled files for a specific Xcode build run. | `build_run_id` |
| `list_xcode_build_issues` | List build issues (warnings and errors) for a specific build run. | `build_run_id` |
| `list_xcode_build_cache_tasks` | List cacheable tasks (cache hits/misses) for a specific Xcode build run. | `build_run_id` |
| `list_xcode_build_cas_outputs` | List CAS (Content Addressable Storage) outputs for a specific Xcode build run. | `build_run_id` |

#### Gradle builds

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_gradle_builds` | List Gradle build runs for a project. | `account_handle`, `project_handle` |
| `get_gradle_build` | Get detailed information about a specific Gradle build run. | `build_run_id` |
| `list_gradle_build_tasks` | List tasks for a specific Gradle build run, including outcome and cache status. | `build_run_id` |

#### Tests

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_test_runs` | List test runs for a project. | `account_handle`, `project_handle` |
| `get_test_run` | Get detailed metrics for a test run. | `test_run_id` |
| `list_test_module_runs` | List test module runs for a specific test run. | `test_run_id` |
| `list_test_suite_runs` | List test suite runs for a specific test run, optionally filtered by module. | `test_run_id` |
| `list_test_cases` | List test cases for a project (supports filters like `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Get detailed metrics for a test case including reliability rate, flakiness rate, and run counts. | `test_case_id` or `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | List test case runs, optionally filtered by test case or test run. | `account_handle`, `project_handle` |
| `get_test_case_run` | Get failure details and repetitions for a specific test case run. | `test_case_run_id` |
| `list_test_case_run_attachments` | List attachments for a test case run. Each attachment includes a temporary download URL. | `test_case_run_id` |

#### Bundles

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_bundles` | List bundles (app binaries) for a project. | `account_handle`, `project_handle` |
| `get_bundle` | Get detailed information about a specific bundle. | `bundle_id` |
| `get_bundle_artifact_tree` | Get the full artifact tree for a bundle as a flat list sorted by path. | `bundle_id` |

#### Generations

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_generations` | List generation runs for a project. | `account_handle`, `project_handle` |
| `get_generation` | Get detailed information about a specific generation run. | `generation_id` |

#### Cache runs

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_cache_runs` | List cache runs for a project. | `account_handle`, `project_handle` |
| `get_cache_run` | Get detailed information about a specific cache run. | `cache_run_id` |
| `list_xcode_module_cache_targets` | List module cache targets for a generation or cache run, showing per-target cache hit/miss status. | `run_id` |

### Prompts

| Prompt | Description |
|--------|-------------|
| `fix_flaky_test` | Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction. |
| `compare_builds` | Guides you through comparing two build runs to identify performance regressions, cache changes, and build issues. Works with both Xcode and Gradle projects. |
| `compare_test_runs` | Guides you through comparing two test runs to identify regressions, new failures, and flaky tests. |
| `compare_bundles` | Guides you through comparing two bundles to identify size changes across the artifact tree. |
| `compare_test_case` | Guides you through comparing a test case's behavior across two branches or time periods. |
| `compare_generations` | Guides you through comparing two generation runs to identify performance regressions and module cache changes. |
| `compare_cache_runs` | Guides you through comparing two cache runs to identify cache effectiveness changes and target-level regressions. |

All prompts accept `account_handle` and `project_handle` to scope the investigation to a specific project. The comparison prompts also accept `base` and `head` arguments to specify the two items to compare (by ID, dashboard URL, or branch name).
