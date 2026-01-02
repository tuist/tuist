# Registry (Context)

This context owns Swift package registry behavior.

## Responsibilities
- Manage Swift package metadata, releases, and manifests.
- Fetch repository tags via VCS and map versions to SwiftPM semantics.
- Store package artifacts in object storage.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Registry data and artifacts are customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
