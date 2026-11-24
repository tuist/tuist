# OAuth

## Responsibilities
- Implement Boruta access token behavior through authoritative upstream Ecto lookups.
- Issue and revoke access/refresh tokens with custom client fetching.
- Only the Tuist apps' environment-configured client skips consent. Every other client, dynamically registered ones included, gets a code only from the CSRF-protected consent POST that names the client and where its access goes. Dynamic clients must use S256 PKCE, and their redirect URIs must be HTTPS, loopback HTTP or an app scheme without wildcards (`Clients.allowed_redirect_uri?/1`, also applied to older registrations when loaded). Scopeless grants get the default user scopes only for first-party clients (`Clients.first_party?/1`); others get `mcp`.
- Include the OAuth client ID in signed Tuist tokens so long-lived event subscriptions can recheck the grant before delivery.
- `Google` verifies One Tap signatures, audience, issuer, timestamps, verified email and session nonce. Public signing keys are cached for at most five minutes within Google's advertised cache lifetime; untrusted token claims never choose a key-fetch address.
- OpenID Provider for the Luft server (`luft.work`): only while `Environment.oidc_signing_key/0` is set, `TuistWeb.Oauth.OpenidController` serves discovery, `/oauth2/jwks` (the ID-token key only, public part) and `/oauth2/userinfo`, and `Clients` registers the confidential `luft_server_client/0` from `TUIST_LUFT_SERVER_OAUTH_*`. It may request only `Clients.luft_server_scopes/0` (`AuthorizeController` preauthorizes it to enforce that; Boruta would otherwise grant any public scope) and uses PKCE. It is deliberately not first-party (`Push.first_party_session?/2`): it holds refresh tokens for everyone who signs in, so its tokens do only what their scopes grant, such as `account:organizations:write` for `POST /api/organizations`. Boruta's `issuer` is the app URL so ID tokens' `iss` matches discovery. `ResourceOwners.claims/2` owns the standard claims; `sub` is the user ID. `prompt=create` sends signed-out people to registration. Contract: `luft-server/README.md`.
- Cache-token introspection exposes `cache_origin` only from verified signed claims. Tenant-scoped introspection remains grant-filtered; callers that distinguish invalid credentials (401) from insufficient tenant grants (403) must validate the credential before the scoped check. Origin is coarse placement context, never authorization evidence.

## Authoritative entity operations

Use upstream Boruta Ecto adapters with `Tuist.OAuth.AuthoritativeCache`. Reads always miss and fall through to PostgreSQL; fills and invalidations are no-ops. Do not fork the upstream adapters or introduce a cache-reading fallback. Entity operations must not depend on the replicated cache being available. The independent bcrypt-proof and bounded authentication-subject caches remain unchanged.

Boruta still starts its replicated cache and membership processes. Removing entity callbacks does not remove their startup/lifecycle behavior or establish membership/partition safety for other consumers. Change cluster formation in #14038 only after this release is deployed and observed; display invalidation/election remains a separate step.

### Required upgrade and rollback sequence

Before deploying this version, upgrade every OAuth reader/writer, including background jobs, to the authoritative-reading compatibility release (#14040, merge `c8e54471a425e6d6ecbe6d8097ed56e4f80b4c81`) or a descendant that preserves authoritative reads **and retains legacy invalidations**. Check actual running versions, scheduled jobs and rollback targets in each environment; checked-in Helm values or a single healthy web replica are not fleet evidence. Self-hosted operators must stage that compatibility release too; the [operator guide](../../../priv/docs/en/guides/server/self-host/server.md#oauth-upgrade-and-rollback-boundary) explains the image pin and rollback boundary. Never roll this version directly into a fleet with cache-reading OAuth consumers.

Compatibility and no-invalidation binaries can overlap: both read PostgreSQL, so retained cache entries are irrelevant. The ordinary rollback target is the authoritative-reading compatibility release, not an earlier cache-reading binary. Once any no-invalidation consumer has mutated state, retained entries may be stale even if the last no-invalidation process has stopped.

Rolling back further requires stopping and draining every no-invalidation OAuth consumer, then clearing or replacing every retained cache participant before starting any cache-reading consumer. Prevent old retained participants from rejoining. Ingress draining alone does not stop background jobs or eliminate cache bootstrap from retained peers. Do not silently clear production caches, auto-roll back schemas or combine this change with membership configuration.

### Unchanged contracts

Fresh reads do not make upstream check-then-revoke code redemption or refresh rotation atomic, revoke already-issued Guardian JWTs, or guarantee replacement-token delivery if a process dies after committing a rotation. Removing invalidation eliminates that post-commit cache failure/stall, not every post-commit failure. The existing non-null `refresh_token` index and SQL query shapes are unchanged from #14040; monitor pool/load normally. No new schema or customer data is introduced.
