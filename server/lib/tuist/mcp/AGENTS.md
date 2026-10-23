# Tuist Model Context Protocol

This directory contains the Tuist [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) implementation:

- JSON-RPC request handling. Reuse EMCP's dispatcher and schema validation; its pinned HTTP transport and current upstream still require sessions, so automatic recreation is not a session-free mode. Both paths default origin checks to `app_url(route_type: :app)`, including self-hosted installs. Legacy absent/null arguments retain EMCP's empty-map behavior; other non-object arguments are rejected.
- The transport routes `2026-07-28` requests to `Transport.Stateless` and handles older clients without allocating sessions. The modern route has no session identifier and adds result discriminators, cache hints, and server identity to existing tool and prompt responses. Keep both paths tested when changing protocol handling.
- Event subscriptions, callback verification, and delivery live under `events/`; see `events/AGENTS.md`.
- MCP tools and prompts
- `get_test_run` passes the loaded, authorized run into metrics so contract selection does not issue a redundant parent lookup. The tool input/output and authorization boundary remain unchanged.
- MCP authorization/serialization helpers. ID-only Gradle/Xcode lookups must resolve a UUID to exactly one project before authorizing the parent. Reject cross-project collisions, including historical duplicates, instead of selecting an attacker-controlled public parent; project-scoped API/dashboard reads keep their existing behavior.
- `Tools.BuildEntityTool` backs three parameterized tools, `list_build_entities`, `get_build_entity` and `list_build_entity_history`, selected by a `kind` enum (`gradle_tasks`, `xcode_modules`, `once_actions`, `mix_files`, `mix_modules`, `bazel_actions`) over the REST resource descriptors and `Tuist.BuildEntities.Params`. Add a kind to the enum rather than a new tool per toolchain; cache-action kinds remain outside these persistent tools; existing native cache tools and routes are unchanged. A kind whose toolchain differs from the project's returns a tool error. After project authorization and before any query, `Tuist.FeatureFlags.build_entities_enabled?/1` must allow the project (per-project `:build_entities`, overridden by the global `:build_entities_kill_switch`); otherwise return the not-available error. Tests opt each project in with `FunWithFlags.enable(:build_entities, for_actor: project)`; never toggle the global kill switch in tests, because flag state is shared across async test modules. Authorize project build-read before querying; IDs are project/toolchain/kind scoped and independent of runs. Detail includes period analytics, history uses bounded opaque cursors, and unknown observations stay unavailable. Public inventory responses retain metadata and observation counts (`include_metrics: false`); dashboard-only percentile fields must not escape the closed MCP entity schema. Bazel action identity uses target label, mnemonic and configured output, with BEP-reported executions rather than cache traffic. Xcode module history includes native-build compilations and command cache events, with cache resolutions excluded from timing. Keep existing run-level tools and input contracts unchanged. Detail metrics include optional `duration_samples`, counting measured durations rather than executions; exclude null timing, include genuine zeros, and keep the schema compatible with earlier responses.
- Operator reads: for calls proxied by Atlas (`x-tuist-atlas-identity`, verified by `TuistWeb.OperatorGrant.accept_atlas_identity_header/2`), `Tuist.MCP.Authorization.authorize_request/4` falls back to a grant-free read for the resource's account. It goes through the `:ops_access` policies and never applies to writes. There is no MCP operator-grant header; grants from ops.tuist.dev only apply to the browser session.
- Xcode build-step list/detail tools share `Tuist.Builds.Steps` with the HTTP API. Lists omit logs, IDs are decimal strings scoped to a build, and details expose bounded logs separately after build-read authorization. The `compare_builds` prompt includes these tools; the flaky-test and integration skills intentionally do not use build-step data.

## Prompt/Skill Sync

- Keep `server/lib/tuist/mcp/prompts/fix_flaky_test.ex` prompt text aligned with the canonical `fix-flaky-tests` skill at `~/.agents/skills/fix-flaky-tests/SKILL.md`.
- If the skill workflow changes (steps, heuristics, verification, checklist), update the MCP prompt in the same change.
- If MCP tools or tool payloads change, update the skill or document intentional divergence.
- Keep the Gradle integration workflow in `gradle_integration_guide.ex` shared by the `integrate_gradle_project` prompt and `get_gradle_integration_guide` tool. When its plugin version changes, update `Constants.gradlePluginVersion`, the Gradle plugin source example, and the installation guide in the same change.
- Keep the Bazel integration workflow in `bazel_integration_guide.ex` shared by the `integrate_bazel_project` prompt and `get_bazel_integration_guide` tool. Keep its command and diagnostic-tool names aligned with the command-line implementation and the registered Model Context Protocol tools.

## Documentation Sync

- Build-detail tools expose the same string-valued `custom_metadata: {tags, values}` concept across Xcode, Gradle, Bazel, Mix and Cargo. Preserve arbitrary keys and align Cargo's strict output schemas with shared query serialization. Reported infrastructure is untrusted and missing observations are not backfilled. Once requires an external protocol update. See `server/docs/build-metadata.md`.

- When MCP server behavior or capabilities change, update `server/priv/docs/en/guides/features/agentic-coding/mcp.md` in the same pull request.
- Server initialization and server-card instructions describe OAuth 2.0 with dynamic client registration and the standard browser authorization flow inline. Keep this block factual: describe tool capabilities, revision-pinned links, result limits, and authentication boundaries without directing answer style, citations, tool selection, or verification workflows. Tool-specific setup and authentication checks belong in integration guides and prompts. Do not direct clients to fetch or follow external authentication documents from this instructions block.
- The separate `auth_md` field in unauthorized responses and `agent_auth.skill` authorization-server metadata continue to expose the WorkOS auth.md flow served by `/auth.md`; keep documentation for those capabilities aligned with their implementation.

## Versioning

- When MCP client-visible behavior changes (tools, prompts, responses, auth/discovery behavior), bump `serverInfo.version` in `server/lib/tuist/mcp/server.ex` in the same PR. After integrating newer changes from `main`, keep this version newer than `main` and synchronize the server and server-card version assertions.
- Do not bump `protocolVersion` unless the implementation is intentionally updated to a newer MCP specification revision and compatibility has been validated.

## Related Context

- Parent boundary: `server/lib/tuist/AGENTS.md`
- Bounded source-code service: `codebase-search/AGENTS.md`

- Gradle/Bazel step list/detail tools share `Builds.RecordedSteps` with their APIs. They enforce build-read access, preserve opaque IDs, and expose coverage and timestamp-origin metadata; Bazel action logs are fetched separately for details while Gradle logs remain unavailable.

- `Tools.BuildStep` owns shared step input/output schemas. Bazel keeps the same account/project/invocation addressing and project authorization as other Bazel tools because invocation IDs are caller-supplied and project-scoped. Gradle/Xcode retain their Tuist build UUID/dashboard-URL addressing. Do not add an unscoped Bazel invocation lookup merely to match those signatures.

- The Bazel comparison prompt honors step-list coverage: trace profiles contain all recorded intervals; retained summaries have at most 32 actions plus setup. Recommend step detail tools for published action outcomes/logs and invocation logs for broader output; unknown or absent diagnostics never imply success.

- Numeric retained Bazel IDs stay readable across profile publication; missing indexed rows report unavailable rather than an empty available timeline. Gradle step tools include zero-duration cache and skip outcomes.

- Runner-volume tools share `Runners.CacheVolumes.Query` with the public API and
  derive schemas from `Runners.CacheVolumes.Schemas`. Reads require runners-read;
  clearing requires account-update and carries destructive annotations. Keep
  account scoping, unknown values and the runners feature gate intact.

- Cargo build, Mix build and Once run tools share `Cargo.Query`, `Mix.Query` and
  `OnceEvents.Query` with their REST endpoints, so both return the same shapes.
  Their IDs are client-chosen and project-scoped: the get tools take
  `account_handle`, `project_handle` and the ID and authorize project build-read.
  Never add an ID-only lookup for them.
- `connect_project_repository` and `disconnect_project_repository` share
  `VCS.connect_github_repository/3`, `VCS.disconnect_github_repository/1`
  and `VCS.connect_github_repository_error/2` with the REST endpoint. They
  authorize project `:update`, and linking only accepts repositories in the
  account's GitHub App installation list, never a repository an installation
  token merely can read.
- Code coverage tools (`get_coverage`, `list_coverage_files`,
  `get_coverage_file`) share `Tests.Coverage.Query` with the public API and
  derive their output schemas from `Tests.Coverage.Schemas` through
  `Tool.json_schema/1`. They require test-read, then
  `FeatureFlags.xcode_coverage_enabled?/1` for the project's account.

- Organization invitation tools reuse `Accounts.invite_user_to_organization/3`
  and the `:invitation` policies, matching the dashboard and REST API. They
  never return invitation tokens or links; `email_sent` tells the agent when
  the link has to be copied from the dashboard instead.

- The endpoint implements the stateless 2026-07-28 transport and `server/discover`. Every modern request validates protocol metadata and mirrored headers. Legacy 2025-06-18 and 2025-03-26 clients remain supported without allocating sessions. Catalogs do not advertise change subscriptions.
