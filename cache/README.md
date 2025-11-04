# Cache Service

A lightweight Elixir/Phoenix service for handling Tuist cache operations, including CAS (Content Addressable Storage) and key-value storage.

## Overview

This service provides:
- Key-value storage for cache entries using in-memory Cachex
- CAS (Content Addressable Storage) using local disk storage
- RESTful API endpoints for cache operations
- Authentication via the Tuist server API
- Optimized nginx-based file serving for read operations

## API Endpoints

### Key-Value Operations
- `PUT /api/cache/keyvalue/:cas_id` - Retrieve key-value entries (requires `account_handle` and `project_handle` query params)
- `PUT /api/cache/keyvalue` - Store key-value entries (requires `account_handle` and `project_handle` query params)

### CAS Operations
- `GET /api/cache/cas/:id` - Retrieve CAS object (nginx serves directly after auth)
- `POST /api/cache/cas/:id` - Store CAS object (requires `account_handle` and `project_handle` query params)

### Health Check
- `GET /up` - Health check endpoint

## Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Configure environment variables:
   - `SECRET_KEY_BASE` - Phoenix secret key base (generate with `mix phx.gen.secret`)
   - `PHX_HOST` - Hostname for the service
   - `PORT` - Port to run on (default: 4000)
   - `SERVER_URL` - URL of the main Tuist server for authentication
   - `CAS_STORAGE_DIR` - Directory for CAS artifact storage (default: `/cas`)

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

The service runs on port 4000 by default in development mode.

## Architecture

### Core Components

- **CacheWeb.CASController** - Handles CAS upload and authentication
  - Uploads limited to 25MB per artifact
  - Streams large files to disk to avoid memory pressure
  - Supports efficient auth subrequests from nginx
- **CacheWeb.KeyValueController** - Handles key-value cache operations
- **Cache.Disk** - Local disk storage backend for CAS objects
  - Atomic file operations with proper error handling
  - Cross-device move support (falls back to copy)
- **Cache.KeyValueStore** - In-memory Cachex-based key-value store
- **Cache.Authentication** - Authentication against Tuist server API
  - Caches successful auth for 10 minutes
  - Caches failures for 3 seconds
  - Validates project access via `/api/projects` endpoint

### Nginx Integration

The service is designed to work with nginx for optimal performance:

1. **Read path (GET)**: nginx uses `auth_request` to validate access via Phoenix, then serves files directly from disk
2. **Write path (POST)**: nginx proxies requests to Phoenix for authentication and storage
3. **Auth endpoint**: Internal `/_auth_cas` endpoint for nginx subrequests

See `platform/nginx.nix` for the complete nginx configuration.

## Performance Optimizations

The cache service is optimized for the **read path**, specifically for handling thousands of small files in bursts:

### Nginx Optimizations
- **HTTP/2 support**: 512 concurrent streams, 10000 keepalive requests
- **Direct file serving**: CAS reads bypass Phoenix after auth check
- **Auth subrequests**: Lightweight authentication without proxying file data
- **Immutable caching**: 1-year cache headers for CAS objects
- **Buffering disabled**: Optimal for large file uploads

### Elixir/Phoenix Optimizations
- **Streaming uploads**: Large files streamed to disk via temporary files
- **Deduplication**: Existing artifacts detected early to avoid re-upload
- **Auth caching**: Project access checks cached via Cachex
  - Successful auth cached for 10 minutes
  - Failed auth cached for 3 seconds
- **Request ID tracking**: Propagates X-Request-ID for observability

### Storage Design
- **Local disk**: CAS artifacts stored on local filesystem for minimal latency
- **Project isolation**: Artifacts organized by `account/project/cas/` structure
- **Volume mount**: `/cas` directory mounted for persistent storage
- **Atomic operations**: Proper handling of concurrent writes and race conditions

## Deployment

The service is deployed via Kamal to NixOS servers:
- **Kamal** deploys the Phoenix app as a Docker container (see `config/deploy.yml` and `config/deploy.staging.yml`)
- **NixOS** provides the server infrastructure configured via `platform/` directory:
  - nginx configured via `platform/nginx.nix`
  - Docker runtime for the Phoenix container
  - ACME/Let's Encrypt for TLS certificates
  - `/cas` directory for persistent artifact storage
  - Optimized kernel and network settings

Deploy with:
```bash
kamal deploy -c config/deploy.yml          # Production
kamal deploy -c config/deploy.staging.yml  # Staging
```