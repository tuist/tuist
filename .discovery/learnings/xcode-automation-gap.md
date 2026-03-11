# Xcode automation gap

## What is solved

- The Mac host now has reproducible bootstrap for Nix, Homebrew basics, VLAN setup, and the runner host config.
- `xcodes` is installed on the Mac.
- `xcodes` can see `26.2` as an available version.
- Manual interactive installation on the host succeeded and produced:

  - `/Applications/Xcode-26.2.0.app`

## What is not solved

- Fully unattended Xcode installation is still not reliable.
- The host can authenticate further manually than the noninteractive flow, including 2FA handling.
- The scripted `xcodes` login path still fails for this account with Apple auth decoding issues.

## Important detail from the manual success

The manually installed path is:

- `/Applications/Xcode-26.2.0.app`

This does not match the older assumed path shape:

- `/Applications/Xcode_26.2.app`

## What changed in repo support

`./.github/actions/select-xcode` now supports both naming patterns:

- `Xcode_26.2.app`
- `Xcode-26.2.0.app`

and exports `DEVELOPER_DIR` so self-hosted jobs do not have to rely on `sudo xcode-select`.

## Recommended interpretation

- Xcode installation itself should be treated as a separate artifact-distribution problem, not a core Nix problem.
- Nix should bootstrap the host and the runner runtime.
- Xcode should be either:

  - installed manually during fleet bring-up,
  - distributed as an internal artifact, or
  - handled by a purpose-built Apple-authenticated provisioning lane.
