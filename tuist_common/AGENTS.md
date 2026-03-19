# Tuist Common (Shared Elixir Utilities)

This package contains shared Elixir utilities consumed by multiple Tuist services.

## Responsibilities
- Host cross-service helper modules that are not owned by a single app.
- Centralize low-level integration utilities shared by `server/` and `cache/`.
- Keep shared telemetry and repository helpers framework-agnostic where practical.
- Own reusable telemetry plugin implementations shared across services.

## Boundaries
- App-specific wiring belongs in `server/` or `cache/`.
- HTTP/API and UI logic stay in the owning application.

## Related Context
- Server service: `server/AGENTS.md`
- Cache service: `cache/AGENTS.md`
