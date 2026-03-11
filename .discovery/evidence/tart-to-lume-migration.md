# Evidence: Tart to Lume migration

## Problem

Tart uses a Fair Source License (v0.9), not open source. Key restrictions:

- 100 CPU core limit per organization for free use
- Paid tiers: Gold (500 cores, $12k/yr), Platinum (3,000 cores, $36k/yr), Diamond (unlimited, $12/core/yr)
- All host CPU cores count (performance + efficiency), regardless of VM vCPU allocation
- License changed from AGPL v3 to Fair Source on February 28, 2023

For a fleet of Mac Minis (8 cores each), the free tier covers ~12 machines. Beyond that, licensing costs become a factor.

## Alternatives evaluated

| Tool | License | macOS Guest | CLI/Headless | Clone | IPSW | OCI | CI/CD Ready |
|------|---------|-------------|-------------|-------|------|-----|-------------|
| Tart | Fair Source (100 cores) | Yes | Yes | APFS clone | Yes | Yes | Yes |
| Lume | MIT | Yes | Yes (`--no-display`) | `lume clone` | Yes | Yes (GHCR) | Yes |
| VirtualBuddy | BSD-2 | Yes | No (GUI only) | Manual | Yes | No | No |
| UTM | Apache-2.0 | Yes | Partial (`utmctl`) | Limited | Yes | No | No |
| vfkit | Apache-2.0 | Partial (needs GUI for macOS) | Yes (Linux) | Manual `cp -c` | No | No | Linux only |
| virtualOS | Open source | Yes | No (GUI only) | No | Yes | No | No |

## Decision: Lume

Lume (MIT licensed, by trycua/cua) is the replacement. Rationale:

1. **MIT licensed** — no usage limits, no commercial restrictions
2. **Same Virtualization.framework foundation** — identical hypervisor capabilities
3. **Same NAT networking model** — vmnet `bridge100`, `192.168.64.1` gateway
4. **Full CLI** with `--no-display` for headless operation
5. **`lume clone`** for fast ephemeral VMs from base images
6. **IPSW support** for creating base images from scratch
7. **OCI registry** (GHCR) for pulling/pushing base images
8. **Very active** — 400+ releases, 2,995+ commits

## Command mapping

| Operation | Tart | Lume |
|---|---|---|
| Create from IPSW | `tart create <name> --from-ipsw <path>` | `lume create <name> --os macos --ipsw <path>` |
| Clone VM | `tart clone <source> <dest>` | `lume clone <source> <dest>` |
| Run headless | `tart run --no-graphics <vm>` | `lume run --no-display <vm>` |
| Execute in guest | `tart exec <vm> -- <cmd>` | `lume ssh <vm> "<cmd>"` |
| Get guest IP | `tart ip <vm>` | `lume get <vm> -f json` (parse `ipAddress`) |
| Stop VM | `tart stop <vm> --timeout 5` | `lume stop <vm>` |
| Delete VM | `tart delete <vm>` | `lume delete --force <vm>` |
| List VMs | `tart list` | `lume ls -f json` |
| Set resources | `tart set <vm> --cpu N --memory M` | `lume set <vm> --cpu N --memory MGB` |
| Pull image | `tart clone ghcr.io/...` | `lume pull <image:tag>` |

## Key behavioral differences

### `tart exec` vs `lume ssh`

The most significant change. `tart exec` uses Virtualization.framework's guest agent for direct command execution. `lume ssh` uses SSH (NIO SSH + system fallback).

Implications:
- Guest must have SSH enabled
- Credentials must be known (default: `lume`/`lume` for unattended images)
- SSH is more standard and doesn't require framework-level integration
- Slight latency increase for first connection (SSH handshake)

### Base images

- Tart: `ghcr.io/cirruslabs/macos-sequoia-base:latest`
- Lume: `macos-sequoia-vanilla:latest` from trycua, or create custom with `lume create --unattended sequoia`

### Installation

Tart was installed from a release tarball. Lume installs via:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)" -- --no-background-service --no-auto-updater
```

Installs to `~/.local/bin/lume`. Not yet in nixpkgs.

## What stayed the same

- NAT networking model and `bridge100` gateway (`192.168.64.1`)
- Host-side socat TCP relay for cache access
- Guest `/etc/hosts` injection for cache hostname
- The relay is vmnet-generic, not hypervisor-specific
- GUI login session requirement (Apple Virtualization.framework limitation)
- APFS-based VM storage

## Migration scope

### Renamed files

Scripts (dropped "tart" prefix, hypervisor is now an implementation detail):
- `create-tart-assignment-vm.nu` → `create-assignment-vm.nu`
- `run-tart-vm-with-private-cache.nu` → `run-vm-with-private-cache.nu`
- `destroy-tart-assignment-vm.nu` → `destroy-assignment-vm.nu`
- `exec-tart-assignment.nu` → `exec-assignment.nu`
- `ensure-tart-cache-relay.nu` → `ensure-cache-relay.nu`
- `bootstrap-tart-cache.nu` → `bootstrap-vm-cache.nu`
- `cleanup-tart-cache.nu` → `cleanup-vm-cache.nu`
- `normalize-tart-guest-network.nu` → `normalize-guest-network.nu`
- `run-tart-assignment-lifecycle.nu` → `run-assignment-lifecycle.nu`
- `run-tart-assignment-from-payload.nu` → `run-assignment-from-payload.nu`
- `stage-tart-assignment-registration.nu` → `stage-assignment-registration.nu`

Nix modules:
- `tart-cache-relay.nix` → `vm-cache-relay.nix`
- `tuist.runner.tartCacheRelay` → `tuist.runner.vmCacheRelay`
- launchd label: `io.tuist.tart-cache-relay` → `io.tuist.vm-cache-relay`

## Open items after migration

- Lume is not yet in nixpkgs — needs a custom Nix derivation or install script wrapper
- Base VM image needs to be created or pulled using Lume tooling
- SSH credential management for guest access (default `lume`/`lume` vs custom)
- Headless host session requirement remains (not solved by switching hypervisors)
