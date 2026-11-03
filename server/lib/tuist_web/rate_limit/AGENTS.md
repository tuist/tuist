# Rate Limiting

`TuistWeb.RateLimit` is the web adapter: plugs, requester keys and response contracts. Backends and the shared-store failure mechanics live in `Tuist.RateLimit`; see `server/lib/tuist/rate_limit/AGENTS.md`.

## Failure policy by surface

- Deny by default. Password login, agent authentication/registration, signup, the pre-authentication Once address guard, Atlas, SCIM, metrics, authorization-denial accounting and public-page challenge verification do not opt into fallback. SCIM and metrics deliberately remain strict even though authenticated.
- Structured report publishing sets `fallback: false` so backend failures surface as HTTP 503 instead of quota exhaustion (HTTP 429).
- Only dashboard checks (including anonymous per-scope aggregation) and authenticated MCP select `failure_policy: :local`. The MCP router authenticates before this limiter; its anonymous branch is a defensive direct-call guard, not pre-authentication credential protection.
- Preserve existing HTTP 429/gRPC resource-exhausted response contracts.

## Other responsibilities

- Compute keys using trusted client addresses and authenticated subjects. Account subjects use `AuthenticatedAccount.account.id`, not a nonexistent wrapper `id`.
