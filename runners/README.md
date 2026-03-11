# Tuist macOS runners

This directory contains the first Nix bootstrap for Tuist's self-hosted macOS runners.

## Goals

- bootstrap a Scaleway Apple Silicon Mac with Nix
- manage the runner service with `nix-darwin`
- use Homebrew declaratively only where the macOS ecosystem still needs it
- reach the cache node over the Scaleway Private Network
- use Lume (MIT-licensed) for disposable VM isolation per CI job

## Layout

- `flake.nix` - entrypoint for the runner fleet
- `hosts/` - per-host overrides
- `modules/` - reusable nix-darwin modules
- `scripts/` - bootstrap helpers and VM lifecycle scripts
- `secrets/` - documentation for SOPS-managed runner secrets
- `xcode-version` - runner-local Xcode pin kept in sync with the repo root `.xcode-version`

## Week 1 assumptions

- one persistent runner per Mac
- `services.github-runners` manages the GitHub runner through launchd
- the runner package uses the official GitHub runner tarball with a Nix wrapper layer, not a local source build
- the runner uses a token file outside the Nix store
- Xcode is installed separately with `xcodes`
- the cache is reached privately at `172.16.16.4`
- `DEVELOPER_DIR` should be resolved at workflow runtime rather than hardcoded in host config

## Secrets expected on the host

- Dynamic GitHub runner token file: `/var/run/tuist/github-runner.token`
- optional Xcode auth env file: `/etc/tuist/xcodes.env`

Both files are outside the Nix store on purpose.

The initial flake includes an optional `sops-nix` integration for `xcodes` bootstrap material on Darwin.

The GitHub runner token is intentionally not modeled as a static secret. For the multi-tenant service path, it should be minted dynamically by the server-side GitHub integration and written to the runtime token path.

For `xcodes`, prefer `FASTLANE_SESSION` when possible because `XCODES_PASSWORD` may not work reliably for Apple Developer downloads.

## Bootstrap sequence

1. Create the Scaleway VLAN on the Mac:

   ```bash
   sudo networksetup -createVLAN pn en0 1597
   ```

2. Install Nix:

   ```bash
   curl -fsSL https://github.com/DeterminateSystems/nix-installer/releases/download/v3.17.0/nix-installer.sh | sudo sh -s -- install macos --no-confirm --no-modify-profile
   ```

3. Start a shell with Nix:

   ```bash
   . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
   ```

4. Apply the host config:

   ```bash
   sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake .#scaleway-m1-01
   ```

5. Install `xcodes`:

   ```bash
   nu runners/scripts/install-xcodes.nu
   ```

6. Install Xcode and runtimes with `xcodes`.

7. Install Lume:

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)" -- --no-background-service --no-auto-updater
   ```

8. Create base VM image:

   ```bash
   lume create tuist-sequoia-base --os macos --ipsw latest --cpu 2 --memory 4GB
   ```

   Or pull a pre-built image:

   ```bash
   lume pull macos-sequoia-vanilla:latest tuist-sequoia-base
   ```

Note:

- this works interactively on the test host, but fully unattended Apple-authenticated installation is still an open issue
- the installed app path may be `/Applications/Xcode-26.2.0.app`, so workflow logic should not assume only the underscore naming pattern
- Lume requires a GUI login session on the host (same Apple Virtualization.framework limitation as Tart)

## Workflow experiment

- `.github/workflows/cli-self-hosted.yml` is the first manual workflow path targeting the self-hosted runner labels.
- `./.github/actions/select-xcode` supports both GitHub-hosted runners and self-hosted runners that already export `DEVELOPER_DIR`.

## VM guest cache access

The simplest implementation found so far is:

- keep Lume guests on the default NAT network for normal internet and DNS
- run a host-side TCP relay from `192.168.64.1:443` to the private cache at `172.16.16.4:443`
- inject a guest `/etc/hosts` entry that maps the cache hostname to `192.168.64.1`

Helper scripts:

- `runners/scripts/ensure-cache-relay.nu`
- `runners/scripts/bootstrap-vm-cache.nu`
- `runners/scripts/run-vm-with-private-cache.nu`
- `runners/scripts/cleanup-vm-cache.nu`
- `runners/scripts/create-assignment-vm.nu`
- `runners/scripts/exec-assignment.nu`
- `runners/scripts/destroy-assignment-vm.nu`
- `runners/scripts/run-assignment-lifecycle.nu`
- `runners/scripts/stage-assignment-registration.nu`
- `runners/scripts/run-assignment-from-payload.nu`

This keeps guest internet working while forcing cache traffic over the host's private VPC path.

Operational note:

- the managed relay binds `192.168.64.1:443`, so it can only start after the vmnet `bridge100` exists
- `run-vm-with-private-cache.nu` therefore boots the VM first and then kickstarts the managed relay
- if launchd has not rebound the listener yet, `ensure-cache-relay.nu` starts a fallback one-shot relay so the worker flow still succeeds

Example, from the `runners/` directory on the Mac host:

```bash
nu scripts/run-vm-with-private-cache.nu tuist-sequoia-proxytest
nu scripts/cleanup-vm-cache.nu tuist-sequoia-proxytest
```

Disposable assignment-shaped example:

```bash
vm_name=$(nu scripts/run-assignment-lifecycle.nu demo-001 -- /bin/sh -lc 'curl -ksS https://tuist-01-test-cache.par.runners.tuist.dev/up')
nu scripts/destroy-assignment-vm.nu $vm_name
```

Payload-driven example:

```bash
vm_name=$(nu scripts/run-assignment-from-payload.nu examples/assignment-payload.sample.json)
nu scripts/destroy-assignment-vm.nu $vm_name
```

## Why Lume over Tart

Tart uses a Fair Source License (v0.9) with a 100 CPU core limit per organization. This is not OSI-approved open source and becomes a paid dependency at fleet scale.

Lume (MIT licensed, by trycua/cua) provides the same capabilities:

- same Apple Virtualization.framework underpinnings
- same NAT networking model (vmnet `bridge100`, `192.168.64.1` gateway)
- CLI with `clone`, `run --no-display`, `stop`, `delete --force`
- OCI registry support (`lume pull`, `lume push`)
- SSH-based guest command execution (`lume ssh <vm> "command"`)
- unattended macOS setup automation

The key difference is `lume ssh` (SSH-based) instead of `tart exec` (Virtualization.framework agent). SSH requires the guest to have SSH enabled and known credentials. Lume's `--unattended` setup creates a `lume`/`lume` user with SSH enabled by default.

## Notes

- `networksetup` is still an imperative bootstrap step on macOS.
- `xcodes` still needs Apple credentials.
- The cache node must have a working connected route for `172.16.16.0/22` or private traffic will fail even if the Mac VLAN is correct.
- Direct bridged guest private addressing also works experimentally, but the NAT-plus-host-relay model is currently simpler and more reproducible.
- Lume, like Tart, requires a GUI login session on the host for Apple's Virtualization.framework to function.
