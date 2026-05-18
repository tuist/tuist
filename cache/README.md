# Cache Service

A lightweight Elixir/Phoenix service for handling Tuist cache operations, including Xcode compilation cache and key-value storage.

## Overview

This service provides:
- Key-value storage for cache entries using in-memory Cachex
- Xcode compilation cache using local disk storage
- RESTful API endpoints for cache operations
- Authentication via the Tuist server API
- Optimized nginx-based file serving for read operations

## API Endpoints

### Key-Value Operations
- `PUT /api/cache/keyvalue/:cas_id` - Retrieve key-value entries (requires `account_handle` and `project_handle` query params)
- `PUT /api/cache/keyvalue` - Store key-value entries (requires `account_handle` and `project_handle` query params)

### Xcode Cache Operations
- `GET /api/cache/cas/:id` - Retrieve Xcode cache artifact (nginx serves directly after auth)
- `POST /api/cache/cas/:id` - Store Xcode cache artifact (requires `account_handle` and `project_handle` query params)

### Health Check
- `GET /up` - Health check endpoint (returns 200 when healthy, 503 otherwise)

## Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Configure environment variables:
   - `SECRET_KEY_BASE` - Phoenix secret key base (generate with `mix phx.gen.secret`)
   - `PUBLIC_HOST` - Hostname for the service (release entrypoint sets `$(cat /etc/host_hostname).tuist.dev`)
   - `PORT` - Port to run on (default: 4000)
   - `SERVER_URL` - URL of the main Tuist server for authentication
   - `STORAGE_DIR` - Directory for artifact storage (default: `/storage`)
   - `DISK_HIGH_WATERMARK_PERCENT` - Optional high watermark (%) that triggers disk eviction (default: `75`)
   - `DISK_TARGET_PERCENT` - Optional target usage (%) the eviction job aims for after cleanup (default: `60`)
   - `S3_BUCKET` - S3 bucket for module and Gradle cache artifacts
   - `S3_XCODE_CACHE_BUCKET` - Optional dedicated S3 bucket for Xcode cache artifacts (defaults to `S3_BUCKET`). When set to a different value, Xcode cache reads and writes use this bucket directly.
   - `S3_REGISTRY_BUCKET` - S3 bucket for Swift package registry
   - `KEY_VALUE_READ_BUSY_TIMEOUT_MS` - Optional SQLite contention budget for KV read-through requests (default: `2000`)

3. Start the server:
   ```bash
   mix phx.server
   ```

## Testing

Run tests with:
```bash
mix test
```

## Development

The service uses a checkout-local suffix in development mode through the shared mise shell env. Each checkout persists that suffix through Git metadata when available, while keeping the existing root `.tuist-dev-instance` file as a compatibility fallback. That suffix scopes the cache port and the main server URL it talks to, so developers can choose either multiple clones or linked worktrees and still run their own paired `server/` and `cache/` instances without colliding.

## Architecture

### Core Components

- **CacheWeb.XcodeController** - Handles Xcode cache upload and authentication
  - Uploads limited to 25MB per artifact
  - Streams large files to disk to avoid memory pressure
  - Supports efficient auth subrequests from nginx
- **CacheWeb.KeyValueController** - Handles key-value cache operations
- **Cache.Disk** - Local disk storage backend for cache artifacts
  - Atomic file operations with proper error handling
  - Cross-device move support (falls back to copy)
- **Cache.CacheArtifacts** - Persists artifact metadata in SQLite to power LRU eviction logic
- **Cache.KeyValueStore** - In-memory Cachex-based key-value store
- **Cache.Authentication** - Authentication against Tuist server API
  - Caches successful auth for 10 minutes
  - Caches failures for 3 seconds
  - Validates project access via `/api/projects` endpoint
- **Cache.DiskEvictionWorker** - Scheduled Oban worker that evicts least-recently-used artifacts when the cache volume crosses the configured high watermark

### Nginx Integration

The service is designed to work with nginx for optimal performance:

1. **Read path (GET)**: nginx uses `auth_request` to validate access via Phoenix, then serves files directly from disk
2. **Write path (POST)**: nginx proxies requests to Phoenix for authentication and storage
3. **Auth endpoint**: Internal `/_auth` endpoint for nginx subrequests

See `platform/nginx.nix` for the complete nginx configuration.

## Performance Optimizations

The cache service is optimized for the **read path**, specifically for handling thousands of small files in bursts:

### Nginx Optimizations
- **HTTP/2 support**: 512 concurrent streams, 10000 keepalive requests
- **Direct file serving**: Xcode cache reads bypass Phoenix after auth check
- **Auth subrequests**: Lightweight authentication without proxying file data
- **Immutable caching**: 1-year cache headers for cache artifacts
- **Buffering disabled**: Optimal for large file uploads

### Elixir/Phoenix Optimizations
- **Streaming uploads**: Large files streamed to disk via temporary files
- **Deduplication**: Existing artifacts detected early to avoid re-upload
- **Auth caching**: Project access checks cached via Cachex
  - Successful auth cached for 10 minutes
  - Failed auth cached for 3 seconds
- **Request ID tracking**: Propagates X-Request-ID for observability

### Storage Design
- **Local disk**: Xcode cache artifacts stored on local filesystem for minimal latency
- **Project isolation**: Artifacts organized by `account/project/xcode/` structure
- **Volume mount**: `/storage` directory mounted for persistent storage
- **Atomic operations**: Proper handling of concurrent writes and race conditions
- **Automatic eviction**: Background worker uses SQLite-tracked access metadata to free least-recently-used artifacts when disk usage crosses the configured watermark, while retaining authoritative copies in S3
- **Three S3 buckets**: Xcode cache artifacts (`S3_XCODE_CACHE_BUCKET`), module/Gradle cache (`S3_BUCKET`), and Swift package registry (`S3_REGISTRY_BUCKET`). When `S3_XCODE_CACHE_BUCKET` is unset, Xcode cache artifacts continue using `S3_BUCKET`. When `S3_XCODE_CACHE_BUCKET` points to a different bucket, Xcode cache reads and writes use that bucket directly. Project cleanup still runs both Xcode cache and general cache deletion passes, so duplicate cleanup work in logs is expected when both artifact types resolve to the same bucket.

## Deployment

The service is deployed via Kamal to NixOS servers:
- **Kamal** deploys the Phoenix app as a Docker container (see `config/deploy.yml` and `config/deploy.staging.yml`)
- **NixOS** provides the server infrastructure configured via `platform/` directory:
  - nginx configured via `platform/nginx.nix`
  - Docker runtime for the Phoenix container
  - ACME/Let's Encrypt for TLS certificates
  - `/storage` directory for persistent artifact storage
  - Optimized kernel and network settings

Deploy with:
```bash
kamal deploy -c config/deploy.yml          # Production
kamal deploy -c config/deploy.staging.yml  # Staging
```
