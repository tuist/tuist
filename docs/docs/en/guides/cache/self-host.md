---
{
  "title": "Self-hosting",
  "titleTemplate": ":title | Cache | Guides | Tuist",
  "description": "Learn how to self-host the Tuist cache service."
}
---

# Self-host Cache {#self-host-cache}

The Tuist cache service can be self-hosted to provide a private binary cache for your team. This is most useful for organizations with large artifacts and frequent builds, where placing the cache closer to your CI infrastructure reduces latency and improves cache efficiency. By minimizing the distance between your build agents and the cache, you ensure that network overhead doesn't negate the speed benefits of caching.

::: info
<!-- -->
Self-hosting cache nodes requires an **Enterprise plan**.

You can connect self-hosted cache nodes to either the hosted Tuist server (`https://tuist.dev`) or a self-hosted Tuist server. Self-hosting the Tuist server itself requires a separate server license. See the <LocalizedLink href="/guides/server/self-host/install">server self-hosting guide</LocalizedLink>.
<!-- -->
:::

## Prerequisites {#prerequisites}

- Docker and Docker Compose
- S3-compatible storage bucket
- A running Tuist server instance (hosted or self-hosted)

## Deployment {#deployment}

The cache service is distributed as a Docker image at [ghcr.io/tuist/cache](https://ghcr.io/tuist/cache). We provide reference configuration files in the [cache directory](https://github.com/tuist/tuist/tree/main/cache).

::: tip
<!-- -->
We provide a Docker Compose setup because it's a convenient baseline for evaluation and small deployments. You can use it as a reference and adapt it to your preferred deployment model (Kubernetes, raw Docker, etc.).
<!-- -->
:::

### Configuration files {#config-files}

```bash
curl -O https://raw.githubusercontent.com/tuist/tuist/main/cache/docker-compose.yml
mkdir -p docker
curl -o docker/nginx.conf https://raw.githubusercontent.com/tuist/tuist/main/cache/docker/nginx.conf
```

### Environment variables {#environment-variables}

Create a `.env` file with your configuration.

::: tip
<!-- -->
The service is built with Elixir/Phoenix, so some variables use the `PHX_` prefix. You can treat these as standard service configuration.
<!-- -->
:::

```env
# Secret key used to sign and encrypt data. Minimum 64 characters.
# Generate with: openssl rand -base64 64
SECRET_KEY_BASE=YOUR_SECRET_KEY_BASE

# Public hostname or IP address where your cache service will be reachable.
PUBLIC_HOST=cache.example.com

# URL of the Tuist server used for authentication (REQUIRED).
# - Hosted: https://tuist.dev
# - Self-hosted: https://your-tuist-server.example.com
SERVER_URL=https://tuist.dev

# S3 Storage configuration
S3_BUCKET=your-cache-bucket
S3_HOST=s3.us-east-1.amazonaws.com
S3_REGION=us-east-1

# S3 authentication (Option 1: static credentials)
S3_ACCESS_KEY_ID=your-access-key
S3_SECRET_ACCESS_KEY=your-secret-key

# S3 authentication (Option 2: IAM role / IRSA)
# Omit S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY, and set
# AWS_WEB_IDENTITY_TOKEN_FILE and AWS_ROLE_ARN instead.
# These are typically injected automatically by EKS or similar platforms.

# CAS storage (required for non-compose deployments)
DATA_DIR=/data
```

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SECRET_KEY_BASE` | Yes | | Secret key used to sign and encrypt data (minimum 64 characters). |
| `PUBLIC_HOST` | Yes | | Public hostname or IP address of your cache service. Used to generate absolute URLs. |
| `SERVER_URL` | Yes | | URL of your Tuist server for authentication. Defaults to `https://tuist.dev` |
| `DATA_DIR` | Yes | | Directory where CAS artifacts are stored on disk. The provided Docker Compose setup uses `/data`. |
| `S3_BUCKET` | Yes | | S3 bucket name. |
| `S3_HOST` | Yes | | S3 endpoint hostname (e.g. `s3.us-east-1.amazonaws.com`). |
| `S3_REGION` | Yes | | S3 region. Also accepted as `AWS_REGION`. |
| `S3_ACCESS_KEY_ID` | Conditional | | S3 access key. Required when using static credentials. Also accepted as `AWS_ACCESS_KEY_ID`. See [S3 authentication](#s3-authentication). |
| `S3_SECRET_ACCESS_KEY` | Conditional | | S3 secret key. Required when using static credentials. Also accepted as `AWS_SECRET_ACCESS_KEY`. See [S3 authentication](#s3-authentication). |
| `S3_ENDPOINT` | No | | Full S3 endpoint URL. When set, overrides `S3_HOST` with the parsed host and scheme. Useful for S3-compatible providers. |
| `AWS_WEB_IDENTITY_TOKEN_FILE` | No | | Path to a web identity token file for IAM role authentication. See [S3 authentication](#s3-authentication). |
| `AWS_ROLE_ARN` | No | | IAM role ARN to assume when using web identity token authentication. |
| `CAS_DISK_HIGH_WATERMARK_PERCENT` | No | `85` | Disk usage percentage that triggers LRU eviction. |
| `CAS_DISK_TARGET_PERCENT` | No | `70` | Target disk usage after eviction. |
| `PHX_SOCKET_PATH` | No | `/run/cache/cache.sock` | Path where the service creates its Unix socket (when enabled). |
| `PHX_SOCKET_LINK` | No | `/run/cache/current.sock` | Symlink path that Nginx uses to connect to the service. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | No | | gRPC endpoint of an OpenTelemetry Collector for distributed tracing. |
| `LOKI_URL` | No | | Base URL of a Loki-compatible endpoint for log forwarding. |
| `DEPLOY_ENV` | No | `production` | Environment label used in traces and log labels (e.g. `production`, `staging`). |

### S3 authentication {#s3-authentication}

The cache service supports multiple methods for authenticating with S3. The method is determined automatically based on which environment variables are set.

#### Static credentials {#static-credentials}

Set `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY` (or `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`). This is the simplest method and works with any S3-compatible provider.

```env
S3_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
S3_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

#### IAM role with web identity (IRSA) {#iam-role-irsa}

If you run the cache service on **Kubernetes with EKS**, you can authenticate using [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) or [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html). Omit `S3_ACCESS_KEY_ID` and `S3_SECRET_ACCESS_KEY`, and ensure the following environment variables are available to the container:

- `AWS_WEB_IDENTITY_TOKEN_FILE` — path to the projected service account token (injected by EKS)
- `AWS_ROLE_ARN` — the IAM role to assume

EKS injects these variables automatically when a service account is annotated with the IAM role.

#### EC2 instance profile {#instance-profile}

When neither static credentials nor a web identity token file are present, the service falls back to the default AWS credential chain. This means it can authenticate using an **EC2 instance profile** or **ECS task role** without any additional configuration — just ensure the instance or task has an IAM role with S3 access.

### Start the service {#start-service}

```bash
docker compose up -d
```

### Verify the deployment {#verify}

```bash
curl http://localhost/up
```

## Configure the cache endpoint {#configure-endpoint}

After deploying the cache service, register it with your Tuist server:

- **Hosted Tuist server** (`https://tuist.dev`):
  1. Navigate to your organization's **Settings** page.
  2. Find the **Custom cache endpoints** section.
  3. Add your cache service URL (for example, `https://cache.example.com`).

- **Self-hosted Tuist server**:
  1. Set `TUIST_CACHE_ENDPOINTS` to a comma-separated list of cache node URLs (for example, `https://cache-1.example.com,https://cache-2.example.com`).
  2. Restart the Tuist server to apply the configuration.

<!-- TODO: Add screenshot of organization settings page showing Custom cache endpoints section -->

```mermaid
graph TD
  A[Deploy cache service] --> B[Register cache endpoint]
  B --> C[Tuist CLI uses your endpoint]
```

Once configured, the Tuist CLI will use your self-hosted cache.

## Volumes {#volumes}

The Docker Compose configuration uses three volumes:

| Volume | Purpose |
|--------|---------|
| `cas_data` | Binary artifact storage |
| `sqlite_data` | Access metadata for LRU eviction |
| `cache_socket` | Unix socket for Nginx-service communication |

## Health checks {#health-checks}

- `GET /up` — Returns 200 when healthy
- `GET /metrics` — Prometheus metrics

## Monitoring {#monitoring}

### Prometheus metrics {#prometheus-metrics}

The cache service exposes Prometheus-compatible metrics at `/metrics`.

If you use Grafana, you can import the [reference dashboard](https://raw.githubusercontent.com/tuist/tuist/refs/heads/main/cache/priv/grafana_dashboards/cache_service.json).

### Distributed tracing {#distributed-tracing}

Set `OTEL_EXPORTER_OTLP_ENDPOINT` to enable OpenTelemetry traces. The cache service instruments Bandit (HTTP server), Phoenix (request lifecycle), Ecto (database queries), Finch (outgoing HTTP), and Broadway (message processing). Traces are exported via gRPC to the configured collector.

### Log forwarding {#log-forwarding}

Set `LOKI_URL` to forward application logs to a Loki-compatible endpoint. Logs are pushed via the Loki HTTP API with `app=tuist-cache`, `env`, and `level` labels.

## Upgrading {#upgrading}

```bash
docker compose pull
docker compose up -d
```

The service runs database migrations automatically on startup.

## Troubleshooting {#troubleshooting}

### Cache not being used {#troubleshooting-caching}

If you expect caching but are seeing consistent cache misses (for example, the CLI is repeatedly uploading the same artifacts, or downloads never happen), follow these steps:

1. Verify the custom cache endpoint is correctly configured in your organization settings.
2. Ensure your Tuist CLI is authenticated by running `tuist auth login`.
3. Check the cache service logs for any errors: `docker compose logs cache`.

### Socket path mismatch {#troubleshooting-socket}

If you see connection refused errors:

- Ensure `PHX_SOCKET_LINK` points to the socket path configured in nginx.conf (default: `/run/cache/current.sock`)
- Verify `PHX_SOCKET_PATH` and `PHX_SOCKET_LINK` are both set correctly in docker-compose.yml
- Verify the `cache_socket` volume is mounted in both containers
