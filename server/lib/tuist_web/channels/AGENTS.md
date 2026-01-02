# Channels (Web Layer)

This area owns Phoenix channels for real-time features.

## Responsibilities
- Handle WebSocket channels (e.g., QA log streaming).
- Authorize channel access via `Tuist.Authorization`.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
