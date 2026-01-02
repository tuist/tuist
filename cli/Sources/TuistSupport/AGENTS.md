# TuistSupport (Shared Utilities)

This module provides low-level helpers and shared infrastructure used across the CLI.

## Responsibilities
- Common utilities (logging, file system helpers, process execution).
- Small cross-cutting helpers used by multiple modules.

## Boundaries
- Keep this module dependency-light; it should not depend on higher-level feature modules.

## Related Context
- Core domain abstractions: `cli/Sources/TuistCore/AGENTS.md`
