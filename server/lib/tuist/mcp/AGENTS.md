# Tuist Model Context Protocol

This directory contains the Tuist [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) implementation:

- JSON-RPC request handling
- MCP tools and prompts
- MCP authorization/serialization helpers

## Prompt/Skill Sync

- Keep `server/lib/tuist/mcp/prompts/fix_flaky_test.ex` prompt text aligned with the canonical `fix-flaky-tests` skill at `~/.agents/skills/fix-flaky-tests/SKILL.md`.
- If the skill workflow changes (steps, heuristics, verification, checklist), update the MCP prompt in the same change.
- If MCP tools or tool payloads change, update the skill or document intentional divergence.
- Keep the Gradle integration workflow in `gradle_integration_guide.ex` shared by the `integrate_gradle_project` prompt and `get_gradle_integration_guide` tool. When its plugin version changes, update `Constants.gradlePluginVersion`, the Gradle plugin source example, and the installation guide in the same change.

## Documentation Sync

- When MCP server behavior or capabilities change, update `server/priv/docs/en/guides/features/agentic-coding/mcp.md` in the same pull request.
- Keep Model Context Protocol authentication guidance aligned with the current WorkOS auth.md discovery and assertion-exchange flow served by `/auth.md`.

## Versioning

- When MCP client-visible behavior changes (tools, prompts, responses, auth/discovery behavior), bump `serverInfo.version` in `server/lib/tuist/mcp/server.ex` in the same PR.
- Do not bump `protocolVersion` unless the implementation is intentionally updated to a newer MCP specification revision and compatibility has been validated.

## Related Context

- Parent boundary: `server/lib/tuist/AGENTS.md`
- Bounded source-code service: `codebase-search/AGENTS.md`
