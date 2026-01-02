# TuistScaffold (CLI Module)

This module provides scaffolding helpers for creating new projects or files.

## Responsibilities
- Render template manifests using Stencil and user-provided attributes.
- Generate directories and files, respecting `.stencil` templating rules.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- `.stencil` files are rendered; non-stencil files are copied verbatim.
- Empty rendered content is skipped unless the file is `.gitkeep`.
