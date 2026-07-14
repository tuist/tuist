# WebSock Bridges (Web Layer)

This area owns raw WebSock handlers that bridge browser WebSocket clients to server-side transports.

## Responsibilities
- Validate that controller-upgraded sessions are scoped and authorized before moving bytes.
- Keep transport credentials and infrastructure addresses out of browser-facing payloads.
- Delegate lifecycle and authorization state to `server/lib/tuist` contexts.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Route-level authentication and upgrade decisions belong in controllers.
- Frontend WebSocket clients live in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Controllers: `server/lib/tuist_web/controllers/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
