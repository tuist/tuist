# TuistAutomation (CLI Module)

This module provides automation workflows and helpers used by CLI commands.

## Responsibilities
- Provide device automation via `devicectl` (install/launch apps, list devices).
- Apply project mappers to enable/disable testing targets for automation workflows.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/ProjectAutomation/AGENTS.md
- cli/Sources/TuistKit/AGENTS.md

## Invariants
- Target execution must use the same DerivedData path as the preceding build for both product lookup and build-settings queries. A nil path preserves Xcode's default location behavior.
- Device discovery relies on `xcrun devicectl` JSON output.
- Unit/UI test targets are tagged `tuist:prunable` to enable pruning.
