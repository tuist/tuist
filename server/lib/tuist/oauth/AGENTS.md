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

Do not approve an ordinary mixed-version rolling rollout from the default Boruta cache backend. New replicas no longer invalidate cache entries that old replicas still trust: a refresh token or authorization code revoked through a new replica can remain usable on an old one, and client changes/deletions can remain stale. This is a security-relevant transition, not an accepted freshness allowance.

Before permitting this version to perform OAuth mutations, use an explicitly approved cutover that drains in-flight HTTP and background OAuth work and stops every old replica that can perform OAuth reads, including background jobs, or first deploy a separate compatibility release that reads authoritative state while retaining legacy invalidations across the entire fleet. Removing a replica from HTTP ingress alone is insufficient. Then complete this release before changing cluster membership in #14038. Merely starting new replicas, warming caches, waiting for readiness or keeping the overlap short is not sufficient. Do not add replicated calls back to this backend to conceal the migration requirement.

Rollback to cache-reading binaries is another no-overlap cutover: first drain and stop all upgraded OAuth readers/writers, including background jobs. After the last upgraded consumer stops and before the first rolled-back consumer starts, clear retained entries on every cache participant or replace all cache participants with empty caches. Prevent participants with retained entries from rejoining: the dependency can bootstrap an empty cache from another member, including an upgraded member whose entity stores ignore its cache. Clearing caches before an overlapping rolling rollback is unsafe because subsequent upgraded mutations still skip invalidation. Verify actual deployment configuration separately; checked-in Helm values do not prove which version or topology is deployed.
