# Cache Service

A lightweight Elixir/Phoenix service for handling Tuist cache operations, including CAS (Content Addressable Storage) and key-value storage.

## Overview

This service provides:
- Key-value storage for cache entries using in-memory Cachex
- CAS object storage using S3
- RESTful API endpoints for cache operations

## Endpoints

### Key-Value Operations
- `GET /api/cache/keyvalue/:cas_id?account_handle=<account>&project_handle=<project>` - Retrieve key-value entries
- `PUT /api/cache/keyvalue?account_handle=<account>&project_handle=<project>` - Store key-value entries

### CAS Operations
- `GET /api/cache/cas/:id?account_handle=<account>&project_handle=<project>` - Retrieve CAS object
- `POST /api/cache/cas/:id?account_handle=<account>&project_handle=<project>` - Store CAS object

## Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Configure environment variables:
   - `AWS_ACCESS_KEY_ID` - AWS access key for S3
   - `AWS_SECRET_ACCESS_KEY` - AWS secret key for S3
   - `AWS_REGION` - AWS region (default: us-east-1)
   - `TUIST_S3_BUCKET_NAME` - S3 bucket name for CAS storage
   - `TUIST_S3_ENDPOINT` - S3 endpoint (optional)
   - `TUIST_S3_VIRTUAL_HOST` - Use virtual host style URLs (default: false)

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

The service runs on port 4001 by default in development mode.

## Architecture

- **CacheWeb.KeyValueController** - Handles key-value operations
- **CacheWeb.CasController** - Handles CAS operations
- **Cache.KeyValueStore** - In-memory storage using Cachex
- **Cache.Storage** - S3 operations for CAS objects