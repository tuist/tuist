# TuistDependencies (Dependency Management)

This module manages external dependencies (e.g., Swift packages) used by Tuist projects.

## Responsibilities
- Apply workspace/project mapping for external dependencies (e.g., rewriting paths under `.build/checkouts`).
- Ensure external project settings (like `SRCROOT`) are consistent for generated projects.

## Related Context
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`

## Invariants
- External projects under SwiftPM checkouts are remapped into derived dependencies directories.
- Local packages outside `.build/checkouts` are not remapped.
