# ProjectAutomation (CLI Module)

This module provides the serialized output schema used by automation tooling.

## Responsibilities
- Define `Graph`, `Project`, `Target`, `Scheme`, and related types for automation outputs.
- Provide a stable, `Codable` representation of the generated Xcode project graph.

## Boundaries
- This is an output schema, not the manifest DSL (`ProjectDescription`) or generator logic.

## Invariants
- Types are `Codable`/`Equatable` and reflect generated project state (paths, targets, schemes).

## Related Context
- cli/Sources/ProjectDescription/AGENTS.md
- cli/Sources/TuistAutomation/AGENTS.md
- cli/Sources/TuistGenerator/AGENTS.md
