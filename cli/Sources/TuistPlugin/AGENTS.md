# TuistPlugin (CLI Module)

This module provides plugin system support and plugin execution helpers.

## Responsibilities
- Load local and remote plugins from config.
- Fetch remote plugins via git or release artifacts, cache them, and build helper plugins.
- Expose template paths and resource synthesizers contributed by plugins.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- Remote plugins must be fetched before loading; missing cached plugins produce a `FatalError`.
- Git tags may use release artifacts; SHA refs use the repository path only.
