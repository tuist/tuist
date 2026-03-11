# Xcode bootstrap and runner service notes

## Key finding: there are two viable Xcode strategies

### Strategy 1: preserve current workflow behavior

- Install the exact version required by `.xcode-version` under `/Applications/Xcode_26.2.app`.
- Keep `sudo xcode-select -switch /Applications/Xcode_$(cat .xcode-version).app` in workflows.

This minimizes workflow changes, but it keeps a privileged mutable step in CI.

### Strategy 2: move self-hosted runners to `DEVELOPER_DIR`

- Install Xcode under a user-owned path.
- Export `DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer` for runner jobs.
- Remove or branch around `sudo xcode-select` for self-hosted labels.

This is the cleaner long-term model for a reproducible self-hosted fleet.

## Evidence from `xcodes`

From experiments on the host:

- `xcodes` runs fine from a downloaded release binary; Homebrew is not strictly required.
- `xcodes installed` reports the currently installed Xcode.
- `xcodes list` shows `26.2 (17C52)` is available.
- `xcodes runtimes` shows `iOS 26.2` runtimes are available.
- `xcodes install --help` exposes:

  - `--directory <directory>`
  - `--experimental-unxip`
  - `--no-superuser`
  - `--use-fastlane-auth`

This combination strongly suggests a user-space installation path is feasible if workflow logic moves to `DEVELOPER_DIR`.

## Credentials required for Xcode automation

- `xcodes` needs Apple authentication.
- It supports:

  - interactive Apple ID login
  - `XCODES_USERNAME` / `XCODES_PASSWORD`
  - `--use-fastlane-auth`

Implication:

- reproducible Xcode install still needs an external credential source
- this should be treated like any other runner secret

## Runner service detail that likely matters for simulators

The official GitHub runner macOS launchd template includes:

- `ProcessType = Interactive`
- `SessionCreate = true`

The upstream `nix-darwin` `services.github-runners` module already sets:

- `ProcessType = "Interactive"`

but does not mirror `SessionCreate = true` by default.

### Why this matters

- UI-adjacent Apple tooling often behaves differently depending on launch context.
- Simulator and Xcode-heavy jobs are exactly the kind of jobs where session semantics can matter.

### Recommendation

- Add `SessionCreate = true` through `serviceOverrides` for the runner.
- Validate simulator creation, boot, and test execution under that service before scaling the design.

## Runner user choice

The default `nix-darwin` behavior uses `_github-runner` unless overridden.

That may be acceptable for:

- CLI-only jobs
- simple build jobs

It is less obviously correct for:

- simulator-heavy tests
- Xcode defaults writes
- any workflow that expects a more normal user home layout

### Recommendation

- For Tuist's mac runner, prefer an explicit dedicated runner user with a stable home directory.
- Keep the work directory and the user's home predictable so caches, simulators, and defaults are easier to reason about.
