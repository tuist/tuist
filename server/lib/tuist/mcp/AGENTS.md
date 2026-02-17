# Tuist MCP

This directory contains the Tuist MCP implementation:

- JSON-RPC request handling
- MCP tools and prompts
- MCP authorization/serialization helpers

## Prompt/Skill Sync

- Keep `server/lib/tuist/mcp/prompts/fix_flaky_test.ex` prompt text aligned with the canonical `fix-flaky-tests` skill at `~/.agents/skills/fix-flaky-tests/SKILL.md`.
- If the skill workflow changes (steps, heuristics, verification, checklist), update the MCP prompt in the same change.
- If MCP tools or tool payloads change, update the skill or document intentional divergence.

## Documentation Sync

- When MCP server behavior/capabilities change, update `docs/docs/en/guides/features/agentic-coding/mcp.md` in the same PR.

## Versioning

- When MCP client-visible behavior changes (tools, prompts, responses, auth/discovery behavior), bump `serverInfo.version` in `server/lib/tuist/mcp/server.ex` in the same PR.
- Do not bump `protocolVersion` unless the implementation is intentionally updated to a newer MCP specification revision and compatibility has been validated.

## Related Context

- Parent boundary: `server/lib/tuist/AGENTS.md`
