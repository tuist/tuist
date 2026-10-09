# Authentication (Context)

This context owns authentication flows and token handling.

## Responsibilities
- Resolve subjects from verified JWTs, user tokens and account/project tokens. `authenticated_subject/1` is fresh; `authenticated_subject_snapshot/1` also exposes expiry from verified state, never unverified claims.
- `TokenVerificationCache` stores successful immutable bcrypt proofs, keyed by the SHA-256 digest of the complete verification input and stored hash. It is independent of credential/permission freshness. Never cache failed proofs.
- `SubjectCache` is a dedicated disposable node-local Cachex cache keyed by HMAC of the full credential. It coalesces fills, prunes to 10,000 entries, and uses a non-sliding deadline anchored to fill start, at most 60 seconds and capped by verified credential expiry. Check both monotonic deadline and wall-clock expiry on every hit. Do not clear either authentication cache on membership/display changes.
- Ordinary API reads and selected ingestion/cache uploads opt into bounded snapshots. Route policy must resolve before controller dispatch, not depend on late `phoenix_controller` metadata. Unknown routes, credential creation, privilege mutations, runner shell upgrades and all other writes remain fresh; strict authentication must also bypass resource loaders.
- Never cache authorization booleans: same-account credentials can have different scopes/project restrictions. Evaluate permissions using the actual bounded subject.
- Streams inherit the original snapshot deadline, not a new interval. Failed refresh is unavailable (HTTP 503 / gRPC unavailable), not invalid credentials or an indefinitely stale grant. Negative results/errors are not retained.
- Refresh tokens while updating `preferred_username` claims; encode tokens with recent accessible project handles.

## Guardrails
- Production-cost proof coverage runs in ExUnit with explicit rounds 12 and one real verification for 2,000 lookups at concurrency 64 using `Mimic.call_original/3`. No shared bcrypt configuration mutation, VM tracing or latency assertions.
- Inject both clocks in snapshot tests. Cover bounded revocation/scopes/deactivation, expiry, slow fills, outages, coalescing, strict routes and stream deadline inheritance. Count real authoritative fills rather than claiming SQL capacity from correctness tests.
- Cold-start fill admission/jitter, proof TTL changes and SQL consolidation remain separate measured improvements. Local tests do not establish production capacity.
- Update `server/data-export.md` when stored customer data changes.

## Related Context
- Parent: `server/lib/tuist/AGENTS.md`
- Web: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
