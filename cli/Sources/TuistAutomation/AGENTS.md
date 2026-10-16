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
- Device discovery relies on `xcrun devicectl` JSON output.
- Unit/UI test targets are tagged `tuist:prunable` to enable pruning.
- `XcodeBuildController.run(arguments:)` sets `XCODE_XCCONFIG_FILE` to the `XcodeCachePackagesXCConfig` of the `-workspace` it builds when that file exists. If the variable is already set, it points it at a temporary xcconfig that includes the user's file and then the package one, so the package settings extend the user's through `$(inherited)`. That is how the Xcode cache prefix mappings reach the targets of `Project.packages` in Tuist's own builds.
