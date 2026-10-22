# OIDC (Context)

This context verifies CI provider OIDC tokens and decides which write scopes an exchanged Tuist token carries.

## Responsibilities
- Verify GitHub Actions, CircleCI, and Bitrise OIDC tokens and extract the repository and workflow claims (`Tuist.OIDC`), and account-configured workload identity tokens (`Tuist.OIDC.Workload`, see below).
- Store and evaluate per-project and per-account scope rules on `ref`, `job_workflow_ref`, and `environment` (`Tuist.OIDC.ScopeRules`). Non-matching write scopes are recorded in the token's `withheld_scopes` claim and enforced by `Tuist.Authorization.Checks.scopes_permit/3`, which substitutes the matching read scope.
- Record which providers exchange tokens for each project (`Tuist.OIDC.ProjectProviders`) so the settings UI can warn when rules would affect CircleCI or Bitrise runs.

## Boundaries
- The token exchange endpoint lives in `server/lib/tuist_web/controllers/api/oidc_controller.ex`; the rules UI lives in `server/lib/tuist_web/live/project_oidc_settings_live.ex` and the account Cache page.
- Anything that authorizes writes for an `AuthenticatedAccount` must go through `Tuist.Authorization` so withheld scopes apply; do not cache authorization decisions.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Only GitHub Actions claims are mapped; tokens from other providers, including workload identities, fail any configured rule.
- Workload tokens are account-wide (`all_projects`), so the exchange evaluates the account rules and the rules of every project in the account (`ScopeRules.evaluate(account, :all_projects, claims)`).
- Rules and provider records are customer data; update `server/data-export.md` on schema changes.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Authorization: `server/lib/tuist/authorization/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`

## Workload OIDC verification

`Workload` verifies account-configured providers with account-wide CI access; the parent `Tuist.OIDC` module keeps GitHub Actions, CircleCI and Bitrise on their fixed-key repository flow. Reserved built-in issuers cannot be configured as workload policies.

- Require `account_handle` before custom-policy lookup. Unsigned issuer/audience/claims only reject or bound work, never authorize.
- Limit tokens to 16 KiB, candidate policies to 20 and distinct JWKS URLs to two. A grant must verify with that policy's own key URL and match its exact issuer, audience and scalar identity claims, including JSON types. Do not let one key group vouch for another group's policies.
- Pin public HTTPS addresses through `OAuth2.SSRFGuard` on every network fetch, retaining the original TLS hostname. Fetch only through `JWKSClient`, using a single unpooled Mint connection and a pinned IP-literal URL. Never use Req/Finch with per-host connection options: those create permanent pools and dynamic atoms for tenant-controlled hosts. No redirects/retries, 64 KiB response limit, 20 keys and an eight-second total fetch deadline. Private IdPs are not supported by this flow, including on self-hosted installations.
- Allow only bounded asymmetric signing keys/algorithms. Respect JWK signing use, key operations and declared algorithms; a missing `kid` requires exactly one eligible key. Catch malformed key/token failures without logging bearer tokens.
- Cache only normalized, key-type-specific public fields (`kty`, bounded string `kid`, `alg` and the required RSA/EC/OKP coordinates), never private keys, unrelated metadata or cross-type padding. A present `kid` must be at most 256 bytes.
- `JWKSCache` owns a dedicated disposable cache with 15-minute TTL and scheduled pruning to 1,000 entries every second (temporary overshoot is possible). Keep default locking `KeyValueStore.get_or_update`; return `nil` for failed fetches so errors are not cached. Eviction may cause refetches, not authorization changes; rotation can take up to the TTL. Do not cache authorization decisions.
- The controller reloads verified policy evidence through `Accounts.oidc_account_by_grants/1` before issuance, rechecking policy ID, own key URL, issuer, audience, typed claims and account. Issue an account-wide CI-only token with `all_projects: true`, not an enumerated project list; no projects need to exist yet. All current/future projects are included, but ordinary project authorization still requires current ownership by the token's account, including after transfers. Deletion stops new exchanges, not existing one-hour Tuist JWTs. Custom validation failures share a uniform 401; missing account input is a 400.
- The exchange route uses the existing hosted per-requester limiter, currently 300 requests per minute.

Policy storage: `../accounts/AGENTS.md`.
