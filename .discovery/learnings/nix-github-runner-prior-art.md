# Nix-based GitHub runner prior art

## Most useful prior art: nix-darwin already has a runner module

The biggest discovery is that `nix-darwin` already includes `services.github-runners`.

That module provides:

- launchd daemons on macOS
- state dir under `/var/lib/github-runners/<name>`
- work dir handling
- log dir under `/var/log/github-runners/<name>`
- token file support
- PAT vs registration token handling
- `replace = true`
- `ephemeral = true`
- labels, runner groups, extra packages, extra environment
- `serviceOverrides` for launchd customization

This means the Darwin side does not need a custom runner service from scratch.

## Why this matters for Tuist

- It keeps the macOS runner story declarative.
- It matches the existing cache-node preference for host management through Nix.
- It avoids ad-hoc launchd plist management.

## Prior art examples

### nix-darwin module itself

Source discovered in upstream nix-darwin:

- `modules/services/github-runner/options.nix`
- `modules/services/github-runner/service.nix`
- `tests/services-github-runners.nix`

Important upstream behaviors:

- if `tokenFile` contains a PAT, the service uses `--pat`
- if it contains a registration token, the service uses `--token`
- it supports `--disableupdate`
- it can wipe work/state directories for ephemeral mode
- it uses launchd daemon management, not a user login session hack

### Cachix CI Agents

`cachix/cachix-ci-agents` is the closest fit to the Tuist direction.

Patterns worth copying:

- wrap `services.github-runners`
- use `replace = true`
- use `ephemeral = true`
- add a curated package set for workflow compatibility
- use explicit labels
- use extra service overrides for Darwin behavior
- include Rosetta-aware handling on Apple Silicon

Most relevant Darwin pattern from their module:

- override launchd keepalive behavior on macOS
- rely on token-file triggers

### Mullvad

`mullvad/mullvadvpn-app` shows a strong multi-runner NixOS pattern:

- multiple runners on one host
- one user per runner
- dedicated work dirs per runner
- explicit labels per workload

The per-runner user/workdir idea is useful if Tuist later wants more than one runner per Mac.

### Worldcoin

`worldcoin/orb-software` shows the opposite end of the spectrum:

- they deliberately relax service sandboxing to let hardware-in-the-loop jobs access the machine more directly

This is useful as a warning:

- hardware-facing workflows often force you to loosen isolation
- when that happens, runner groups and trust boundaries matter even more

### Small ephemeral examples

Smaller Nix configs such as `lovesegfault/nix-config` use a compact pattern:

- `ephemeral = true`
- `replace = true`
- token from a secret file
- extra labels from platform information

## Prior art takeaways

### For week 1

- Use upstream `nix-darwin.services.github-runners`
- keep one runner per host
- use PAT-backed registration
- use `replace = true`
- start persistent first unless there is time to validate ephemeral behavior well

### For phase 2

- adopt `ephemeral = true`
- generate tighter labels by capability and Xcode version
- split by trust boundary or workload type
- investigate JIT registration or GitHub scale-set APIs if fleet growth happens

## What not to build first

- custom launchd plumbing from scratch
- a Darwin runner module inside `cache/`
- a VM-per-job system on this exact 8 GB machine before the bare-metal path works
