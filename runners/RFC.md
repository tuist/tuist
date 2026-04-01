# Self-Hosted Runners: Scaleway Host Setup, VM Images, and Host Agent

We've been building toward self-hosted GitHub Actions runners that give teams isolated, ephemeral macOS environments for their CI jobs. The hackday work (PR #8817) proved the concept end-to-end using WebSocket communication and Curie for virtualization. Now we need to turn that into something we can operate: real Scaleway machines managed declaratively, a pipeline for building and distributing macOS VM images, and a lightweight agent process on each host that talks to the Tuist server.

This RFC covers the host-side infrastructure. The server-side components (webhook handling, job matching, REST API) are a separate effort that this work depends on but does not implement.

---

## The Physical Host: Scaleway Mac Minis Managed by nix-darwin

Scaleway offers bare-metal Mac minis (M1 at EUR 0.10/hr, M4 at EUR 0.22/hr) in their Paris region. Each machine runs macOS natively on Apple Silicon, which is what we need for Virtualization.framework-based VMs.

The question is how to manage these machines. We already use NixOS with Colmena for the cache fleet (`cache/platform/flake.nix`), so the team is familiar with declarative Nix configuration. **nix-darwin** is the macOS equivalent of NixOS: it lets us declare the entire machine state (packages, launchd services, network config, secrets) in a flake and converge with `darwin-rebuild switch`. The alternative is Ansible, but it's imperative and drift-prone, and introduces a second configuration paradigm. Shell scripts are fine for one-time bootstrap but not for ongoing management.

The flake structure mirrors what we already have for cache nodes:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = { nixpkgs, nix-darwin, sops-nix, nix-homebrew, ... }:
  let
    machines = [ "runner-paris-1" "runner-paris-2" ];
    sharedModules = [
      sops-nix.darwinModules.sops
      nix-homebrew.darwinModules.nix-homebrew
      ./configuration.nix
      ./network.nix
      ./packages.nix
      ./secrets.nix
      ./vm-cache-relay.nix
      ./host-agent.nix
    ];
    mkDarwinConfig = hostname: nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = sharedModules ++ [
        ./hosts/${hostname}.nix
        { networking.hostName = hostname; }
      ];
    };
  in {
    darwinConfigurations = nixpkgs.lib.genAttrs machines mkDarwinConfig;
  };
}
```

Adding a new host means adding its name to the `machines` list, creating a per-host override file with its static IP, and running `darwin-rebuild switch` over SSH.

### Networking

Each host has three network interfaces that serve distinct purposes:

- **en0** (public): the machine's internet-facing address (51.159.x.x). Used for GitHub API calls, image pulls, and server communication.
- **vlan0** (private, tag 1597): a Scaleway Private Network interface at 172.16.16.x. This connects directly to the cache node at 172.16.16.4 without traversing the public internet.
- **bridge100** (vmnet NAT, 192.168.64.1): created automatically on the first VM boot. Guest VMs get DHCP addresses in the 192.168.64.x range.

The problem is that VMs on bridge100 can't reach the cache on vlan0 directly. We solve this with a socat relay: a persistent launchd daemon (`io.tuist.vm-cache-relay`) listens on bridge100's gateway address (192.168.64.1:443) and forwards traffic to the cache's VLAN IP (172.16.16.4:443). Inside each VM, `/etc/hosts` maps the cache hostname to 192.168.64.1 so all cache traffic flows through the relay without any guest-side configuration beyond a single hosts entry.

### Secrets

The cache fleet uses opnix (1Password integration) for secrets. For runner hosts, **sops-nix with age** is a better fit: each Mac's SSH host key (`/etc/ssh/ssh_host_ed25519_key`) doubles as the age decryption key, so there's no need to provision a separate 1Password service account token on each machine. Encrypted secret files live in `runners/secrets/<hostname>.sops.yaml` and are decrypted to `/run/secrets/` at activation time with mode 0400.

Secrets needed per host:
- `host_api_token`: pre-shared bearer token for authenticating with the Tuist server's host-facing REST API
- `xcodes_apple_id` and `xcodes_apple_password`: Apple ID credentials for automated Xcode downloads via xcodes

Runner registration tokens (the short-lived GitHub tokens that let a runner register for exactly one job) are never persisted on disk. They're minted by the server per-assignment and passed to the host in the assignment payload.

### Bootstrapping a New Machine

Getting a fresh Scaleway Mac from zero to managed takes a single script (`runners/scripts/bootstrap-host.sh`):

1. SSH in as root
2. Install Nix via the Determinate Systems installer
3. Install nix-darwin
4. Clone the tuist monorepo
5. Run `darwin-rebuild switch --flake ./runners/platform#runner-paris-N`

After that, the host's SSH public key gets added to `runners/secrets/.sops.yaml` as an age recipient, the host's secrets file gets created and encrypted with `sops`, and a second `darwin-rebuild switch` picks up the decrypted secrets. The host agent launchd service starts automatically and registers with the server.

Scaleway API automation for ordering new machines is not worth the investment at this scale. The fleet will likely stay under 10 hosts for a while. A provision script that automates the SSH-based bootstrap (steps 1-5) over a fresh machine is sufficient. Terraform can be revisited if the fleet grows significantly.

---

## VM Images: Build Once, Clone Instantly

Each CI job runs inside a disposable macOS VM cloned from a sealed base image. The base image is immutable: it contains macOS, Xcode, the GitHub Actions runner binary, and common developer tools. It is never modified after creation, only cloned.

### Choosing a VM Tool

The Nushell scripts that manage the VM lifecycle call out to a VM CLI for operations like clone, boot, SSH, stop, and delete. We evaluated several options:

**Lume** (MIT, by trycua): single-binary CLI wrapping Virtualization.framework, with an HTTP API server mode. Active development (2024-2025). Supports headless boot, SSH, and cloning. No native OCI registry support for image distribution.

**Curie** (Apache 2.0, by macvmio): plugin-based architecture with OCI support via the Geranos plugin. Used in the hackday PR. Still early/maturing.

**Tart** (Fair Source, by Cirrus Labs): the most mature option with native OCI registry push/pull. However, the Fair Source license requires paid sponsorship beyond 100 CPU cores, which becomes a constraint as the fleet scales.

**Custom (Virtualization.framework directly)**: full control but high maintenance burden. Not justified given the existing options.

The Nushell scripts abstract the VM tool behind a consistent interface, so switching tools later is a matter of updating a handful of scripts rather than rearchitecting. **Lume is the starting point** given its MIT license and simplicity. If it proves insufficient, Curie is the fallback. Tart is ruled out due to licensing constraints at scale.

### Building a Base Image

The build process runs on any Mac with Lume installed (could be one of the Scaleway hosts themselves):

```bash
#!/bin/bash
# runners/images/build-base-image.sh

lume create tuist-sequoia-base --ipsw <restore-image-url>
lume run tuist-sequoia-base --headless
# wait for SSH...

lume ssh tuist-sequoia-base -- <<'PROVISION'
  # Install Homebrew
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Install Xcode
  brew install xcodes
  xcodes install 16.2 --select

  # Accept license
  sudo xcodebuild -license accept

  # Install GitHub Actions runner
  mkdir -p /opt/actions-runner && cd /opt/actions-runner
  curl -O -L https://github.com/actions/runner/releases/download/v2.322.0/actions-runner-osx-arm64-2.322.0.tar.gz
  tar xzf actions-runner-osx-arm64-2.322.0.tar.gz && rm *.tar.gz

  # Install mise and common tools
  curl https://mise.run | sh

  # Harden for CI: disable sleep, screen saver, auto-updates
  sudo pmset -a sleep 0 displaysleep 0
  defaults write com.apple.screensaver idleTime 0
  sudo softwareupdate --schedule off

  # Clean up to minimize image size
  xcrun simctl delete unavailable
  brew cleanup --prune=all
PROVISION

lume stop tuist-sequoia-base
```

This is intentionally a manual, human-supervised process. macOS VM image building involves Xcode downloads (which can fail), license acceptance, and other interactive steps that are hard to fully automate in CI. The result is a sealed disk image that serves as the golden source for all clones.

### Distributing Images

Lume does not have native OCI registry support, so we use `oras` (OCI Registry As Storage) to push raw disk images to GHCR:

```bash
# Compress and push
zstd ~/.lume/vms/tuist-sequoia-base/disk.img -o /tmp/disk.img.zst
oras push ghcr.io/tuist/runner-images/sequoia-xcode-16.2:2026-03-26 /tmp/disk.img.zst

# Pull on a runner host
oras pull ghcr.io/tuist/runner-images/sequoia-xcode-16.2:latest -o /tmp/
zstd -d /tmp/disk.img.zst -o ~/.lume/vms/tuist-sequoia-base/disk.img
```

Images are tagged with `<os>-xcode-<version>:<date>`. The `latest` tag always points to the current recommended image. A `runners/scripts/sync-images.nu` script wraps this workflow for use on hosts.

### Fast Cloning

APFS copy-on-write makes cloning near-instant:

```bash
lume clone tuist-sequoia-base assignment-asg_01JX  # instant, ~0 bytes until writes
# ... job runs, writes go to the clone's CoW layer ...
lume delete assignment-asg_01JX                     # destroy clone, reclaim space
```

This is the key performance primitive. A host can go from "assignment received" to "VM booted and SSH-ready" in seconds rather than minutes.

---

## Assignment Lifecycle: Eight Nushell Scripts

When the host agent receives an assignment, it orchestrates eight Nushell scripts in sequence. Each script is small, testable independently, and handles exactly one phase of the lifecycle:

| Step | Script | What it does |
|------|--------|-------------|
| 1 | `create-assignment-vm.nu` | Clone the sealed base image into a disposable VM named `assignment-<id>` |
| 2 | `run-vm-with-private-cache.nu` | Boot the clone headless, poll until SSH is reachable |
| 3 | `normalize-guest-network.nu` | Reset the guest NIC to DHCP, wait for an IP on the 192.168.64.x range |
| 4 | `ensure-cache-relay.nu` | Verify the host-side socat relay is running; restart it if not |
| 5 | `bootstrap-vm-cache.nu` | SSH into the guest, inject an `/etc/hosts` entry mapping the cache hostname to 192.168.64.1 |
| 6 | `stage-assignment-registration.nu` | Write the runner config JSON and ephemeral registration token into `/var/run/tuist/` inside the guest |
| 7 | `exec-assignment.nu` | SSH into the guest and run `/opt/actions-runner/run.sh --jitconfig <config>`. Blocks until the runner agent exits. |
| 8 | `destroy-assignment-vm.nu` | Stop the VM and delete the clone. Runs unconditionally, including on failure. |

If any script in steps 1-7 fails, step 8 runs anyway for cleanup, and the agent reports the failure back to the server.

---

## Host Agent: A Lightweight Elixir Release

Each Scaleway Mac runs a standalone Elixir OTP application (`runners/agent/`) managed by launchd. It is intentionally minimal: its only job is to talk to the Tuist server and orchestrate the Nushell scripts.

### Why a standalone release

The host agent runs on macOS aarch64-darwin. The Tuist server runs on Render (x86_64-linux). They share almost no dependencies: no Phoenix, no Ecto, no PostgreSQL. Building the agent as a separate Mix project keeps the dependency footprint small (just `req`, `jason`, and `finch`) and lets us package it as a Nix derivation deployed via nix-darwin.

### Module structure

```
runners/agent/lib/
  runner_agent/
    application.ex         # OTP Supervisor: starts Heartbeat and Poller
    config.ex              # Reads env vars and sops-decrypted files
    server_client.ex       # HTTP wrapper for the server's host-facing REST API
    heartbeat.ex           # GenServer: POSTs /hosts/:id/heartbeat every 30s
    poller.ex              # GenServer: POSTs /hosts/:id/next-assignment every 5s when idle
    assignment_runner.ex   # Supervised Task: runs Nushell scripts 1-8 sequentially
```

### How it works

On startup, the agent reads its configuration from environment variables and sops-decrypted files:

- `RUNNER_SERVER_URL` (e.g., `https://tuist.dev`)
- `RUNNER_HOST_API_TOKEN` (from `/run/secrets/host_api_token`)
- `RUNNER_POOL_LABELS` (e.g., `macos,apple-silicon,xcode-16.2`)
- `RUNNER_SCRIPTS_DIR` (path to Nushell scripts)

It registers with the server on first boot (`POST /api/runners/hosts/register`) and persists the returned host ID to `/var/lib/runner-agent/host_id` so it survives restarts.

Two GenServers run concurrently:

**Heartbeat** sends a health report every 30 seconds: CPU usage, memory, free disk space, which VM images are available locally, and whether an assignment is currently active. If the server is unreachable, it logs a warning and retries on the next tick without crashing.

**Poller** checks for work every 5 seconds by calling `POST /api/runners/hosts/:id/next-assignment`. When the server returns an assignment payload (base image tag, registration token, runner name, labels, cache config, timeouts), the Poller spawns an AssignmentRunner as a supervised Task and stops polling until the assignment completes.

**AssignmentRunner** executes the eight Nushell scripts in sequence via `System.cmd("nu", [script_path | args])`. On success or failure, it reports the result back to the server via `POST /api/runners/assignments/:id/complete` and signals the Poller to resume.

### Launchd integration

The agent is packaged as a Nix derivation and declared as a launchd service in `runners/platform/host-agent.nix`:

- Label: `io.tuist.runner-agent`
- KeepAlive: true (launchd restarts on crash)
- Environment variables sourced from sops-decrypted paths
- Stdout/stderr routed to `/var/log/runner-agent/`

---

## Directory Layout

```
runners/
  AGENTS.md
  platform/
    flake.nix                      # nix-darwin flake
    configuration.nix              # Base macOS config: packages, users, SSH
    network.nix                    # VLAN 1597, bridge100, IP forwarding, PF NAT
    vm-cache-relay.nix             # io.tuist.vm-cache-relay launchd daemon
    host-agent.nix                 # io.tuist.runner-agent launchd service + Nix derivation
    packages.nix                   # nushell, socat, zstd, git, jq, aria2, oras
    secrets.nix                    # sops-nix declarations
    hosts/
      runner-paris-1.nix           # Per-host overrides (static IP, hostname)
      runner-paris-2.nix
  secrets/
    .sops.yaml                     # Maps SSH host keys to age recipients
    runner-paris-1.sops.yaml       # Encrypted host secrets
  scripts/
    bootstrap-host.sh              # One-time setup for fresh Scaleway Mac
    sync-images.nu                 # Pull/update VM images from GHCR
    create-assignment-vm.nu        # Step 1: clone base image
    run-vm-with-private-cache.nu   # Step 2: boot headless, wait for SSH
    normalize-guest-network.nu     # Step 3: reset guest NIC
    ensure-cache-relay.nu          # Step 4: verify socat relay
    bootstrap-vm-cache.nu          # Step 5: inject /etc/hosts
    stage-assignment-registration.nu  # Step 6: write runner credentials
    exec-assignment.nu             # Step 7: run GitHub Actions runner
    destroy-assignment-vm.nu       # Step 8: stop VM, delete clone
  images/
    build-base-image.sh            # Build sealed macOS VM image
  agent/
    mix.exs                        # Standalone Elixir release
    config/
      config.exs
      runtime.exs
    lib/
      runner_agent/
        application.ex
        config.ex
        server_client.ex
        heartbeat.ex
        poller.ex
        assignment_runner.ex
```

---

## What This Does Not Cover

- **Server-side implementation**: the `Tuist.Runners` context, database migrations, REST API controllers, and GitHub webhook handling are a prerequisite but separate effort.
- **Observability**: Grafana Alloy integration for runner hosts (metrics, logs, traces). Can follow the pattern in `cache/platform/alloy.nix`.
- **Multi-region**: this RFC assumes Paris-only. Expanding to other Scaleway regions is additive.
- **Autoscaling**: the initial fleet is static. Dynamic provisioning/deprovisioning of Scaleway Macs based on queue depth is a future optimization.
