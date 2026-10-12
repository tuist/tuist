# TuistSupport (Shared Utilities)

This module provides low-level helpers and shared infrastructure used across the CLI.

## Responsibilities
- Logging infrastructure and log handlers (console, detailed, OSLog, JSON).
- Error modeling (`FatalError`) and common system helpers (process, environment, Xcode detection).
- Shared constants and utilities used across CLI modules.
- Caller-owned scratch directory preparation and validation for cache warming.
- Terminal-native command state reporting through `ProgramStatusReporter` (OSC 7501).

## Boundaries
- Keep this module dependency-light; it should not depend on higher-level feature modules.

## Invariants
- Logger configuration honors environment variables (quiet, osLog, detailed, verbose).
- `FatalError` types are used to classify user-facing failures vs. unexpected errors.
- Caller-owned cache-warm scratch directories are created when absent and must be empty when present.
- Program-status reports are disabled by default outside the CLI entry point and suppressed for non-interactive stdout, CI, machine-readable output, and quiet mode. Messages are single-line, control-free UTF-8, base64-encoded, and bounded to the protocol's 2048-byte decoded limit.
- Status output is best-effort: write errors, including a revoked terminal, must not change command results or exit status.
- Handled cancellation reports `idle`. Tuist intentionally does not install signal handlers for status reporting: Ctrl-C retains its existing process-group and termination semantics, and relies on terminal-side cleanup at process exit or the next shell prompt.

## Related Context
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
