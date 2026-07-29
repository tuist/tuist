# Tuist codebase search

This private service gives the hosted Tuist Model Context Protocol server deterministic, read-only access to a fixed revision of the public Tuist repository. It intentionally contains no language model and no command execution surface.

The service exposes:

- `POST /v1/search` for bounded literal or regular-expression searches.
- `POST /v1/files` for bounded repository traversal.
- `POST /v1/file` for bounded line-range reads.
- `GET /health` for readiness and revision reporting.

Every response identifies the revision it came from. Search and listing responses also say whether the result is partial and why.

## Resource limits

Limits are compiled into the service rather than taken from deployment settings, so a configuration mistake cannot make a request unbounded:

| Resource | Limit |
| --- | ---: |
| Concurrent operations | 4 |
| Request body | 16 kibibytes |
| Operation duration | 4 seconds |
| Search pattern | 512 bytes |
| Traversal depth | 32 levels |
| Files searched | 20,000 |
| Search bytes | 128 mebibytes |
| Individual searched file | 2 mebibytes |
| Context enrichment | 16 mebibytes |
| Returned search matches | 50 |
| Listed entries visited | 10,000 |
| Returned listed entries | 500 |
| Individual readable file | 4 mebibytes |
| Returned file lines | 400 |
| Returned text | 128 kibibytes |

The Kubernetes deployment adds processor and memory limits around the process as a second boundary.

## Running locally

```bash
CODEBASE_ROOT=.. \
CODEBASE_REVISION="$(git -C .. rev-parse HEAD)" \
mise x -- cargo run
```

The server listens on `127.0.0.1:4000` by default. Set `CODEBASE_BIND_ADDRESS` to change the listener and `CODEBASE_REPOSITORY_URL` to change source-link generation.

## Building the image

The image fetches one exact public Tuist revision during the build and removes Git metadata from the runtime image:

```bash
docker build \
  --build-arg TUIST_REVISION="$(git rev-parse HEAD)" \
  --tag tuist-codebase-search \
  codebase-search
```
