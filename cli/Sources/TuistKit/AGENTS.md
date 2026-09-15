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
- `TuistCommand` groups commands into: Get started, Develop, Share, Account, Other.
- `TuistCommand.main` initializes cache directories, loads config, resolves server URL, and runs `TrackableCommand`.
- Noora logging is reinitialized after command execution to ensure logs are captured in verbose logs.
- Cache warm selection is scoped from explicit non-test roots; focused test roots may remain in the graph but do not expand binary cache candidates.
- Cache readiness probes keep their read side open until the daemon responds or closes the connection. Closing immediately after connecting can crash SwiftNIO on Darwin before it accepts the socket.
- When selective testing skips every test, publish a completed empty test run with the selected scheme name, recovering pruned workspace schemes from the initial graph. A build-only sharding run must also publish it when emitting an empty shard matrix, because no test job will follow.

## Related Context
- CLI entry point: `cli/Sources/tuist/AGENTS.md`
- Core domain models: `cli/Sources/TuistCore/AGENTS.md`
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`
- Server integration: `cli/Sources/TuistServer/AGENTS.md`
- When the default generator runs focus without filters (for example, during build), it preserves eligible local package tests and their dependencies for their effective platforms. Ordinary unfocused generation relies on the narrowing and pruning mappers. Test automation saves the graph before focus for platform inference and passes includedProducts for unit/UI tests; a selected scheme keeps its own test roots and does not add package tests outside the scheme.
