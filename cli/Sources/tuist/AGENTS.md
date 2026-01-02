# CLI Entry Point (tuist)

This module defines the CLI entry point for the `tuist` binary.

## Responsibilities
- Boot the CLI runtime by calling `initDependencies` and delegating to `TuistCommand.main`.
- Provide the `@main` entry that wires the binary to `TuistKit` command execution.

## Invariants
- Entrypoint should remain thin: no command logic or option parsing here.
- Logging and error presentation remain centralized in `TuistKit`.

## Related Context
- Command definitions and wiring: `cli/Sources/TuistKit/AGENTS.md`
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
