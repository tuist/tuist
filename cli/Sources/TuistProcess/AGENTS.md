# TuistProcess (CLI Module)

This module provides process execution helpers and process lifecycle utilities.

## Responsibilities
- Run background processes with controlled environment and silent output.

## Boundaries
- Keep CLI command wiring in `cli/Sources/TuistKit`.
- Keep shared low-level utilities in `cli/Sources/TuistSupport`.

## Invariants
- Background processes are detached with stdout/stderr to null device.
- `CommandRunner.runInOwnProcessGroup` spawns the command as the leader of a new process group. On cancellation it sends SIGTERM to the group (Git removes its lock files on it), then SIGKILL after the grace period, which also ends a child that ignores SIGTERM or is stopped. swift-subprocess's own teardown signals only the leader. The SIGKILL is sent from inside the `Subprocess.run` body, before the leader is reaped, so the group id cannot have been reused. It is opt-in: the group is not the terminal's foreground group, so Ctrl-C (tuist installs no SIGINT handler) no longer reaches the command, and the default `CommandRunning` implementation (mocks) forwards to `run`.
- Subprocess output is read with blocking reads on a dedicated thread (`FileHandle.byteStream()`), never through `readabilityHandler`: on Linux its readability source can miss the end of file after a short-lived child writes and exits, leaving `CommandRunner` waiting forever. Create both byte streams synchronously before spawning, not inside output-consumption tasks: the child must be able to drain both pipes even when Swift's cooperative pool cannot schedule those tasks (Command PR #313).

## Tests
- Unit tests live in `cli/Tests/TuistProcessTests` and run on macOS (Xcode) and Linux (`swift test`).
- `drainsBothPipesWithoutSchedulingOutputConsumptionTasks` deterministically holds the post-spawn worker before consumer tasks are created and verifies that a child finishes writing 1 MiB to each pipe during that hold, with all bytes subsequently delivered.

## Related Context
- cli/Sources/TuistSupport/AGENTS.md

## Integration coverage

- `cli/Tests/Fixtures/ProcessSchemeIntegration/test.sh` builds the `TuistProcessSchemeIntegration` scheme and verifies that its post-action can run a command and launch a background worker that runs another command after its parent exits. Generate that target first with `tuist generate TuistProcessSchemeIntegration --no-open`.
- The probe imports the production process runners. Its completion files are required because Xcode does not propagate post-action failures through the build exit status.
