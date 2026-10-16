# Oauth (Context)

This context owns OAuth2 token/client handling (Boruta).

## Responsibilities
- Implement Boruta access token behavior through authoritative upstream Ecto lookups.
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

- Cache-token introspection exposes `cache_origin` only from verified signed claims. Tenant-scoped introspection remains grant-filtered; callers that distinguish invalid credentials (401) from insufficient tenant grants (403) must validate the credential before the scoped check. Origin is coarse placement context, never authorization evidence.

## Replica-safety rollout

Use upstream Boruta Ecto adapters with `Tuist.OAuth.NoCache` as the entity-cache backend. Client/token/grant reads remain authoritative in PostgreSQL; normal OAuth store operations must not invoke Nebulex replicated cache RPCs or cluster-wide locks. Do not fork the upstream Ecto adapters to disable caching. The independent bcrypt-proof and bounded authentication-subject caches remain unchanged.

Boruta still starts its internal replicated cache and membership processes. Bypassing entity stores does not eliminate dependency membership activity or establish the historical cluster-flapping root cause. Fresh database reads also do not make upstream check-then-revoke code redemption or refresh rotation atomic.

### Upgrade and rollback gate

Do not approve an ordinary mixed-version rolling rollout from the default Boruta cache backend. New replicas no longer invalidate cache entries that old replicas still trust: a refresh token revoked through a new replica can remain usable on an old one, and client changes/deletions can remain stale. This is a security-relevant transition, not an accepted freshness allowance.

Before serving OAuth traffic on this version, use an explicitly approved cutover that drains in-flight OAuth work and removes every old serving replica, or first deploy a separate compatibility release that reads authoritative state while retaining legacy invalidations across the entire fleet. Then complete this release before changing cluster membership in #14038. Merely starting new replicas, warming caches, waiting for readiness or keeping the overlap short is not sufficient. Do not add replicated calls back to this backend to conceal the migration requirement.

A rollback to cache-reading binaries likewise requires an explicit cache-generation reset across all cache participants or drained replacement of all participants, not reuse of the still-running legacy cache's entries. Verify actual deployment configuration separately; checked-in Helm values do not prove which version or topology is deployed.
