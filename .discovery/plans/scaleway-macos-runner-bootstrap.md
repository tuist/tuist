# Scaleway macOS runner bootstrap plan

## Goal

Bootstrap both sides of the setup with Nix where it makes sense:

- cache nodes: keep the existing NixOS + Colmena flow in `cache/platform/`
- macOS runners: add a separate Darwin bootstrap track, not under `cache/`
- wire the macOS runners to GitHub Actions and to the cache node over Scaleway Private Network

## Recommended architecture for week 1

### Control plane

- Keep cache nodes on the existing `cache/platform/flake.nix` model.
- Add a new mac runner flake under `/runners`.
- Use `nix-darwin` for host config and the built-in `services.github-runners` module for runner lifecycle.
- Keep runner registration dynamic and server-driven through the existing GitHub App integration in `server/`.
- Model runner pools as account-scoped service resources, not as one static token per host.

### Secrets

- Keep secrets out of the repo.
- For cache nodes, continue using `opnix` + 1Password as today.
- For mac runners, reserve the runtime token file path outside the Nix store and let `services.github-runners` read it.
- For the productized path, the server should mint short-lived registration material and the host should write it only at runtime.
- Keep SOPS for host bootstrap material like `xcodes`, not for long-lived runner registration credentials.

### Networking

- Public internet remains required for GitHub control-plane traffic.
- Private Network should carry runner-to-cache traffic.
- Scaleway Apple Silicon requires manual VLAN creation on macOS after Private Network attachment.
- Target private path is the cache node at `172.16.16.4/22`.

### Runner mode

- Week 1 baseline: one persistent runner on the bare-metal Mac, managed by `nix-darwin`.
- Label it explicitly, for example: `self-hosted`, `macos`, `apple-silicon`, `scaleway`, `m1`, `xcode-26-2`.
- Phase 2: evaluate ephemeral or JIT registration once the base path is working.
- For parity with GitHub's own macOS launchd template, add `SessionCreate = true` through runner `serviceOverrides` and validate simulator behavior.
- For the service architecture, plan around per-assignment registration and per-run teardown, not one long-lived shared runner token.

## Why this baseline

- It is the fastest path that stays reproducible.
- `nix-darwin` already ships a maintained `services.github-runners` module.
- The current host is only 8 GB RAM, which is a poor fit for serious VM-per-job isolation.
- Bare-metal + launchd gets you to real builds quickly, while leaving room for stricter isolation later.

## Week plan

### Day 1: fix network reality

- Attach the Mac mini to the same Scaleway Private Network as the cache node.
- Create the VLAN on macOS with `networksetup -createVLAN` using the Private Network VLAN tag.
- Verify a private route exists for `172.16.16.4`.
- Verify `curl` to the cache over the private address.
- On cache nodes, verify the connected route for the private subnet is installed; the current test node needed a manual `ip route add 172.16.16.0/22 dev ens6 src 172.16.16.4` because `ens6` came up with `noprefixroute`.

### Day 2: create the Darwin bootstrap

- Create a new flake outside `cache/`, under `/runners`.
- Add `nix-darwin` and optional `nix-homebrew` inputs.
- Model one host by explicit hostname, not the current UUID-like default.
- Put baseline packages in Nix: `gh`, `curl`, `jq`, `coreutils`, `gnutar`, `gzip`, `gnused`, `findutils`, `bash`, `zstd`.
- Treat `mise` and `tuist` as optional preinstalls because current workflows already use `jdx/mise-action` to install toolchains at job runtime.

### Day 3: make the Mac conform to workflow expectations

- Install the required Xcode version from `.xcode-version`.
- Either:
  - set the system up so `/Applications/Xcode_26.2.app` exists, or
  - change workflow logic before using self-hosted labels and rely on `DEVELOPER_DIR`.
- Preinstall simulator runtimes and create baseline simulator devices.
- Set the default developer directory during bootstrap so jobs do not need interactive sudo.
- Decide whether the runner should use a user-owned Xcode directory plus `DEVELOPER_DIR`, or preserve current workflow behavior with `/Applications/Xcode_26.2.app`.

### Day 4: wire GitHub Actions

- Use `services.github-runners` in `nix-darwin`.
- Start with one runner and a restricted runner group.
- Keep labels narrow so only chosen jobs land on it.
- Move one low-risk macOS workflow onto the new labels first.

### Day 5: wire cache usage and decide the security boundary

- Confirm the runner reaches the cache over Private Network, not public DNS.
- Decide whether the runner should talk to the cache by private IP, split DNS, or an internal hostname.
- Document the sandbox boundary for week 1: bare-metal trust boundary plus cleanup.
- Define phase 2 for stronger isolation.

## Concrete implementation sketch

### Repo placement

- Recommended new area: `/runners`
- When implemented, update the root intent docs to describe the new runner subsystem.

### Darwin flake shape

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-darwin, ... }: {
    darwinConfigurations."tuist-m1-runner-par-01" = nix-darwin.lib.darwinSystem {
      modules = [
        ./configuration.nix
        ./github-runner.nix
      ];
    };
  };
}
```

### Runner bootstrap points

- `services.github-runners.<name>.enable = true`
- `url = "https://github.com/<org>"`
- `runnerGroup = "<restricted-group>"`
- `replace = true`
- `tokenFile = "/var/run/tuist/github-runner.token"` or similar non-store runtime path
- `extraLabels = [ ... ]`
- `extraPackages = [ ... ]`
- `serviceOverrides.SessionCreate = true`

### User model

- Default `_github-runner` may be fine for simple CLI jobs.
- For Xcode and simulator-heavy jobs, prefer an explicit dedicated normal user with a stable home directory.
- Validate where simulator devices, defaults, and caches end up before scaling beyond one host.

### Xcode model

- Lowest workflow churn: install `Xcode_26.2.app` under `/Applications` and keep existing `sudo xcode-select` pattern.
- Lowest bootstrap privilege: install Xcode into a user-owned directory with `xcodes --directory ... --no-superuser`, then use `DEVELOPER_DIR` instead of `sudo xcode-select`.
- Recommended for long-term reproducibility: move to `DEVELOPER_DIR`, because it removes a privileged mutable step from every workflow run.

## Sandboxing recommendation

### Week 1

- Use repo allowlists + runner groups + narrow labels.
- Keep the runner for private repos only.
- Clean the runner work directory between jobs.
- Minimize secrets present on the host.

### Not recommended for week 1

- VM-per-job isolation on this exact host.
- broad org-wide routing to the same runner
- mixing many repos with very different trust levels on one machine

### Phase 2 options

- JIT or ephemeral registration with the GitHub runner APIs
- VM-backed isolation using Apple virtualization tooling when hardware size allows
- one runner per trust boundary or workload class

## Biggest risks discovered

- The Mac currently has no Private Network VLAN configured.
- The Mac cannot currently reach `172.16.16.4`.
- The Mac has no Nix, no Homebrew, and no GitHub runner installed.
- The Mac has Xcode `26.0`, but the repo expects `26.2`.
- The current workflows assume `sudo xcode-select`, but this host does not have passwordless sudo.
- Simulator runtimes/devices are not currently ready for iOS test workloads.
- `nix-darwin`'s runner module is close to the official runner template, but it does not mirror `SessionCreate = true` by default.
- The current cache test node also has a private-network routing bug: `ens6` is DHCP-configured with `noprefixroute`, so the connected `172.16.16.0/22` route must be restored declaratively.
- The initial `/runners` flake reaches the `github-runner` package build, but the current host segfaults while locally building `nodejs-slim-20.20.1`.

## Success criteria

- macOS host bootstraps from a flake under a non-cache infra path
- GitHub runner is launchd-managed through `nix-darwin`
- cache node remains managed through `cache/platform/flake.nix`
- Mac reaches cache over Private Network
- one selected workflow runs successfully on the self-hosted runner
