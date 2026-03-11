# Darwin secrets strategies for runners

## Secrets you will likely need

- Apple/Xcode authentication material for `xcodes`
- Tuist auth material if you do not want every job to bootstrap it interactively
- any future private package, notarization, or signing credentials

Important correction:

- GitHub runner registration credentials should not be modeled as static Darwin secrets for the multi-tenant service path.
- They should be minted dynamically by the server-side GitHub integration and written to a runtime path only when needed.

## Option 1: imperative secret placement

Pattern:

- write a token file to the target host by hand or via SSH
- point `services.github-runners.<name>.tokenFile` at it

Pros:

- fastest bootstrap

Cons:

- weakest reproducibility story
- easy to drift

This is acceptable only as an experiment, not as the product architecture.

## Option 2: `sops-nix` on `nix-darwin`

Why it stands out:

- `sops-nix` has a real Darwin module: `sops-nix.darwinModules.sops`
- secrets decrypt during activation time
- files land outside the Nix store with ownership and permissions

This is a strong fit for:

- generated config fragments
- Apple auth material if you want it file-backed

## Option 3: `agenix`

Important limitation:

- `agenix` has a Home Manager story on Darwin, but it is not the obvious system-level `nix-darwin` choice for a launchd-managed runner host.

Implication:

- for a system runner host, `sops-nix` is the stronger Nix-native option.

## Option 4: 1Password CLI on the host

Pros:

- aligns with current 1Password usage on the cache side

Cons:

- less Nix-native on Darwin than `sops-nix`
- you still need to decide how activation or service startup resolves secrets

## Recommendation

### Week 1

- if speed matters most, start with imperative `xcodes` bootstrap material only
- but the repo now has an optional `sops-nix` Darwin module path under `/runners/modules/secrets.nix`

### Phase 2

- turn on `tuist.runner.secrets.enable = true` and point it at a host-specific SOPS file for `xcodes`
- keep runner registration material dynamic and server-issued

## Extra note

Never point runner `tokenFile` at anything in the Nix store. The upstream runner module explicitly warns against it.
