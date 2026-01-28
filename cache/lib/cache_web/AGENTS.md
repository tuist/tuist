# CacheWeb (API Layer)

This directory contains the Phoenix web layer for cache APIs.

## Responsibilities
- REST endpoints for key-value and CAS operations.
- Auth gate before handing off to nginx for direct file serving.
- Swift package registry endpoints for downloads and metadata.

## Related Context
- Cache domain: `cache/lib/cache/AGENTS.md`
- Cache service overview: `cache/README.md`
