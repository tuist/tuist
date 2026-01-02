# TuistProcess (CLI Module)

This module provides process execution helpers and process lifecycle utilities.

## Responsibilities
- Run background processes with controlled environment and silent output.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Invariants
- Background processes are detached with stdout/stderr to null device.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md
