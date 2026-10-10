# Oauth (Context)

This context owns OAuth2 token/client handling (Boruta).

## Responsibilities
- Implement Boruta access token behavior with cache-backed lookups.
- Issue and revoke access/refresh tokens with custom client fetching.
- Include the OAuth client ID in signed Tuist tokens so long-lived event subscriptions can recheck the grant before delivery.
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

## Replica-safety rollout

Use upstream Boruta Ecto adapters with `Tuist.OAuth.NoCache` as the entity-cache backend. Client/token/grant reads remain authoritative in PostgreSQL; normal OAuth store operations must not invoke Nebulex replicated cache RPCs or cluster-wide locks. Do not fork the upstream Ecto adapters to disable caching.
