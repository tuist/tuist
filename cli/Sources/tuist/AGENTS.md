# CLI Entry Point (tuist)

This module defines the CLI entry point for the `tuist` binary.

## Responsibilities
- Boot the CLI runtime by calling `initDependencies` and delegating to `TuistCommand.main`.
- Provide the `@main` entry that wires the binary to `TuistKit` command execution.
- Scope OSC 7501 program-status reporting around the entire CLI lifecycle, including dependency initialization. Explicit exit paths in `TuistCommand` must report the final status before exiting.
- Route SwifterPM's redacted warnings through `AlertController` with `SwifterPM.withWarningHandler`. Keychain reads run in-process to preserve Tuist item trust; headless reads serialize and temporarily disable legacy approval, restoring the previous process-wide interaction setting afterwards.
- Bind `Constants.version` to `releaseVersion` (`ReleaseVersion.swift`), which the release pipeline stamps. Keeping the stamp in this leaf target means a new version only recompiles the entry point, not every module that imports `TuistConstants`.

## Invariants
- Entrypoint should remain thin: delegate command-specific parsing and execution to the feature module.
- Cargo delegates to `TuistCargoCommand` before generic flag stripping, configuration loading, command analytics, or authentication. Runtime initialization must interpret only Tuist flags before `cargo`, never Cargo or test-harness flags. Compiler hooks must not publish command events.
- Logging and error presentation remain centralized in `TuistKit` for ordinary commands. Cargo forwards subprocess output and preserves its exit status through ArgumentParser without the generic completion output.
- Dependency initialization binds a fresh `Environment.current` after processing global flags, even if startup code already read the default environment.

## Related Context
- Cargo decoration and nextest integration: `cli/Sources/TuistCargoCommand/AGENTS.md`
- Command definitions and wiring: `cli/Sources/TuistKit/AGENTS.md`
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
- Shared utilities: `cli/Sources/TuistSupport/AGENTS.md`
