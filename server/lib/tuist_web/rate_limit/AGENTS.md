# Rate Limit (Web Layer)

This area owns request rate limiting helpers.

## Responsibilities
- Apply request rate limits through Valkey when configured. Reject requests on shared-store failure rather than resetting the budget in local memory.
- Preserve fixed-window and token-bucket policies. Installations without Valkey use approximate, eventually consistent in-memory admission; Erlang publish/subscribe does not provide a strict shared budget.
- Compute rate limit keys using client addresses and authenticated subjects.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`
