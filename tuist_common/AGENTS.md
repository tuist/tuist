# Tuist Common (Shared Elixir Utilities)

This package contains shared Elixir utilities consumed by multiple Tuist services.

## Ingestion capture boundary

`Ingestion.Bufferable.BufferImpl` supports an OTP-app-scoped process-local capture callback for Once's durable publication builder. Captured submissions normalize the same schema fields without entering the asynchronous buffer, and flush is a no-op only in that process. Ordinary callers and other OTP apps retain their existing buffering/write-through behavior. Do not introduce global configuration changes or treat buffer acceptance as remote durability.

## Responsibilities
- Host cross-service helper modules that are not owned by a single app.
- Centralize low-level integration utilities shared by `server/` and `cache/`.
- Keep shared telemetry and repository helpers framework-agnostic where practical.
- Own reusable telemetry plugin implementations shared across services.
- `ObanLogger` emits compact job lifecycle records without job arguments or metadata. Keep job identity, timings, state and exception diagnostics; `ObanTelemetry` independently reports failures to Sentry.

## Boundaries
- App-specific wiring belongs in `server/` or `cache/`.
- HTTP/API and UI logic stay in the owning application.

## Related Context
- Server service: `server/AGENTS.md`
- Cache service: `cache/AGENTS.md`
