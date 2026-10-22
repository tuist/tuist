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

## Authoritative entity operations

Use upstream Boruta Ecto adapters with `Tuist.OAuth.AuthoritativeCache`. Reads always miss and fall through to PostgreSQL; fills and invalidations are no-ops. Do not fork the upstream adapters or introduce a cache-reading fallback. Entity operations must not depend on the replicated cache being available. The independent bcrypt-proof and bounded authentication-subject caches remain unchanged.

Boruta still starts its replicated cache and membership processes. Removing entity callbacks does not remove their startup/lifecycle behavior or establish membership/partition safety for other consumers. Change cluster formation in #14038 only after this release is deployed and observed; display invalidation/election remains a separate step.

### Required upgrade and rollback sequence

Before deploying this version, upgrade every OAuth reader/writer, including background jobs, to the authoritative-reading compatibility release (#14040, merge `c8e54471a425e6d6ecbe6d8097ed56e4f80b4c81`) or a descendant that preserves authoritative reads **and retains legacy invalidations**. Check actual running versions, scheduled jobs and rollback targets in each environment; checked-in Helm values or a single healthy web replica are not fleet evidence. Self-hosted operators must stage that compatibility release too; the [operator guide](../../../priv/docs/en/guides/server/self-host/server.md#oauth-upgrade-and-rollback-boundary) explains the image pin and rollback boundary. Never roll this version directly into a fleet with cache-reading OAuth consumers.

Compatibility and no-invalidation binaries can overlap: both read PostgreSQL, so retained cache entries are irrelevant. The ordinary rollback target is the authoritative-reading compatibility release, not an earlier cache-reading binary. Once any no-invalidation consumer has mutated state, retained entries may be stale even if the last no-invalidation process has stopped.

Rolling back further requires stopping and draining every no-invalidation OAuth consumer, then clearing or replacing every retained cache participant before starting any cache-reading consumer. Prevent old retained participants from rejoining. Ingress draining alone does not stop background jobs or eliminate cache bootstrap from retained peers. Do not silently clear production caches, auto-roll back schemas or combine this change with membership configuration.

### Unchanged contracts

Fresh reads alone do not make redemption/rotation atomic. The HTTP token endpoint uses `Tuist.OAuth.Exchange`: parse exactly once with Boruta's public request parser before taking a database connection, lock the effective code/refresh credential from that parsed request, then invoke the unchanged upstream authorization protocol and response converter in one PostgreSQL transaction. Preserve upstream client-authentication precedence, DPoP and error semantics, including request objects and request URIs. Never select locks from merged `conn.params`, canonicalize claims into authentication inputs, or parse and then re-fetch a mutable request URI. HTTP callbacks run only after commit; differential parser and real routed-grant tests must remain valid on Boruta upgrades. Preserve Boruta's code-reuse descendant revocation by committing `invalid_grant`; roll back replacement writes on other exchange errors. Lock contention is bounded and returns OAuth `temporarily_unavailable`/503. All grant-serving replicas must run this wrapper before relying on serialization: older issuers do not cooperate with the row-lock protocol. Already-issued Guardian JWT revocation and lost replacement-response semantics are unchanged. Never fork the cache-reading adapters or backport invalidation removal to 1.355. The lookup indexes remain those from #14040; monitor pool/load normally. This exchange wrapper adds no stored customer data.
