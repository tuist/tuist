# TuistDependencies (Dependency Management)

This module manages external dependencies (e.g., Swift packages) used by Tuist projects.

## Responsibilities
- Apply workspace/project mapping for external dependencies (e.g., rewriting paths under SwiftPM scratch-directory checkouts).
- Ensure external project settings (like `SRCROOT`) are consistent for generated projects.

## Related Context
- Project generation: `cli/Sources/TuistGenerator/AGENTS.md`

## Invariants
- External projects under SwiftPM scratch-directory checkouts are remapped into derived dependencies directories.
- Local packages outside SwiftPM scratch-directory checkouts are not remapped.
- Only local package tests with destinations inferred from production consumers extend the external dependency graph. Preserve their dependency closure across package boundaries for those effective platforms; prune tests with no inferred destinations and their otherwise unused dependencies. Narrowing and pruning share this eligibility calculation.
