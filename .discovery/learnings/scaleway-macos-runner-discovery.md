# Scaleway macOS runner discovery

## Current state

- The cache side already has a NixOS bootstrap path in `cache/platform/flake.nix`.
- The test cache host is `tuist-01-test-cache.par.runners.tuist.dev` and the live machine has private address `172.16.16.4/22` on `ens6`.
- The Mac host at `51.159.120.232` is reachable over SSH as `m1` and is a Scaleway Apple Silicon machine.

## What the Mac host actually looks like

- macOS `26.0`
- Xcode `26.0`
- Apple M1, 8 CPU cores, 8 GB RAM, 228 GiB disk
- Rosetta is installed
- Nix is now installed through Determinate Nix Installer
- no Homebrew
- no GitHub Actions runner installed
- the Private Network VLAN is now configured locally as `vlan0`

## Important mismatches with current workflows

- `.xcode-version` is `26.2`, but the host only has `Xcode.app` version `26.0`.
- Existing macOS workflows call:

  - `sudo xcode-select -switch /Applications/Xcode_$(cat .xcode-version).app`

- On this host, `sudo -n true` fails, so a workflow cannot rely on passwordless sudo.
- Result: current self-hosted migration will fail unless the host bootstrap makes the job not need sudo, or the workflows change.

## Cache connectivity finding

- The cache node is alive publicly at `https://tuist-01-test-cache.par.runners.tuist.dev/up`.
- The Mac required a local VLAN interface before Private Network traffic worked.
- The VLAN tag for this Private Network is `1597`.
- After `sudo networksetup -createVLAN pn en0 1597`, the Mac received `172.16.16.3/22` on `vlan0`.
- Once `vlan0` had DHCP, routing to `172.16.16.4` correctly moved to `vlan0`.
- A second problem then surfaced: the cache node itself was missing the connected `172.16.16.0/22` route because `ens6` was configured with `noprefixroute`.
- After adding and then deploying a declarative cache-node route, private connectivity worked end-to-end.

## Bootstrap progress so far

- The cache-node route fix is now committed in Nix config and deployed to the test cache host.
- An initial `/runners` flake now exists in the repo.
- The flake evaluates locally and on the Mac.
- The first source-build runner packaging path failed in a local Node.js build with a segmentation fault.
- The runner package was then replaced with a binary-wrapper package based on the official GitHub runner tarball.
- With that package, the `/runners` flake now builds end-to-end on the live Mac.
- Host-side secrets management for `xcodes` is now active through `sops-nix`.
- `xcodes` still fails to authenticate this Apple account even with the normal Apple ID password managed correctly through secrets.
- The observed failure is a missing `salt` field during Apple auth decoding, which matches an upstream `xcodes` issue tied to Apple's SRP login state for older passwords.
- The next blockers are a workable Xcode distribution/auth path, dynamic runner registration from `server/`, and actual per-run isolation.

Implication:

- the bootstrap shape is now concrete
- the remaining work is in package/build reliability, secrets, Xcode automation, and actual runner registration

## What Nix can own on the Mac

Nix is a strong fit for:

- runner service definition
- CLI/tool bootstrap
- launchd management through `nix-darwin`
- labels, runner group, token file path, work directory
- stable shell environment for workflows
- optional Homebrew bootstrap through `nix-homebrew`

Nix is not the whole story for:

- attaching the Mac to a Scaleway Private Network in the Scaleway control plane
- creating the required macOS VLAN unless the bootstrap can run privileged host commands
- installing Xcode itself in a clean, fully declarative way
- accepting Apple licenses and simulator runtime provisioning without some imperative bootstrap

## Recommended split of responsibility

### Nix-owned

- `nix-darwin` flake
- system packages
- GitHub runner launchd service
- non-secret configuration
- runner work directory policy

### Imperative bootstrap steps

- attach Private Network in Scaleway
- create VLAN on macOS
- ensure the cache node installs the connected private-subnet route
- install the required Xcode version and simulator runtimes
- place the runner registration secret where the service reads it

## Sandboxing conclusion

- Week 1 should not aim for strong isolation on this machine.
- GitHub explicitly recommends ephemeral runners for autoscaling and security, but this host is better suited to a single persistent runner first.
- True isolation on macOS means VM-backed or one-job/JIT patterns, which is likely phase 2 work.
- The best week-1 boundary is operational isolation:

  - private repos only
  - restricted runner group
  - narrow labels
  - minimal secrets on the host
  - cleanup between jobs

## Best immediate next moves

1. Attach the Mac to the Private Network and create the VLAN.
2. Install Nix and stand up a tiny `nix-darwin` flake under `/runners`.
3. Decide between keeping `/Applications/Xcode_26.2.app` plus `sudo xcode-select`, or moving self-hosted jobs to `DEVELOPER_DIR`.
4. Get the host to match `.xcode-version` and install simulator runtimes.
5. Bring up one runner with a restricted label set.
6. Move one low-risk macOS workflow first.

## Correction to the first-pass assumption about tools

- Missing `mise` and `tuist` on the host are not hard blockers by themselves.
- Current workflows already use `jdx/mise-action`, so those tools can be installed at job runtime.
- The harder blockers are:

  - no Private Network VLAN
  - no Nix bootstrap path yet
  - Xcode `26.0` vs required `26.2`
  - current workflow dependence on `sudo xcode-select`
  - simulator runtimes not ready
