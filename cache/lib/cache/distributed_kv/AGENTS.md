# Distributed KV

This directory contains the shared-store pieces for distributed key-value replication.

## Responsibilities
- Shared Postgres schemas and repo access.
- Replication shipping and polling helpers.
- Distributed project cleanup coordination, published cleanup barriers, and shared-row GC.

## Notes
- `local` mode remains the default and must keep working without the shared repo.
- Shared-store operations must stay off the normal request hot path unless a feature explicitly opts in.
