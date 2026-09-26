# Oauth (Context)

This context owns OAuth2 token/client handling (Boruta).

## Responsibilities
- Implement Boruta access token behavior with cache-backed lookups.
- Issue and revoke access/refresh tokens with custom client fetching.
- `Google` verifies One Tap signatures, audience, issuer, timestamps, verified email and session nonce. Public signing keys are cached for at most five minutes within Google's advertised cache lifetime; untrusted token claims never choose a key-fetch address.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

- Cache-token introspection exposes `cache_origin` only from verified signed claims. Tenant-scoped introspection remains grant-filtered; callers that distinguish invalid credentials (401) from insufficient tenant grants (403) must validate the credential before the scoped check. Origin is coarse placement context, never authorization evidence.
