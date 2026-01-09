# TuistKit (CLI Commands)

This module houses CLI command definitions, command wiring, and high-level orchestration.

## Responsibilities
- Define the root command (`TuistCommand`) and subcommand groups.
- Load config, server URL, and trackable command execution lifecycle.
- Centralize error handling, logging, and Noora integration.

## Boundaries
- Keep orchestration here; domain logic lives in feature modules (e.g., generator, cache, server).
- Avoid direct file system or graph logic that belongs in `TuistCore`, `TuistGenerator`, or `TuistSupport`.

## Invariants
- `TuistCommand` groups commands into: Get started, Develop, Share, AI, Account, Other.
- `TuistCommand.main` initializes cache directories, loads config, resolves server URL, and runs `TrackableCommand`.
- Noora logging is reinitialized after command execution to ensure logs are captured in verbose logs.

## Related Context
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
- Server integration: `cli/Sources/TuistServer/AGENTS.md`
