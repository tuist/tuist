# TuistSimulator (CLI Module)

This module provides simulator-related helpers used by CLI workflows.

## Responsibilities
- Model destination types (simulator vs device) and derive build product paths.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- Simulator/device destination paths use platform-specific SDK suffixes.
