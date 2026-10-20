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

## Authoritative-read compatibility release

Use upstream Boruta Ecto adapters with `Tuist.OAuth.AuthoritativeCache`. Reads always miss and fall through to PostgreSQL; fills are no-ops. Invalidations delegate to `Boruta.Cache.delete/1`, including its failure behavior. Older replicas and rolled-back binaries still read that cache, so retaining the upstream invalidations is required during mixed-version operation. Do not fork the upstream adapters, suppress invalidation failures or introduce a no-invalidation mode into this release. The independent bcrypt-proof and bounded authentication-subject caches remain unchanged.

This is the preparatory compatibility release, not the final removal of replicated OAuth operations. It supports the existing connected-cluster rolling upgrade/rollback contract from cache-reading binaries without introducing missing invalidations. It does not repair pre-existing stale entries, legacy partition/rejoin behavior, delayed legacy-reader publication races, or an environment that already ran an experimental backend without invalidations. Verify actual deployed versions and topology separately; checked-in Helm values are not deployment evidence.

Boruta still starts its replicated cache and membership processes, and invalidations retain their existing RPC/lock and availability costs. An invalidation failure propagates after the database mutation; with fills ignored, a failure may now first surface after consuming a code or refresh token without delivering its replacement, requiring re-authorization. Never swallow that failure to keep an old cached grant usable. Fresh reads do not make upstream check-then-revoke code redemption or refresh rotation atomic or change revocation of already-issued Guardian JWTs. Dynamic token refresh lookup is supported by the concurrent non-null `refresh_token` index; client and event-delivery lookups also add SQL work and need normal pool/load monitoring.

### Subsequent removal of legacy invalidation

Deploy this compatibility version across every OAuth reader/writer, including background jobs, before a separately reviewed release stops sending invalidations. Compatibility and no-invalidation binaries can overlap only after no cache-reading consumers remain. Do not combine the compatibility transition with cluster membership changes in #14038; complete the later removal first.

After the later no-invalidation version performs mutations, rolling back only to this authoritative-reading compatibility version remains valid. Rolling back further to cache-reading binaries is not an ordinary rolling rollback: first drain and stop every no-invalidation OAuth consumer, then clear or replace all cache participants before starting a cache-reading consumer, and prevent retained participants from rejoining. Those are future-release gates, not a substitute for compatibility in this release.
