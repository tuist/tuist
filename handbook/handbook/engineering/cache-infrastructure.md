---
{
  "title": "Cache infrastructure",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "This document describes how Tuist's cache infrastructure is managed using NixOS, including deployment, configuration, and operational procedures."
}
---
# Cache infrastructure

Tuist operates a globally distributed cache service that handles artifacts to speed up developers' workflows. This performance is achieved by deploying servers across multiple geographic regions.

We manage the host machines using [NixOS](https://nixos.org/), which allows us to define the system configuration declaratively and reproduce the same environment across all servers. Even though the cache application itself runs in a Docker container, we rely on NixOS to keep the underlying host environment (kernel, networking, system services, nginx, Docker runtime, and observability) consistent and predictable.

## Overview

The cache service runs on dedicated servers across multiple regions to minimize latency for developers worldwide. Unlike the main Tuist server (which runs on Render), the cache service is deployed on self-hosted machines that we operate and manage ourselves.

NixOS gives us an infrastructure-as-code workflow for those machines, so host-level configuration changes are versioned, reviewable, and reproducible across all regions.

### Architecture

| Component | Technology | Purpose |
|-----------|-----------|---------|
| OS & Configuration | NixOS with Nix Flakes | Declarative, reproducible server configuration |
| Deployment | Colmena | Multi-machine NixOS deployment orchestration |
| Application | Elixir/Phoenix in Docker | Cache service API (deployed via Kamal) |
| Reverse Proxy | nginx | HTTP/2, TLS termination, static file serving |
| Secrets | opnix (1Password) | Secure secrets management |
| Observability | Grafana Alloy | Metrics and logs to Grafana Cloud |

### Server Regions

The cache service is deployed to the following regions:

| Server | Environment | Region |
|--------|-------------|--------|
| `cache-eu-central` | Production | Europe (Central) |
| `cache-us-east` | Production | US East |
| `cache-us-west` | Production | US West |
| `cache-ap-southeast` | Production | Asia Pacific (Southeast) |
| `cache-eu-central-staging` | Staging | Europe (Central) |
| `cache-us-east-staging` | Staging | US East |
| `cache-eu-central-canary` | Canary | Europe (Central) |

All servers are accessible at `cache-<region>.tuist.dev` (e.g., `cache-eu-central.tuist.dev`). Non-production environments include an explicit suffix: `cache-<region>-<env>.tuist.dev` (e.g., `cache-eu-central-staging.tuist.dev`).

## Configuration Structure

The NixOS configuration lives in `cache/platform/` and is structured as follows:

```
cache/platform/
├── flake.nix              # Nix Flake entry point, defines machines and Colmena config
├── configuration.nix      # Base system configuration (kernel, networking, Docker, etc.)
├── disk-config.nix        # Declarative disk partitioning via disko
├── hardware-configuration.nix  # Hardware-specific settings
├── nginx.nix              # nginx reverse proxy configuration
├── secrets.nix            # 1Password secrets integration via opnix
├── users.nix              # User accounts and SSH keys
└── alloy.nix              # Grafana Alloy observability configuration
```

### Key Configuration Files

#### `flake.nix`

> [!NOTE]
> A **Nix flake** is a standardized way to package Nix projects and their dependencies. It pins inputs (via `flake.lock`) and makes builds and environments more reproducible and easier to share. See the [Nix flakes documentation](https://nix.dev/concepts/flakes.html) for details.

Defines the Nix Flake with:
- Input dependencies (nixpkgs, disko, opnix)
- List of all cache machines
- Colmena deployment configuration that targets `cache-<region>(-<env>).tuist.dev`

#### `configuration.nix`

Base system configuration including:
- Linux kernel 6.18 with optimized network sysctls for high-throughput file serving
- Docker runtime for the Phoenix application container
- Firewall rules (ports 22, 80, 443, 4369, 9100-9155)
- File/socket limits and tmpfiles rules for the cache directories

#### `disk-config.nix`

Declarative disk layout using disko:
- **`/dev/sda`**: Boot partition (128MB ESP) + root filesystem (ext4)
- **`/dev/sdb`**: Dedicated `/cas` volume for cache artifacts (ext4 with optimized mount options)

#### `nginx.nix`

nginx configuration optimized for cache performance:
- HTTP/2 with 512 concurrent streams
- 10,000 keepalive requests per connection
- Direct file serving from `/cas` for read operations (bypasses Phoenix after auth)
- Internal proxy locations for local and remote artifact fetching
- Let's Encrypt TLS via ACME

#### `secrets.nix`

1Password integration via opnix for:
- Grafana Cloud Prometheus credentials
- Grafana Cloud Loki credentials

#### `alloy.nix`

Grafana Alloy configuration for:
- Prometheus metrics scraping (cache service + system metrics)
- Docker container log collection
- nginx error log forwarding
- Remote write to Grafana Cloud

## Provisioning with nixos-anywhere

[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) allows you to install NixOS on a remote machine over SSH from any Linux system (including a rescue/recovery environment). It automatically handles disk partitioning using disko and installs the complete NixOS configuration in a single command.

### Prerequisites

1. **Local machine**: Nix with flakes enabled
2. **Target server**:
   - Booted into a Linux environment with SSH access (e.g., rescue mode, live ISO, or existing Linux)
   - Root SSH access (either direct root login or a user with passwordless sudo)
   - At least 1GB RAM (2GB+ recommended for building)
   - Two disks available (`/dev/sda` for system, `/dev/sdb` for cache storage)
3. **DNS**: The hostname must resolve to the server's IP (e.g., `cache-eu-central.tuist.dev`)
4. **1Password**: A service account token for the `cache` vault

### Installation Steps

1. **Add the server to the configuration**

   Edit `cache/platform/flake.nix` and add the new hostname to the `machines` list:

   ```nix
   machines = [
     "cache-eu-central"
     "cache-us-east"
     # ... existing machines
     "cache-new-region"  # Add new server
   ];
   ```

2. **Run nixos-anywhere**

   From your local machine with Nix installed:

   ```bash
   cd cache/platform

   # Install NixOS on the target server
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#cache-new-region \
     root@<server-ip-or-hostname>
   ```

   This command will:
   - Connect to the target server via SSH
   - Partition the disks according to `disk-config.nix` (this **destroys all data** on the target disks)
   - Install NixOS with the configuration from the flake
   - Reboot the server into the new NixOS installation

3. **Configure secrets**

   After the server reboots, SSH in and set up the 1Password token:

   ```bash
   ssh root@cache-new-region.tuist.dev

   # Create the opnix token file (get token from 1Password)
   echo "YOUR_1PASSWORD_SERVICE_ACCOUNT_TOKEN" > /etc/opnix-token
   chmod 600 /etc/opnix-token
   ```

4. **Apply the full configuration**

   The initial nixos-anywhere installation includes the base configuration. Run Colmena to ensure everything is up to date and secrets are properly loaded:

   ```bash
   cd cache/platform
   colmena apply --on cache-new-region
   ```

5. **Deploy the Phoenix application**

   Add the new server to the Kamal deploy configuration (`cache/config/deploy.yml`), then deploy:

   ```bash
   cd cache
   kamal deploy -c config/deploy.yml
   ```

## Deployment Workflow

### Prerequisites

1. SSH access to the target servers (keys configured in `users.nix`)
2. 1Password CLI with access to the `cache` vault
3. Nix with flakes enabled

### Deploying NixOS Configuration

NixOS configuration changes are deployed using Colmena:

```bash
# Deploy to all machines
cd cache/platform
colmena apply

# Deploy to a specific machine
colmena apply --on cache-eu-central

# Build without deploying (dry run)
colmena build
```

Colmena builds the configuration on the target machine (`buildOnTarget = true`) to ensure architecture compatibility.

### Deploying the Phoenix Application

The Phoenix application runs in a Docker container and is deployed separately using Kamal:

```bash
# Production deployment
kamal deploy -d production

# Staging deployment
kamal deploy -d staging
```

Kamal handles:
- Building and pushing the Docker image
- Rolling deployment across servers
- Health checks and rollback

## Operational Procedures

### SSH Access

Connect to servers using:

```bash
ssh <username>@<hostname>.tuist.dev
```

Authorized users are defined in `users.nix`. All users in the `wheel` group have passwordless sudo access.

### Monitoring

Metrics and logs are shipped to Grafana Cloud via Alloy. Access dashboards at [grafana.com](https://grafana.com) with the Tuist organization account.

Key metrics exported:
- Phoenix application metrics at `/metrics`
- System metrics (CPU, memory, disk, network)
- Docker container resource usage

### Adding SSH Access for a New User

1. Edit `users.nix` to add the user with their SSH public key
2. Add the user to appropriate groups (`wheel` for sudo, `docker` for container access)
3. Deploy: `colmena apply`

### Rotating Secrets

Secrets are managed in 1Password under the `cache` vault. The opnix integration automatically fetches secrets at service startup.

To rotate a secret:
1. Update the secret in 1Password
2. Restart the affected service: `systemctl restart grafana-alloy` (or restart the Docker container for app secrets)
