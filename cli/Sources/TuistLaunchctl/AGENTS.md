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
- Select the GUI domain when it exists, otherwise the background user domain, based on launchd availability rather than CI environment variables.
- The plist's `LimitLoadToSessionType` must match the selected domain (`Aqua` for GUI, `Background` for user). Background agents must not also autoload into a later GUI login.
- Look up existing agents in both domains for status, restart, and teardown; a desktop login may have appeared since setup. Preserve unexpected launchctl failures rather than treating them as missing jobs or domains.
- `isLaunchAgentCurrent` is true only when the installed plist equals, as a property list, the one `setupLaunchAgent` would write, launchd holds a process for the label, and that process started after the plist, the program binary and every launch input last changed (`st_ctime`, which an installer cannot backdate). Anything it cannot read counts as not current, so a caller that skips the reinstall on `true` only skips one that would have replaced the process and nothing else.
