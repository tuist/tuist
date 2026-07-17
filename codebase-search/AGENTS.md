# Codebase Search Service

This directory contains the private, read-only Rust service that gives the hosted Tuist Model Context Protocol server bounded access to the public Tuist source tree.

## Boundaries

- Keep the service deterministic. It lists files, searches text, and reads bounded line ranges. It does not call a language model or execute commands.
- Every operation must have hard limits for time, concurrency, traversal, input, bytes read, and output. A deployment setting must not be able to remove those limits.
- Keep the repository root and revision fixed when the process starts. Do not accept repository locations or revisions from requests.
- Resolve and validate every requested path against the configured repository root before reading it.
- Do not follow directory symbolic links while traversing the repository.
- Return the repository revision and stable source links with results.
- Report truncation and skipped content explicitly so callers do not treat partial results as exhaustive.

## Verification

Run from this directory:

```bash
mise run format
mise run lint
mise run test
```

When the container or bundled checkout changes, also build the image with an explicit Tuist revision.

