# Rate Limit (Web Layer)

This area owns request rate limiting helpers.

## Responsibilities
- Apply all request rate limits through Valkey with a matching in-memory fallback.
- Preserve fixed-window and token-bucket policies across both backends.
- Compute rate limit keys using client addresses and authenticated subjects.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

## Replica-safety rollout

Shared limiter failures deny by default, especially on credential-guessing and anonymous MCP routes. Dashboard checks and already-authenticated protocol traffic explicitly select `failure_policy: :local`, with a namespaced reduced node-local budget. The divisor is at least five/configured `:rate_limit_fallback_replicas` and the observed node count; tiny budgets deny instead of rounding upward. This is a deliberately conservative outage policy, not a globally exact counter during partitions. Redis children start before the endpoint and stop after it.
