# Workload OIDC verification

`Workload` verifies account-configured providers with explicit project grants; the parent `Tuist.OIDC` module keeps GitHub Actions, CircleCI and Bitrise on their fixed-key repository flow. Reserved built-in issuers cannot be configured as workload policies.

- Require `account_handle` before custom-policy lookup. Unsigned issuer/audience/claims only reject or bound work, never authorize.
- Limit tokens to 16 KiB, candidate policies to 20 and distinct JWKS URLs to two. A grant must verify with that policy's own key URL and match its exact issuer, audience and scalar identity claims, including JSON types. Do not let one key group vouch for another group's projects.
- Pin public HTTPS addresses through `OAuth2.SSRFGuard` on every network fetch, retaining the original TLS hostname. Fetch only through `JWKSClient`, using a single unpooled Mint connection and a pinned IP-literal URL. Never use Req/Finch with per-host connection options: those create permanent pools and dynamic atoms for tenant-controlled hosts. No redirects/retries, 64 KiB response limit, 20 keys and an eight-second total fetch deadline. Private IdPs are not supported by this flow, including on self-hosted installations.
- Allow only bounded asymmetric signing keys/algorithms. Respect JWK signing use, key operations and declared algorithms; a missing `kid` requires exactly one eligible key. Catch malformed key/token failures without logging bearer tokens.
- Cache only normalized, key-type-specific public fields (`kty`, bounded string `kid`, `alg` and the required RSA/EC/OKP coordinates), never private keys, unrelated metadata or cross-type padding. A present `kid` must be at most 256 bytes.
- `JWKSCache` owns a dedicated disposable cache with 15-minute TTL and scheduled pruning to 1,000 entries every second (temporary overshoot is possible). Keep default locking `KeyValueStore.get_or_update`; return `nil` for failed fetches so errors are not cached. Eviction may cause refetches, not authorization changes; rotation can take up to the TTL. Do not cache authorization decisions.
- The controller reloads grants through `Projects.projects_by_oidc_grants/1` before issuance, rechecking policy content and every associated project's current account ownership. An identity never grants access to unselected or future projects. Deletion stops new exchanges, not existing one-hour Tuist JWTs. Custom validation failures share a uniform 401; missing account input is a 400.
- The exchange route uses the existing hosted per-requester limiter, currently 300 requests per minute.

Parent: `../AGENTS.md`. Policy storage: `../accounts/AGENTS.md`.
