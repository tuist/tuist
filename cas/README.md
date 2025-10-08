# Tuist CAS Worker

A Cloudflare Worker that implements a Content-Addressable Storage (CAS) API for build artifacts, backed by S3-compatible storage.

## API

### `GET /api/cas/:id`

Download an artifact.

**Request:**
- Method: `GET`
- Path parameter: `:id` - artifact identifier

**Response:**
- `302 Found` - Artifact exists, redirects to presigned S3 download URL
- `404 Not Found` - Artifact does not exist (no body)

### `POST /api/cas/:id`

Upload an artifact (or verify it already exists).

**Request:**
- Method: `POST`
- Path parameter: `:id` - artifact identifier

**Response:**
- `302 Found` - Artifact doesn't exist, redirects to presigned S3 upload URL
- `304 Not Modified` - Artifact already exists, no upload needed (no body)

## Environment Variables

Required variables:

- `TUIST_S3_REGION` - S3 region (e.g., `us-east-1`)
- `TUIST_S3_ENDPOINT` - S3 endpoint URL (e.g., `https://s3.amazonaws.com`)
- `TUIST_S3_BUCKET_NAME` - S3 bucket name
- `TUIST_S3_ACCESS_KEY_ID` - S3 access key (use `wrangler secret put`)
- `TUIST_S3_SECRET_ACCESS_KEY` - S3 secret key (use `wrangler secret put`)

Optional variables:

- `TUIST_S3_BUCKET_AS_HOST` - Use virtual host style URLs (`true`/`false`, default: `false`)
- `TUIST_S3_VIRTUAL_HOST` - Modify presigned URLs to use virtual host style (`true`/`false`, default: `false`)

## Development

Install dependencies:

```bash
pnpm install
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

Deploy to production:

```bash
pnpm deploy
```

## S3 Storage Structure

Artifacts are stored with keys in the format:

```
{first-2-chars-of-id}/{id}
```

This prefix scheme improves S3 performance by distributing objects across partitions.
