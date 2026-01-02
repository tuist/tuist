# TuistSupport (Shared Utilities)

This module provides low-level helpers and shared infrastructure used across the CLI.

## Responsibilities
- Logging infrastructure and log handlers (console, detailed, OSLog, JSON).
- Error modeling (`FatalError`) and common system helpers (process, environment, Xcode detection).
- Shared constants and utilities used across CLI modules.

## Boundaries
- Keep this module dependency-light; it should not depend on higher-level feature modules.

## Invariants
- Logger configuration honors environment variables (quiet, osLog, detailed, verbose).
- `FatalError` types are used to classify user-facing failures vs. unexpected errors.

## Related Context
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
