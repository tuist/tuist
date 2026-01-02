# CLI Entry Point (tuist)

This module defines the CLI entry point and command dispatch for the `tuist` binary.

## Responsibilities
- Parse CLI arguments and route to the appropriate command implementation.
- Configure process-wide defaults (logging, analytics wiring, environment).

## Related Context
- Command definitions and wiring: `cli/Sources/TuistKit/AGENTS.md`
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
