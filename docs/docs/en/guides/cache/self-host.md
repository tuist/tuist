---
{
  "title": "Self-hosting",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "Learn how to self-host the Tuist cache service."
}
---

# Self-host Cache {#self-host-cache}

The Tuist cache service can be self-hosted to provide a private binary cache for your team.

::: info
Self-hosting cache nodes is currently available to all users. This may require an Enterprise plan in the future.
:::

## Prerequisites {#prerequisites}

- Docker and Docker Compose
- S3-compatible storage bucket
- A running Tuist server instance

## Deployment {#deployment}

The cache service is distributed as a Docker image at `ghcr.io/tuist/cache`. We provide reference configuration files in the [cache directory](https://github.com/tuist/tuist/tree/main/cache).

### Configuration files {#config-files}

Create a directory for your deployment and download the configuration files:

```bash
curl -O https://raw.githubusercontent.com/tuist/tuist/main/cache/docker-compose.yml
mkdir -p docker
curl -o docker/nginx.conf https://raw.githubusercontent.com/tuist/tuist/main/cache/docker/nginx.conf
```

### Environment variables {#environment-variables}

Create a `.env` file with the required configuration:

```bash
SECRET_KEY_BASE=<generate with: openssl rand -base64 64>
PHX_HOST=cache.example.com
SERVER_URL=https://your-tuist-server.example.com

# S3 Storage
S3_BUCKET=your-cache-bucket
S3_HOST=s3.us-east-1.amazonaws.com
S3_ACCESS_KEY_ID=your-access-key
S3_SECRET_ACCESS_KEY=your-secret-key
S3_REGION=us-east-1
```

| Variable | Description |
|----------|-------------|
| `SECRET_KEY_BASE` | Phoenix secret key (minimum 64 characters) |
| `PHX_HOST` | Public hostname of your cache service |
| `SERVER_URL` | URL of your Tuist server for authentication |
| `S3_BUCKET` | S3 bucket name |
| `S3_HOST` | S3 endpoint hostname |
| `S3_ACCESS_KEY_ID` | S3 access key |
| `S3_SECRET_ACCESS_KEY` | S3 secret key |
| `S3_REGION` | S3 region |

Optional configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `CAS_DISK_HIGH_WATERMARK_PERCENT` | `85` | Disk usage percentage that triggers LRU eviction |
| `CAS_DISK_TARGET_PERCENT` | `70` | Target disk usage after eviction |
| `PHX_SOCKET_PATH` | `/run/cache/cache.sock` | Path where Phoenix creates its Unix socket |
| `PHX_SOCKET_LINK` | `/run/cache/current.sock` | Symlink path that Nginx uses to connect to Phoenix |

### Start the service {#start-service}

```bash
docker compose up -d
```

### Verify the deployment {#verify}

```bash
curl http://localhost/up
```

## Configure the cache endpoint {#configure-endpoint}

After deploying the cache service, register it in your Tuist server organization settings:

1. Navigate to your organization's **Settings** page
2. Find the **Custom cache endpoints** section
3. Add your cache service URL (e.g., `https://cache.example.com`)

Once configured, the Tuist CLI will use your self-hosted cache.

::: info
Removing the last custom cache endpoint reverts the organization to using the default cache.
:::

## Volumes {#volumes}

The Docker Compose configuration uses three volumes:

| Volume | Purpose |
|--------|---------|
| `cas_data` | Binary artifact storage |
| `sqlite_data` | Access metadata for LRU eviction |
| `cache_socket` | Unix socket for Nginx-Phoenix communication |

## Health checks {#health-checks}

- `GET /up` — Returns 200 when healthy
- `GET /metrics` — Prometheus metrics (localhost only by default)

## Upgrading {#upgrading}

```bash
docker compose pull
docker compose up -d
```

The service runs database migrations automatically on startup.

## Troubleshooting {#troubleshooting}

### Artifacts not caching {#troubleshooting-caching}

1. Verify the custom cache endpoint is configured in your organization settings
2. Ensure your Tuist CLI is authenticated (`tuist auth`)
3. Check cache service logs for errors: `docker compose logs cache`

### Socket path mismatch {#troubleshooting-socket}

If you see connection refused errors:
- Ensure `PHX_SOCKET_LINK` points to the socket path configured in nginx.conf (default: `/run/cache/current.sock`)
- Verify `PHX_SOCKET_PATH` and `PHX_SOCKET_LINK` are both set correctly in docker-compose.yml
- Verify the `cache_socket` volume is mounted in both containers
