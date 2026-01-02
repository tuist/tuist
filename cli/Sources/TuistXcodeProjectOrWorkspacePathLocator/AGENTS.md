# TuistXcodeProjectOrWorkspacePathLocator (CLI Module)

This module provides helpers for resolving Xcode project/workspace paths.

## Responsibilities
- Implement helpers for resolving Xcode project/workspace paths.
- Keep the module cohesive around its named concern

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md
- cli/Sources/TuistLoader/AGENTS.md
