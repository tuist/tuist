# Evidence: Lume validation on test Mac

Date: 2026-03-17

## Summary

Lume v0.2.86 validated end-to-end on `m1@51.159.120.232` (Scaleway Mac Mini M1, macOS 26.0). Full CI runner workflow confirmed: unattended image creation from IPSW, headless VM boot, SSH guest access, APFS clone, and private cache connectivity via host relay.

## Installation

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"
```

- Installed to `~/.local/share/lume/lume.app`, CLI at `~/.local/bin/lume`
- Automatically installs a launchd daemon (`com.trycua.lume_daemon`) on port 7777
- Includes auto-updater via daily cron job
- `~/.local/bin` must be added to PATH

## Image creation from IPSW with unattended setup

```bash
lume create tahoe-base --os macOS --ipsw latest --cpu 4 --memory 4GB --disk-size 50GB --unattended tahoe --no-display
```

- Downloads macOS 26.3.1 IPSW (~15GB, ~8 minutes)
- Installs macOS into VM (~4 minutes)
- Runs unattended Setup Assistant automation via VNC + OCR (167 steps)
- Creates user `lume` with password `lume`, SSH enabled
- Total time: ~25 minutes from bare metal to SSH-ready base image
- On-disk size: 26GB (sparse, 50GB virtual)

### Unattended setup details

The `tahoe` preset uses VNC + Apple Vision OCR to click through macOS Setup Assistant:
- Selects language, country, skips Apple Account
- Creates user account (`lume`/`lume`)
- Disables analytics, Siri, FileVault
- Enables SSH via `systemsetup -setremotelogin on`

The `sequoia` preset failed on this host (stuck waiting for "Choose Your Look" after FileVault dialog), but the `tahoe` preset succeeded. The OCR-based approach is inherently fragile across macOS minor versions — presets need maintenance.

### CancellationError on stop

The unattended setup completed successfully but threw a `CancellationError` when stopping the VM after provisioning. Despite this error, the VM was fully usable.

## Headless VM boot

```bash
lume run tahoe-base --no-display
```

- VM boots headlessly, gets NAT IP within ~60 seconds
- `lume ls` shows status, IP, SSH availability, VNC URL
- VNC exposed with auto-generated password on a random port

## SSH access

```bash
lume ssh tahoe-base 'hostname && sw_vers'
```

- Default credentials: `lume`/`lume`
- `lume ssh` handles IP discovery and SSH connection in one command
- Confirmed: macOS 26.3.1 (Tahoe) guest on macOS 26.0 host

## Clone performance

```bash
time lume clone tahoe-base tahoe-clone-test
# => 2.283 seconds
```

- APFS Copy-on-Write: zero additional disk usage
- VM must be stopped before cloning
- Clone gets unique MAC address automatically

## OCI pull (broken)

```bash
lume pull macos-sequoia-vanilla:latest sequoia-base
```

- All 82 disk image layers skipped as "unsupported layer media type"
- Only config + nvram downloaded (33MB)
- Appears to be a Lume v0.2.86 bug with the current OCI image format
- Workaround: build from IPSW with `--unattended` (works, just slower)

## Networking validation

### Default NAT

- Guest gets `192.168.64.x` IP via vmnet DHCP
- Gateway at `192.168.64.1` (bridge100)
- Public internet: works
- Private cache IP `172.16.16.4`: times out (expected, NAT doesn't route to VLAN)

### Host relay (socat) for private cache

Host side:

```bash
nix shell nixpkgs#socat --command sudo socat TCP-LISTEN:443,bind=192.168.64.1,reuseaddr,fork TCP:172.16.16.4:443
```

Guest side:

```bash
echo "192.168.64.1 tuist-01-test-cache.par.runners.tuist.dev" | sudo tee -a /etc/hosts
curl -ksS https://tuist-01-test-cache.par.runners.tuist.dev/up
```

Verified result:

```text
connected_to=192.168.64.1:443
UP! Version: e47107b5b9736194d4a091c59e530660c5f13988_uncommitted_d376de4cee7219c5
```

Traffic path confirmed: guest (192.168.64.20) -> relay (192.168.64.1:443) -> private cache (172.16.16.4:443). Public internet continues to work simultaneously.

### Sudo in guest

`lume ssh` does not allocate a TTY, so `sudo` without a password fails. Workaround: use `sshpass` from the host to get a full SSH session with `-t` or pipe the password via stdin (`echo lume | sudo -S ...`).

## VM lifecycle

| Operation | Command | Time | Notes |
|-----------|---------|------|-------|
| Create from IPSW | `lume create --ipsw latest --unattended tahoe` | ~25 min | Includes download, install, setup |
| Clone | `lume clone <src> <dst>` | ~2s | APFS CoW, zero extra disk |
| Run headless | `lume run <name> --no-display` | ~60s to SSH | Background with `nohup` |
| SSH exec | `lume ssh <name> '<cmd>'` | <1s | Built-in IP discovery |
| Stop | `lume stop <name>` | ~15s | SIGINT -> SIGKILL fallback |
| Delete | `lume delete <name> --force` | <1s | Immediate |

## Graceful shutdown issue

`lume stop` consistently fails graceful shutdown (SIGINT times out after 10 attempts) and falls back to SIGKILL. This is a rough edge — the VM doesn't respond to SIGINT cleanly. Data integrity seems fine (VMs boot cleanly after force-kill), but it's not ideal.

## State left on the host

- `/Users/m1/.local/share/lume/lume.app` - Lume v0.2.86
- `/Users/m1/.local/bin/lume` - CLI symlink
- `~/.lume/tahoe-base/` - macOS 26.3.1 base image (26GB)
- LaunchAgent: `com.trycua.lume_daemon` (port 7777)
- Auto-updater cron job

## Comparison with previous Tart results (experiment log entries 42-62)

| Aspect | Tart (previous) | Lume (this test) |
|--------|-----------------|------------------|
| Headless boot | Required GUI login session first | Works without GUI login |
| Guest SSH | Unknown creds on cirruslabs images | `lume`/`lume` default, `--unattended` sets it up |
| Cache relay | Validated with socat | Validated with socat (same architecture) |
| Clone | APFS CoW (instant) | APFS CoW (~2s) |
| Setup from IPSW | Interactive only | `--unattended` preset automation |
| macOS 26 guest | Not tested (Sequoia only) | macOS 26.3.1 confirmed |
| License | Fair Source (100 cores) | MIT |
| Stability | Stable (after GUI login) | Graceful shutdown fails, CancellationError on create, but VMs work |
