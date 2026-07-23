---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Give AI agents access to test insights and more via Tuist's MCP endpoint."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) is an open standard that lets artificial intelligence agents interact with external services and data sources.
It makes applications such as [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/), and editors like [Zed](https://zed.dev), [Cursor](https://www.cursor.com), or [Visual Studio Code](https://code.visualstudio.com) interoperable with Tuist.

Tuist hosts a server-side Model Context Protocol endpoint at `https://tuist.dev/mcp`. By connecting your client to it, agents can access your Tuist project data, including test insights, flaky test analysis, and more.
Most tools are read-only and scoped to authenticated Tuist project data. Account setup tools can list accounts, create organizations, create projects, and add existing users to organizations when the authenticated user has the required permissions.
The account setup tools require user authentication. They are not available to project tokens or ordinary account tokens. After a user claims an `auth.md` registration, Tuist associates that credential with the confirming user only on the Model Context Protocol endpoint so the setup tools can complete the requested workflow.

## Model Context Protocol versus skills

Model Context Protocol tools and <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> can overlap in what they do. Given the current overlap between the two, choose one approach per workflow and use it consistently instead of mixing both in the same flow.

## Configuration

Add `https://tuist.dev/mcp` as a remote Model Context Protocol server in your client. Tuist advertises both [Open Authorization](https://oauth.net/2/) discovery metadata and the current [auth.md protocol](https://workos.com/auth-md) at `https://tuist.dev/auth.md`.

Clients that already support remote browser authentication can continue authenticating in the browser. Clients and agents that support `auth.md` can register anonymously, present a trusted provider identity assertion, or start a service-authenticated email claim. Registration returns a Tuist-signed identity assertion, which the agent exchanges at the standard token endpoint for a one-hour access token. Tuist publishes its public signing key and supports standard token revocation and provider security-event delivery.

An unauthenticated agent should read the `WWW-Authenticate` header returned by the Model Context Protocol endpoint, fetch the protected-resource metadata, fetch the authorization-server metadata, and follow its `agent_auth.skill` URL. Tuist also returns the same local `auth_md` URL in the unauthorized response body so language-model-driven clients can discover the flow without relying on a native client integration. The deployment-local document is the source of truth for endpoint names, request bodies, claim polling, and assertion exchange.

Before an agent starts an email claim, it must ask the user to confirm the email address for their Tuist account. It must not infer that address from a provider profile, Git configuration, environment variable, or session metadata.

The endpoint uses the `mcp` scope group. An anonymous pre-claim credential can discover capabilities and read public integration guidance, but it is not treated as a signed-in user. After claim, the credential is user-scoped and each tool applies its normal authorization checks. See the <.localized_link href="/guides/server/authentication#scope-groups">scope groups documentation</.localized_link> for details.

<details>
<summary>Claude Code</summary>

Run:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

When a headless Claude Code client does not expose a failed native server connection to the model, require the agent to inspect the configured endpoint's unauthenticated [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) response before searching hosted documentation or editing the project. The response points the model to the deployment-local `auth.md` document even when browser authentication is unavailable.

</details>


<details>
<summary>Codex</summary>

Run:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Complete the browser login before starting a new `codex exec` run. Codex reads the Tuist server instructions during initialization, so Gradle optimization requests automatically receive the authentication and verification workflow.

</details>


<details>
<summary>Claude Desktop</summary>

Open **Settings → Connectors → Add custom connector**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

Complete [Open Authorization](https://oauth.net/2/) in the browser when prompted.

</details>


<details>
<summary>Pi</summary>

Pi does not include a Model Context Protocol client. You can install the third-party [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) extension after reviewing its source and security implications:

```bash
pi install npm:pi-mcp-adapter
```

Add a project-level `.mcp.json` file:

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

Setting `auth` to `false` prevents the adapter's browser authentication handler from hiding Tuist's unauthorized response. A headless agent can then read the returned `auth_md` URL and follow Tuist's registration, identity-assertion exchange, and claim-polling flow. Configure the exchanged access token as a bearer token or let the agent make authenticated Model Context Protocol calls directly.

If you prefer browser authentication, set `auth` to `"oauth"`. For that flow, keep one process alive with Pi's [remote procedure call mode](https://pi.dev/docs/latest/rpc) while authentication completes:

```bash
pi --mode rpc
```

Do not split a pending browser authentication across separate `pi --print` invocations because the process that owns the callback state has exited.

</details>


<details>
<summary>OpenCode</summary>

Add the Tuist Model Context Protocol server to `opencode.json`:

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

Open **Cursor Settings → Tools & Integrations → Model Context Protocol Tools** and add:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

Use **Command Palette → MCP: Add Server**, then configure a [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) server with:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

Open **Agent panel → Settings → Add Custom Server**, then set:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

If your agent supports `auth.md`, it can start anonymously without opening a browser. A trusted provider identity can also complete without a browser when the provider identity is already linked. For service-authenticated email, anonymous claiming, or a first provider link, the agent shows you a Tuist verification link and six-digit code. Open the link, sign in, and enter the agent's code on the Tuist page. Never send the code back to the agent. Tuist's authorization-server metadata points directly to the deployment's own `/auth.md`, which contains the exact request and polling shapes.

## Gradle authentication uses two credentials

The credential used for Model Context Protocol tools does not authenticate the Gradle plugin. Before an agent edits or verifies a Gradle integration, it should run:

```bash
tuist auth whoami --url https://tuist.dev
```

If that command is not authenticated, the agent must stop and ask the user to run:

```bash
tuist auth login --url https://tuist.dev
```

For a local or self-hosted deployment, replace the URL in both commands and in `tuist.toml`. Keep the hostname spelling identical everywhere. For example, `localhost` and `127.0.0.1` use separate stored credentials.


## Capabilities

### Tools

The following tools are available through the Tuist Model Context Protocol server:

Every tool publishes a human-readable description together with explicit input and output schemas. Successful calls return structured content that conforms to the advertised output schema, plus the same result serialized as text for clients that do not yet consume structured content.

#### Documentation and community search

This read-only tool searches Tuist's documentation, [application programming interface](https://en.wikipedia.org/wiki/API) reference, GitHub releases, community forum, and GitHub issues through the same search engine that powers the docs website. Release results include the product, version, publication date, and prerelease status. Stable releases are searched by default, and prereleases can be included with `include_prereleases`. The tool is only available on the Tuist-hosted server at `https://tuist.dev/mcp`.

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `search_tuist` | Start answering Tuist questions from public documentation, the application programming interface reference, GitHub releases, community discussions, and GitHub issues. Optionally restrict to one `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Source-backed answers

These read-only tools let agents use the exact public Tuist source revision deployed alongside the hosted server as the source of truth for answers that depend on current behavior. They are only available at `https://tuist.dev/mcp`.

Compatible clients receive server instructions during initialization that route ordinary Tuist questions through documentation and source-backed tools before local files or general web search. This means users can ask a question directly without invoking the `ask_tuist` prompt first. The prompt remains available when users want to start the same workflow explicitly.

Every operation has fixed limits for concurrency, duration, traversal, bytes read, and response size. Search and listing results include `truncated` and `truncation_reason` fields. When a result is truncated, narrow the path, file pattern, or search term instead of treating the result as exhaustive.

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `search_tuist_code` | Answer questions about current behavior, defaults, configuration, feature gates, error handling, or undocumented details by searching source files. Results include surrounding lines, revision-pinned source links, and scan statistics. | `pattern` |
| `list_tuist_files` | Discover a source subsystem or nearby tests when the relevant path is unknown. Listings have bounded depth and result counts. | None |
| `read_tuist_file` | Inspect a focused line range in an implementation file, call site, or test after finding the relevant path. Truncated responses provide `next_start_line` for continuation. | `path` |

#### Projects

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `list_accounts` | List personal and organization account handles available to the authenticated user, including whether each account can create projects. | None |
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
| `list_xcode_build_cas_outputs` | List [content-addressable storage](https://en.wikipedia.org/wiki/Content-addressable_storage) outputs for a specific Xcode build run. | `build_run_id` |

#### Gradle builds

| Tool | Description | Required parameters |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Return the complete authentication, project setup, Gradle plugin, cache policy, and two-build verification workflow. Agents should call it before editing an existing Android or Gradle project. | None |
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
| `integrate_gradle_project` | Guides you through integrating Tuist into an existing Gradle project. It includes separate tool and Gradle authentication, account discovery, project creation, remote cache policy, build insights, and read-back verification. |
| `integrate_xcode_project` | Guides you through integrating Tuist into an existing Xcode project. Supports Xcode cache, build insights, test insights, and test sharding. |
| `ask_tuist` | Answers a Tuist question using public material for context and focused implementation and test evidence as the source of truth for current behavior. It requires a `question` and cites revision-pinned evidence. |

Project-data prompts accept `account_handle` and `project_handle` to scope the investigation to a specific project. The comparison prompts also accept `base` and `head` arguments to specify the two items to compare (by ID, dashboard URL, or branch name). `ask_tuist` accepts a `question` instead of project parameters. `integrate_gradle_project` also accepts `features`, a comma-separated list of Gradle integrations to apply: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests`, and `test_sharding`. `integrate_xcode_project` accepts `features` with `xcode_cache`, `build_insights`, `test_insights`, and `test_sharding`.

#### Gradle integration prompt features

The `integrate_gradle_project` prompt and `get_gradle_integration_guide` tool document the complete setup workflow. The tool is also referenced by the server's initialization instructions, which makes it discoverable by agents that do not enumerate prompts.

| Feature | What the agent configures |
|---------|---------------------------|
| `remote_cache` | Enables Gradle's build cache, configures Tuist remote cache upload policy, and recommends uploads only from continuous integration runners with local read-only usage. |
| `build_insights` | Applies the Tuist Gradle plugin and configures build analytics upload behavior when needed. |
| `test_insights` | Applies the Tuist Gradle plugin so Gradle `Test` task results are uploaded automatically. |
| `flaky_tests` | Guides setup for flaky test detection, optional Gradle Test Retry plugin usage, and test quarantine configuration. |
| `test_sharding` | Adds the continuous integration workflow for `tuistPrepareTestShards`, shard matrix generation, and `TUIST_SHARD_INDEX` based test execution. |

When `features` is omitted, the prompt asks the agent to clarify which integrations the user wants or infer the smallest useful set from the request before editing the Gradle project.

#### Xcode integration prompt features

The `integrate_xcode_project` prompt documents every Xcode integration that Tuist supports:

| Feature | What the agent configures |
|---------|---------------------------|
| `xcode_cache` | Configures `tuist setup cache`, generated-project cache settings, manual Xcode cache build settings, and an upload policy limited to continuous integration runners. |
| `build_insights` | Configures `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath`, and optional machine metrics through `tuist setup insights`. |
| `test_insights` | Configures `tuist inspect test`, scheme test post-actions, and result bundle generation for continuous integration test runs. |
| `test_sharding` | Adds the Xcode or generated-project shard planning and shard execution workflow with `TUIST_SHARD_INDEX`. |

When `features` is omitted, the prompt asks the agent to clarify which integrations the user wants or infer the smallest useful set from the request before editing the Xcode project.
