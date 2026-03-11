# Evidence: Curie + Geranos evaluation

Date: 2026-03-17

## What they are

**Curie** (macvmio/curie) — Apache 2.0

- CLI macOS VM manager using Apple Virtualization.framework
- Docker-like interface: images, containers, `run`, `create`, `start`, `ps`, `clone`, `commit`, `build`
- Plugin system for pull/push via external tools
- Socket-based VM interaction (keyboard/mouse synthesis, screenshots, ping)
- Shared directory support (virtio-fs)
- Latest version: 0.5.1
- Swift codebase, 148 commits, 23 stars

**Geranos** (macvmio/geranos) — Apache 2.0

- OCI registry transfer tool for macOS VM images
- Specifically optimized for APFS Copy-on-Write disk images
- Bandwidth optimization: verifies local hashes, only transfers changed chunks
- Acts as curie's pull/push plugin via `~/.curie/plugins/{pull,push}`
- Latest version: v0.7.5
- Go codebase, 114 commits, 10 stars

## Installation on test Mac

Host: `m1@51.159.120.232` (Scaleway Mac Mini M1, macOS 26.0)

Curie installed via official install script:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/macvmio/curie/refs/heads/main/.mise/tasks/install)"
```

Result: `curie-0.5.1.pkg` installed to `/usr/local/bin/curie`.

Geranos installed from GitHub release:

```bash
curl -fsSL -o /tmp/geranos.tar.gz https://github.com/macvmio/geranos/releases/download/v0.7.5/geranos_Darwin_arm64.tar.gz
tar xzf /tmp/geranos.tar.gz -C /tmp/
sudo cp /tmp/geranos /usr/local/bin/geranos
```

Result: geranos v0.7.5 in `/usr/local/bin/geranos`.

## Geranos configuration

Geranos needs `~/.geranos/config.yaml` pointing to curie's image directory:

```yaml
images_directory: /Users/m1/.curie/.images
```

## Plugin wiring

Geranos acts as curie's pull/push backend via shell scripts in `~/.curie/plugins/`:

```bash
# ~/.curie/plugins/pull
#!/bin/bash -e
geranos pull "$2"

# ~/.curie/plugins/push
#!/bin/bash -e
geranos push "$2"
```

After creating these, curie's `--help` output automatically includes `pull` and `push` commands.

## Image pull via geranos

```bash
geranos pull ghcr.io/macvmio/macos-sequoia:agent-v1.3b
```

- Downloaded a macOS Sequoia (15.x) image from GHCR
- On-disk size: 25GB (APFS sparse, virtual size 64GB)
- Pull time: several minutes (bandwidth-optimized chunked transfer)
- Available macvmio images: `macos-sequoia` (agent-v1.2, agent-v1.3, agent-v1.3b), `macos-sonoma` (14.5-agent-v1.6/v1.7/v1.8)

Verified through both tools:

```text
curie images => ghcr.io/macvmio/macos-sequoia:agent-v1.3b (64.03 GB, ID b8f29ff4f1c8)
geranos list => ghcr.io/macvmio/macos-sequoia:agent-v1.3b (25G disk usage, manifest present)
```

## Image directory structure

Curie stores images under `~/.curie/.images/<reference>/`:

```text
~/.curie/.images/ghcr.io/macvmio/macos-sequoia:agent-v1.3b/
├── .oci.config.json      # OCI config (76KB)
├── .oci.manifest.json    # OCI manifest (242KB)
├── auxilary-storage.bin  # Apple VZ auxiliary storage (33MB)
├── config.json           # VM config (CPU, memory, network, display)
├── disk.img              # APFS sparse disk image (64GB virtual, 25GB actual)
├── hardware-model.bin    # Apple VZ hardware model
├── machine-identifier.bin # Apple VZ machine identifier
└── metadata.json         # Image metadata (created date, MAC, ID)
```

This is the same Virtualization.framework bundle format as Tart and Lume.

## Clone performance

Curie clone (APFS CoW):

```bash
curie clone ghcr.io/macvmio/macos-sequoia:agent-v1.3b tuist/macos-sequoia:test-clone
```

- Instant (sub-second)
- Nearly zero additional disk (APFS copy-on-write)
- Disk went from 73GB to 72GB free after clone

Geranos clone:

```bash
geranos clone 'ghcr.io/macvmio/macos-sequoia:agent-v1.3b' 'ghcr.io/macvmio/macos-sequoia:local-clone'
```

- Also instant (0.05s)
- Same APFS CoW behavior
- Geranos clones require registry-style references (not arbitrary names)

## Container lifecycle (Docker-like)

Curie distinguishes between images (immutable templates) and containers (mutable instances):

```bash
# Create named container from image
curie create tuist/macos-sequoia:test-clone --name test-runner
# => 9672ca21f7db

# List containers
curie ps
# => shows container with ID, repository, tag, name, size

# Start container headlessly with socket and shared directory
curie start --no-window --share-cwd --socket-path /tmp/curie-vm.sock @9672ca21f7db/tuist/macos-sequoia:test-clone

# Commit container changes back to image
curie commit <container-ref> <new-image-ref>

# Remove container
curie rm <container-ref>
```

This is a genuine image/container split like Docker. Changes made to a running container can be committed back as a new image. Ephemeral `curie run` automatically deletes the container on exit.

## Headless VM operation

```bash
curie run --no-window ghcr.io/macvmio/macos-sequoia:agent-v1.3b
```

- VM boots headlessly on macOS 26 host
- NAT networking via vmnet (same bridge100 / 192.168.64.x model as Tart and Lume)
- ARP-based IP discovery via `curie inspect`
- IP visible within seconds after boot

## Socket interface

Curie exposes a Unix socket for interacting with running VMs:

```bash
curie start --socket-path /tmp/curie-vm.sock ...

# Ping (check if VM is alive)
curie socket ping --socket-path /tmp/curie-vm.sock
# => {"success":{}}

# Keyboard synthesis
curie socket synthesize-keyboard --socket-path /tmp/curie-vm.sock --input "hello"

# JSON API (for complex inputs)
curie socket json --socket-path /tmp/curie-vm.sock --socket-request '{"ping":{}}'
```

Supported socket operations:
- `ping` — check VM health
- `terminate-vm` — stop VM
- `make-screenshot` — capture screen to PNG
- `synthesize-keyboard` — type text, key combos with modifiers
- `synthesize-mouse` — click at coordinates

## Bugs found on macOS 26

1. **Socket JSON crash**: `curie socket json` crashes with `SCBasicObjc.Exception` / `Failed to resolve given type -- TYPE=Executor`. Likely a dependency injection issue in curie 0.5.1 on macOS 26.

2. **Socket keyboard synthesis failure**: `curie socket synthesize-keyboard` returns `Failed to read from socket, error 3`. Different code path from ping (which works), but same socket.

3. **Screenshot via socket**: Crashes with the same DI exception as JSON.

These bugs mean the socket API is currently not usable for automated guest interaction on macOS 26. Only `ping` and `terminate-vm` work.

## Guest SSH access

The macvmio pre-built `agent-v1.3b` image:
- SSH is enabled (port 22 responds, publickey+password+keyboard-interactive auth)
- The `admin` user exists but the password is unknown
- Common passwords (admin, agent, curie, password, 1234, etc.) all fail
- The credentials are not documented publicly

This is an image-level concern, not a curie concern. In production, we'd build our own base image with SSH keys pre-configured.

## VM stability with macOS 15 guest on macOS 26 host

The macvmio Sequoia (macOS 15) image on macOS 26 host:
- Boots successfully and gets NAT IP
- VM shuts down after a few minutes of inactivity
- Possibly an image-level auto-shutdown or Virtualization.framework compatibility issue
- Not observed with Tart Sequoia images on the same host (those stayed running)

## IPSW download and image build

```bash
curie download -p /tmp/RestoreImage.ipsw
# => Downloads macOS 26.3.1 (25D2128) IPSW

curie build tuist/macos:26.3 --ipsw-path /tmp/RestoreImage.ipsw --disk-size "60 GB"
```

- Download auto-detects latest compatible IPSW
- Build creates a fresh VM from IPSW (requires interactive macOS setup wizard)
- Same interactive setup challenge as Tart/Lume: user account configuration requires GUI or keyboard synthesis

## Geranos registry operations

```bash
# List remote tags
geranos remote images ghcr.io/macvmio/macos-sequoia
# => agent-v1.2, agent-v1.3, agent-v1.3b

# Push to registry (requires authentication)
geranos login ghcr.io
geranos push ghcr.io/tuist/macos-runner:v1.0

# Optimized cross-repo push
geranos push ghcr.io/tuist/macos-runner:v1.1 --mount ghcr.io/tuist/macos-runner:v1.0
```

Geranos supports `--mount` for cross-repo blob reuse, reducing upload time when pushing similar images to different repositories.

## Comparison: Curie+Geranos vs Lume vs Tart

| Feature | Curie + Geranos | Lume | Tart |
|---------|----------------|------|------|
| **License** | Apache 2.0 | MIT | Fair Source (100 cores free) |
| **VM Framework** | Virtualization.framework | Virtualization.framework | Virtualization.framework |
| **Image/Container split** | Yes (Docker-like) | No (VMs only) | No (VMs only) |
| **Clone** | APFS CoW (instant) | APFS CoW (instant) | APFS CoW (instant) |
| **Headless** | `--no-window` | `--no-display` | `--no-graphics` |
| **Guest exec** | No built-in | `lume ssh` (SSH-based) | `tart exec` (gRPC agent) |
| **OCI pull/push** | Via geranos plugin | Built-in (GHCR) | Built-in (GHCR) |
| **Shared dirs** | virtio-fs (`--share-cwd`) | virtio-fs (`--dir`) | virtio-fs (`--dir`) |
| **Socket API** | Yes (keyboard/mouse/screenshot) | No | No |
| **Network modes** | NAT only | NAT, bridged, softnet | NAT, bridged, softnet |
| **IP discovery** | ARP via `curie inspect` | `lume get -f json` | `tart ip` |
| **JSON output** | `curie images -f json`, `curie ps -f json` | `lume ls -f json` | `tart list --format json` |
| **Build from IPSW** | `curie build` | `lume create --ipsw` | `tart create --from-ipsw` |
| **Commit changes** | `curie commit` (container -> image) | Not available | Not available |
| **Config editing** | `curie config` (opens editor) | `lume set --cpu --memory` | `tart set --cpu --memory` |
| **Export/Import** | `curie export`/`curie import` (with compression) | Not built-in | Not built-in |
| **Bandwidth optimization** | Geranos: chunk-level dedup, sparse file aware | Standard OCI | Standard OCI |
| **Data directory** | `~/.curie` | `~/.lume` | `~/.tart` |
| **Maturity** | Early (0.5.1, 23 stars) | Medium (2995+ commits) | High (Fair Source, commercial) |
| **macOS 26 support** | Socket bugs, VM boots OK | Not tested yet | Tested working |

## Key advantages of Curie+Geranos

1. **Docker-like workflow**: The image/container split with `commit` is genuinely useful. You can:
   - Create a container from a base image
   - Boot it, install software, configure SSH
   - Commit the result as a new image
   - Push to registry
   - This is the same workflow Docker users know

2. **Bandwidth-optimized transfers**: Geranos is specifically designed for large VM images. It:
   - Splits disk.img into chunks
   - Hashes locally before uploading
   - Only transfers changed chunks
   - Supports cross-repo `--mount` for blob reuse

3. **Socket API (when it works)**: Keyboard/mouse synthesis and screenshots are useful for automated image preparation (clicking through setup wizard, running commands without SSH).

4. **Export/Import**: Built-in compressed archive export is useful for offline distribution.

## Key disadvantages of Curie+Geranos

1. **No built-in `exec`**: Unlike Lume's `lume ssh` or Tart's `tart exec`, curie has no way to run commands inside a VM. You must configure SSH yourself or use keyboard synthesis (which is buggy on macOS 26).

2. **Socket bugs on macOS 26**: The keyboard synthesis and screenshot features crash. Only ping and terminate work. This is a significant gap for automated workflows.

3. **Limited network modes**: NAT only, no bridged or softnet networking. For our cache relay architecture this is fine (we use NAT + host relay anyway), but it's less flexible.

4. **Small community**: 23 stars, 2 contributors on curie. 10 stars, 1 contributor on geranos. Risk of abandonment.

5. **Two separate tools**: Unlike Lume or Tart where everything is one binary, curie+geranos requires installing and configuring two tools plus a plugin bridge.

6. **No pre-built CI-ready images**: The macvmio images exist but credentials are undocumented. Lume and Tart have well-known community images with SSH pre-configured.

7. **VM stability on macOS 26**: The macvmio Sequoia guest shut down unexpectedly on our macOS 26 host. May be image-specific, but needs investigation.

## Assessment

Curie+Geranos is architecturally interesting — the Docker-like image/container model and geranos's bandwidth-optimized transfers are genuine differentiators. However, for our CI runner use case:

- The lack of built-in `exec` capability is a significant gap
- Socket API bugs on macOS 26 block the keyboard synthesis workaround
- The small community and two-tool complexity add risk
- NAT-only networking is sufficient for our relay model but less flexible

**Current recommendation**: Lume remains the better choice for CI runner VMs. Curie+Geranos could become interesting if:
- Socket API bugs are fixed for macOS 26
- An `exec` command is added (SSH-based or agent-based)
- Community grows and pre-built CI images appear
- Geranos's bandwidth optimization becomes critical (e.g., frequent large image distribution across many hosts)

## State left on the host

After this evaluation, the following is installed on `m1@51.159.120.232`:
- `/usr/local/bin/curie` (0.5.1)
- `/usr/local/bin/geranos` (0.7.5)
- `~/.curie/` with one image: `ghcr.io/macvmio/macos-sequoia:agent-v1.3b` (25GB on disk)
- `~/.geranos/config.yaml`
- `~/.curie/plugins/{pull,push}` (geranos bridge scripts)
- `/opt/homebrew/bin/sshpass` (installed during credential testing)
- Tart has been fully removed (binary and all VMs/cache)
