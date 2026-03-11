# GitHub runner package build notes

## What the upstream Nix package actually does

The Nix package for `github-runner` in nixpkgs does not just unpack the official runner tarball.

It:

- builds the runner from the upstream `actions/runner` source tree with .NET
- patches the runner for Nix store and `RUNNER_ROOT` behavior
- links Nix-provided Node runtimes into `lib/externals/node20` and `lib/externals/node24`

Important implication:

- `services.github-runners` on nix-darwin inherits that package model
- if the right Node or runner substitutes are unavailable, the Mac may have to build large dependencies locally

## What happened on the live Mac at first

The first remote `darwin-rebuild -- build` of the new `/runners` flake failed.

Critical failure:

```text
error: Cannot build '/nix/store/pk682b1g7rhgpvb5ywmdvkkjnzmxcnlr-nodejs-slim-20.20.1.drv'
Reason: builder failed with exit code 139
Segmentation fault: 11
```

This cascaded into failures for:

- `github-runner-2.332.0`
- the generated runner launchd artifacts
- the full `darwin-system` build

## Most likely explanation

- the host is on macOS `26.0`
- the nixpkgs pin selected a build path that did not get fully substituted from cache
- Node.js then built locally and crashed during configure/build on this machine

This may be a mix of:

- cache availability for this exact Darwin/SDK combination
- current nixpkgs pin choice
- memory pressure on an 8 GB machine

## Why this matters for the project

- the Nix bootstrap story is good, but not yet completely friction-free on this host
- `services.github-runners` is still the right long-term abstraction
- a successful week-1 bootstrap may need one more packaging decision

## Mitigation options that were considered

### Option A: change nixpkgs pin

- try a more conservative nixpkgs branch with better Darwin substitute coverage
- goal: avoid local Node.js builds entirely

### Option B: reduce runner package surface

- test whether pinning only one Node runtime materially reduces the build burden
- this probably does not fully remove the problem, but it is cheap to test

### Option C: custom package around the official runner release

- fetch the official runner tarball directly
- avoid rebuilding from source where possible
- preserve only the Nix patches actually needed for `RUNNER_ROOT` and launchd operation

This is the most work, but it may be the strongest fallback if nixpkgs packaging remains unstable on this host class.

## What worked next

The source-build path was replaced with a custom Nix package that:

- fetches the official `actions-runner-osx-arm64` release tarball
- keeps the upstream runner tree as a read-only template in the Nix store
- copies that template into `RUNNER_ROOT` on first use
- wraps `config.sh` and `Runner.Listener` so the mutable runner state lives outside the Nix store

That package successfully built on the live Mac.

Additional validation on the Mac showed:

- `config.sh --help` works through the wrapper layer
- the wrapper correctly materializes a mutable runner tree under a temporary `RUNNER_ROOT`
- `Runner.Listener --version` returns `2.332.0`
- a full `nix build .#darwinConfigurations."scaleway-m1-01".config.system.build.toplevel` succeeded on the Mac

## Current recommendation

- Keep the binary-packaged runner for week 1.
- Revisit upstream nixpkgs `github-runner` later if the Darwin source-build path becomes reliable again.
