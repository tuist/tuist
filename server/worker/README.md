# Tuist CAS Worker

A Cloudflare Worker that implements a Content-Addressable Storage (CAS) API for build artifacts, backed by S3-compatible storage. The worker acts as an authenticated proxy that validates requests with the Tuist server and caches authorization data to minimize latency.

## API

### `GET /api/projects/:account_handle/:project_handle/cas/:id`

Download an artifact.

**Request:**
- Method: `GET`
- Path parameters:
  - `:account_handle` - Account handle
  - `:project_handle` - Project handle
  - `:id` - Artifact identifier
- Headers (required):
  - `Authorization` - Bearer token for authentication
- Headers (optional):
  - `x-request-id` - Request ID for tracing (forwarded to server)

**Response:**
- `401 Unauthorized` - Missing or invalid Authorization header
- `302 Found` - Artifact exists, redirects to presigned S3 download URL
- `404 Not Found` - Artifact does not exist (no body)
- `500 Internal Server Error` - Server error

**Example:**
```bash
GET /api/projects/acme/myapp/cas/abc123
Authorization: Bearer <token>
```

### `POST /api/projects/:account_handle/:project_handle/cas/:id`

Upload an artifact (or verify it already exists).

**Request:**
- Method: `POST`
- Path parameters:
  - `:account_handle` - Account handle
  - `:project_handle` - Project handle
  - `:id` - Artifact identifier
- Headers (required):
  - `Authorization` - Bearer token for authentication
- Headers (optional):
  - `x-request-id` - Request ID for tracing (forwarded to server)

**Response:**
- `401 Unauthorized` - Missing or invalid Authorization header
- `302 Found` - Artifact doesn't exist, redirects to presigned S3 upload URL
- `304 Not Modified` - Artifact already exists, no upload needed (no body)
- `500 Internal Server Error` - Server error

**Example:**
```bash
POST /api/projects/acme/myapp/cas/abc123
Authorization: Bearer <token>
```

## How It Works

1. **Request Validation**: Worker validates that Authorization header is present
2. **Prefix Resolution**:
   - Generates cache key from account handle, project handle, and auth token (SHA-256 hash)
   - Checks KV cache for S3 prefix
   - If not cached: queries server at `GET /api/projects/:account_handle/:project_handle/cas/prefix` with Authorization and x-request-id headers
   - Caches the prefix in KV for 1 hour
3. **S3 Operations**: Uses the prefix to construct the full S3 key and performs HEAD/GET/PUT operations
4. **Response**: Returns presigned S3 URL or appropriate status code

## Environment Variables

Required variables:

- `SERVER_URL` - Tuist server URL (e.g., `https://tuist.dev` or `http://localhost:8080` for dev)
- `TUIST_S3_REGION` - S3 region (e.g., `us-east-1`)
- `TUIST_S3_ENDPOINT` - S3 endpoint URL (e.g., `https://s3.amazonaws.com`)
- `TUIST_S3_BUCKET_NAME` - S3 bucket name
- `TUIST_S3_ACCESS_KEY_ID` - S3 access key (use `wrangler secret put`)
- `TUIST_S3_SECRET_ACCESS_KEY` - S3 secret key (use `wrangler secret put`)

Optional variables:

- `TUIST_S3_BUCKET_AS_HOST` - Use virtual host style URLs (`true`/`false`, default: `false`)
- `TUIST_S3_VIRTUAL_HOST` - Modify presigned URLs to use virtual host style (`true`/`false`, default: `false`)

## KV Namespace

The worker requires a KV namespace binding for caching:

- Binding name: `CAS_CACHE`
- Used to cache S3 prefixes with 1-hour TTL
- Reduces roundtrips to the Tuist server for authorization

Create the KV namespace:

```bash
wrangler kv:namespace create "CAS_CACHE"
wrangler kv:namespace create "CAS_CACHE" --preview
```

Update `wrangler.toml` with the namespace IDs.

## Development

### From Tuist Server

When running the Tuist Phoenix server in development (`mise run dev`), the worker starts automatically with the correct environment variables.

### Standalone

Install dependencies:

```bash
pnpm install
```

Set up environment variables in `.dev.vars`:

```
SERVER_URL=http://localhost:8080
TUIST_S3_REGION=auto
TUIST_S3_ENDPOINT=http://localhost:9095
TUIST_S3_BUCKET_NAME=tuist-development
TUIST_S3_ACCESS_KEY_ID=minio
TUIST_S3_SECRET_ACCESS_KEY=minio1234
TUIST_S3_VIRTUAL_HOST=false
TUIST_S3_BUCKET_AS_HOST=false
```

Run development server:

```bash
pnpm dev
```

Run tests:

```bash
pnpm test
```

## Deployment

Set secrets:

```bash
wrangler secret put TUIST_S3_ACCESS_KEY_ID
wrangler secret put TUIST_S3_SECRET_ACCESS_KEY
```

Set environment variables in `wrangler.toml` or via dashboard:

```toml
[env.production.vars]
SERVER_URL = "https://tuist.dev"
TUIST_S3_REGION = "us-east-1"
TUIST_S3_ENDPOINT = "https://s3.amazonaws.com"
TUIST_S3_BUCKET_NAME = "your-bucket"
TUIST_S3_VIRTUAL_HOST = "false"
TUIST_S3_BUCKET_AS_HOST = "false"
```

Deploy to production:

```bash
pnpm deploy
```

## S3 Storage Structure

Artifacts are stored with keys in the format:

```
{prefix}/{first-2-chars-of-id}/{id}
```

Where:
- `{prefix}` is retrieved from the server based on account/project authorization
- The 2-character prefix improves S3 performance by distributing objects across partitions

Example: `projects/acme/myapp/ab/abc123def456`
