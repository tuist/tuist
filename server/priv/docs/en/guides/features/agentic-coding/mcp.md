---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Give AI agents access to test insights and more via Tuist's MCP endpoint."
}
---
# Model Context Protocol (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) is a standard for LLMs to interact with development environments.
MCP makes LLM-powered applications such as [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), and editors like [Zed](https://zed.dev), [Cursor](https://www.cursor.com), or [VS Code](https://code.visualstudio.com) interoperable with external services and data sources.

Tuist hosts a server-side MCP endpoint at `https://tuist.dev/mcp`. By connecting your MCP client to it, AI agents can access your Tuist project data, including test insights, flaky test analysis, and more.
Most MCP tools are read-only and scoped to authenticated Tuist project data. Account setup tools can create organizations, create projects, and add existing users to organizations when the authenticated user has the required permissions.
The account setup tools require user authentication. They are not available to project tokens or account tokens.

## MCP vs Skills

MCP and <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> can overlap in what they do. Given the current overlap between the two, choose one approach per workflow and use it consistently (either MCP or skills) instead of mixing both in the same flow.

## Configuration

Add `https://tuist.dev/mcp` as a remote MCP server in your client. Tuist advertises both OAuth discovery metadata and an `auth.md` file at `https://tuist.dev/auth.md`.

Clients that already support remote MCP OAuth can continue authenticating in the browser. Clients and agents that support `auth.md` can use Tuist's agent registration endpoints. Tuist supports agent-verified ID-JAG registration, user-claimed anonymous start with an API key, and user-claimed email-required registration with either an access token or API key.

The MCP endpoint uses the `mcp` scope group, which grants read-only access to all your projects. The resulting credential is still user-scoped, so account setup tools are only available when the authenticated user has the required permissions. See the <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link> for details.

<details>
<summary>Claude Code</summary>

Run:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

</details>


<details>
<summary>Claude Desktop</summary>

Open **Settings → Connectors → Add custom connector**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

Complete OAuth in the browser when prompted.

</details>


<details>
<summary>OpenCode</summary>

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

</details>


<details>
<summary>Cursor</summary>

Open **Cursor Settings → Tools & Integrations → MCP Tools** and add:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>VS Code</summary>

Use **Command Palette → MCP: Add Server**, then configure an HTTP server with:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

Open **Agent panel → Settings → Add Custom Server**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

If your agent supports `auth.md`, you can connect without opening a browser. Depending on the agent, Tuist will either confirm with the agent provider directly or email you a secure link with a six-digit code to read back to the agent.


## Capabilities

### Tools

The following tools are available through the Tuist MCP server:

Every tool publishes a human-readable description together with explicit input and output schemas. Successful calls return structured content that conforms to the advertised output schema, plus the same result serialized as text for clients that do not yet consume structured content.

#### Projects

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `create_organization` | Create a Tuist organization for the authenticated user. | `handle` |
| `create_project` | Create a Tuist project under an account the authenticated user can access. | `account_handle`, `project_handle` |
| `add_organization_member` | Add an existing Tuist user to an organization or update an existing member's role. | `organization_handle`, `email` |
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
| `list_test_runs` | List test runs for a project. Supports exact filters such as `git_branch`, `status`, and `scheme`, plus richer `query` expressions such as `-git_branch~"gh-readonly-queue"`. | `account_handle`, `project_handle` |
| `get_test_run` | Get detailed metrics for a test run. | `test_run_id` |
| `list_test_module_runs` | List test module runs for a specific test run. | `test_run_id` |
| `list_test_suite_runs` | List test suite runs for a specific test run, optionally filtered by module. | `test_run_id` |
| `list_test_cases` | List test cases for a project (supports filters like `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Get detailed metrics for a test case including reliability rate, flakiness rate, and run counts. | `test_case_id` or `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | List test case runs, optionally filtered by test case or test run. | `account_handle`, `project_handle` |
| `get_test_case_run` | Get failure details and repetitions for a specific test case run. | `test_case_run_id` |
| `list_test_case_run_attachments` | List attachments for a test case run. Each attachment includes a temporary download URL. | `test_case_run_id` |
| `list_test_case_events` | List state changes for a test case, such as muting or skipping it. | `test_case_id` |
| `update_test_case` | Update a test case's state or flaky classification. | `test_case_id` or `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | List selective-testing target results for a test run. | `test_run_id` |

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
| `integrate_gradle_project` | Guides you through integrating Tuist into an existing Gradle project. Supports remote build cache, build insights, test insights, flaky test detection and quarantine, and test sharding. |
| `integrate_xcode_project` | Guides you through integrating Tuist into an existing Xcode project. Supports Xcode cache, build insights, test insights, and test sharding. |

All prompts accept `account_handle` and `project_handle` to scope the investigation to a specific project. The comparison prompts also accept `base` and `head` arguments to specify the two items to compare (by ID, dashboard URL, or branch name). `integrate_gradle_project` also accepts `features`, a comma-separated list of Gradle integrations to apply: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests`, and `test_sharding`. `integrate_xcode_project` accepts `features` with `xcode_cache`, `build_insights`, `test_insights`, and `test_sharding`.

#### Gradle integration prompt features

The `integrate_gradle_project` prompt documents every Gradle integration that the Tuist Gradle plugin supports:

| Feature | What the agent configures |
|---------|---------------------------|
| `remote_cache` | Enables Gradle's build cache, configures Tuist remote cache upload policy, and recommends CI-only uploads with local read-only usage. |
| `build_insights` | Applies the Tuist Gradle plugin and configures build analytics upload behavior when needed. |
| `test_insights` | Applies the Tuist Gradle plugin so Gradle `Test` task results are uploaded automatically. |
| `flaky_tests` | Guides setup for flaky test detection, optional Gradle Test Retry plugin usage, and test quarantine configuration. |
| `test_sharding` | Adds the CI workflow for `tuistPrepareTestShards`, shard matrix generation, and `TUIST_SHARD_INDEX` based test execution. |

When `features` is omitted, the prompt asks the agent to clarify which integrations the user wants or infer the smallest useful set from the request before editing the Gradle project.

#### Xcode integration prompt features

The `integrate_xcode_project` prompt documents every Xcode integration that Tuist supports:

| Feature | What the agent configures |
|---------|---------------------------|
| `xcode_cache` | Configures `tuist setup cache`, generated-project cache settings, manual Xcode cache build settings, and CI-only cache upload policy. |
| `build_insights` | Configures `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath`, and optional machine metrics through `tuist setup insights`. |
| `test_insights` | Configures `tuist inspect test`, scheme test post-actions, and result bundle generation for CI test runs. |
| `test_sharding` | Adds the Xcode or generated-project shard planning and shard execution workflow with `TUIST_SHARD_INDEX`. |

When `features` is omitted, the prompt asks the agent to clarify which integrations the user wants or infer the smallest useful set from the request before editing the Xcode project.
