# Evidence: Scaleway and GitHub doc notes

## Scaleway Apple Silicon docs

### Private Networks

Extracted facts:

- Private Networks are an optional feature for Scaleway Mac minis.
- A Mac can attach to up to 8 Private Networks.
- After attachment, macOS requires manual VLAN creation.
- Example method uses `networksetup -createVLAN` on top of `en0`.
- DHCP assigns the private address once the VLAN exists.

Implication for this project:

- Scaleway-side attachment alone is not enough.
- The macOS bootstrap must include a privileged VLAN setup step.

### Package manager page

Extracted facts:

- Scaleway documents Homebrew as the default package-manager path on Apple Silicon.

Implication for this project:

- Scaleway's default guidance is imperative/Homebrew-oriented.
- Tuist can deliberately replace that with Nix + `nix-darwin`, while still keeping Homebrew as an escape hatch if needed.

## GitHub Actions docs

### Self-hosted runner basics

- macOS 11+ is supported.
- ARM64 macOS runners are supported.
- Runners must have outbound HTTPS access to GitHub.

### Service management on macOS

- GitHub's official runner supports `./svc.sh install`, `start`, `stop`, and `status` on macOS.
- Custom launchd service definitions are also allowed as long as they start via `runsvc.sh`.

### Security guidance

- GitHub recommends self-hosted runners only for private repos.
- GitHub recommends ephemeral runners for autoscaling and stronger security isolation.
- Runner groups should be used to limit blast radius.

### Registration guidance

- PAT-backed registration is better for declarative services than one-hour registration tokens.
- If auto-updates are disabled, runner binaries must still be refreshed within GitHub's support window.

## nix-darwin prior art

- `nix-darwin` already provides `services.github-runners`.
- The module already models launchd, work dirs, logs, labels, runner groups, token files, and ephemeral mode.
- This is the best starting point for the macOS side of a Nix-first Tuist runner setup.
