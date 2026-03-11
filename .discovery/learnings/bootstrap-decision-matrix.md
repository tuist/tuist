# Bootstrap decision matrix

## 1. Where should the mac runner config live?

### Options

- `/runners`
- `cache/platform`
- `infra/`

### Conclusion

- `/runners` is the cleanest target.
- It keeps cache host management and mac runner host management separate.
- It avoids turning `cache/platform` into a mixed Linux + Darwin control plane.

## 2. How should Nix itself be installed?

### Option A: Determinate Nix Installer + nix-darwin

Pros:

- best documented macOS installer experience
- survives macOS upgrades better
- installer supports planning and receipts
- explicit Determinate docs for pairing with `nix-darwin`

Cons:

- extra vendor layer
- if you let Determinate manage Nix config, `nix-darwin` must use `nix.enable = false`

### Option B: upstream Nix + nix-darwin

Pros:

- fewer moving parts conceptually
- closest to stock Nix ecosystem expectations

Cons:

- less ergonomic installer story on macOS
- less opinionated support around upgrades

### Recommendation

- Week 1 recommendation: use Determinate Nix Installer for bootstrap, then `nix-darwin` for host config.
- Keep this decision isolated so it can be swapped later.

## 3. How should Homebrew fit in?

### Option A: no Homebrew

Pros:

- cleaner Nix story

Cons:

- Xcode installation becomes awkward
- some macOS ecosystem tools are much easier to source via Homebrew

### Option B: nix-darwin `homebrew.*` only

Pros:

- declarative formula/cask list

Cons:

- does not install Homebrew itself

### Option C: `nix-homebrew` + nix-darwin `homebrew.*`

Pros:

- reproducible Homebrew bootstrap
- supports Rosetta Homebrew on Apple Silicon
- good fit for `xcodes`

Cons:

- one more moving part

### Recommendation

- Use `nix-homebrew` only if the Xcode/tooling path really needs Homebrew.
- Today, the strongest case is `xcodes`.

## 4. How should Xcode be installed?

### Option A: install to `/Applications/Xcode_26.2.app`

Pros:

- current workflows keep working with minimal changes

Cons:

- needs privileged install/select behavior
- bakes mutable system state into job execution

### Option B: install to a user-owned path and set `DEVELOPER_DIR`

Pros:

- removes per-job sudo need
- more reproducible for self-hosted runners
- works well with `xcodes --directory` and `--no-superuser`

Cons:

- requires workflow changes or self-hosted-specific branching

### Recommendation

- Long-term: Option B.
- Week 1: choose based on whether you want fast adoption or cleaner bootstrap semantics.

## 5. How should the runner be registered?

### Option A: short-lived registration token

Pros:

- simple to start manually

Cons:

- expires quickly
- bad fit for declarative rebuilds

### Option B: fine-grained PAT in a secret file

Pros:

- better fit for `nix-darwin.services.github-runners`
- supports re-registration on rebuild

Cons:

- long-lived credential to manage

### Option C: GitHub App / JIT runner flow

Pros:

- best long-term security story
- aligns with ephemeral/JIT designs

Cons:

- more moving parts for week 1

### Recommendation

- A static token can unblock a one-off experiment.
- The real service architecture should use GitHub App-backed dynamic registration from `server/`.
- Product direction: GitHub App or JIT runner config, not PATs in host config.

## 6. How should secrets be managed on Darwin?

### Option A: `sops-nix` Darwin module

Pros:

- actual `nix-darwin` module exists
- system-level secret files at activation time
- good fit for host bootstrap material like `xcodes` auth files

Cons:

- another bootstrap dependency

### Option B: `agenix`

Pros:

- simple and popular in NixOS

Cons:

- Darwin story is primarily Home Manager, not system-wide `nix-darwin`

### Option C: imperative secret drop-in

Pros:

- fastest way to start

Cons:

- weakest reproducibility story

### Recommendation

- If you want Nix-owned secrets on macOS, prefer `sops-nix` over `agenix`.
- Keep runner registration material dynamic and server-issued.
- Use `sops-nix` for host bootstrap material, not long-lived runner registration credentials.

## 7. How much sandboxing is realistic on this host?

### Option A: persistent bare-metal runner

Pros:

- simplest path to value
- fits current hardware

Cons:

- weakest isolation

### Option B: ephemeral registration on same bare metal

Pros:

- better GitHub-side hygiene

Cons:

- hardware state still persists unless cleaned aggressively

### Option C: VM-per-job using Apple virtualization tooling

Pros:

- strongest isolation story

Cons:

- much heavier operationally
- 8 GB M1 is a weak starting point

### Recommendation

- Week 1: A.
- Phase 2: B.
- Phase 3: C if isolation requirements justify larger hosts.
