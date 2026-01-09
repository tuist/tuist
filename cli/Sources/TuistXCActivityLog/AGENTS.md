# TuistXCActivityLog (CLI Module)

This module provides XCActivityLog parsing helpers, especially for CAS output analysis.

## Responsibilities
- Model CAS outputs and their types (swift artifacts, diagnostics, dependency scans).
- Track CAS operations (upload/download) with size and duration metadata.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistGenerator/AGENTS.md

## Invariants
- CAS output types map to compiler artifact identifiers (e.g., `swiftdoc`, `swiftinterface`).
