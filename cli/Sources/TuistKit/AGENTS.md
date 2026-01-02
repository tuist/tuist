# TuistKit (CLI Commands)

This module houses CLI command definitions, command wiring, and high-level orchestration.

## Responsibilities
- Define CLI commands and options.
- Connect commands to services in lower-level modules.

## Boundaries
- Keep command orchestration here; avoid pushing domain logic upward from `TuistCore` or `TuistSupport`.
- Heavy domain logic should live in `TuistCore` or feature modules.

## Related Context
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
- Server integration: `cli/Sources/TuistServer/AGENTS.md`
