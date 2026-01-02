# TuistLaunchctl (CLI Module)

This module provides launchctl integration helpers for macOS automation.

## Responsibilities
- Load/unload LaunchAgents and LaunchDaemons via `launchctl`.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Related Context
- cli/Sources/TuistAutomation/AGENTS.md

## Invariants
- Uses `/bin/launchctl` and waits for command completion.
