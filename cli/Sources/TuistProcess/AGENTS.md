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

## Integration coverage

- `cli/Tests/Fixtures/ProcessSchemeIntegration/test.sh` builds the `TuistProcessSchemeIntegration` scheme and verifies that its post-action can run a command and launch a background worker that runs another command after its parent exits. Generate that target first with `tuist generate TuistProcessSchemeIntegration --no-open`.
- The probe imports the production process runners. Its completion files are required because Xcode does not propagate post-action failures through the build exit status.
