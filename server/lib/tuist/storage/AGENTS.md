# Storage (Context)

This context owns object storage access (S3-compatible and Azure Blob).

## Responsibilities
- Generate presigned URLs for upload/download (including multipart uploads).
- Stream and upload objects, check existence, and delete by prefix.
- Enforce Tuist Cloud and opt-in self-hosted artifact-retention windows without deleting analytics metadata.
- Emit telemetry for storage operations.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Storage keys are customer data; update `server/data-export.md` when keys/paths change.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
