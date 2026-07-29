# TuistSupport (Shared Utilities)

This module provides low-level helpers and shared infrastructure used across the CLI.

## Responsibilities
- Logging infrastructure and log handlers (console, detailed, OSLog, JSON).
- Error modeling (`FatalError`) and common system helpers (process, environment, Xcode detection).
- Shared constants and utilities used across CLI modules.
- Caller-owned scratch directory preparation and validation for cache warming.

## Boundaries
- Keep this module dependency-light; it should not depend on higher-level feature modules.

## Invariants
- Logger configuration honors environment variables (quiet, osLog, detailed, verbose).
- `FatalError` types are used to classify user-facing failures vs. unexpected errors.
- Caller-owned cache-warm scratch directories are created when absent and must be empty when present.

## Related Context
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
