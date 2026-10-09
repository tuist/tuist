# Restoring replica-safe servers after the authentication brownout

## Incident

PR [#13658](https://github.com/tuist/tuist/pull/13658) was merged on September 29, 2026. Eduardo reverted it in [#13722](https://github.com/tuist/tuist/pull/13722) after production throughput fell approximately 30-fold. CPU increased while PostgreSQL stayed idle, and Kura introspection timed out. Erlang membership flapped and invalidated local caches. Some CLI refresh requests completed after client timeouts, leaving those clients with revoked refresh tokens.

Removing the subject cache exposed bcrypt on every project/account-token request. The original two-server verification used user credentials, not the bcrypt-backed credentials used by high-volume CI traffic. Ordinary ExUnit also reduces bcrypt cost to one round, masking this capacity regression.

## Restored behavior

- Stable Erlang cookies, fixed private distribution ports, headless discovery and scoped network policies, including self-hosted installations and Helm validation.
- Session-free legacy MCP requests. Preserve the newer modern transport and event-subscription implementation rather than replacing it with the original pre-revert implementation.
- Authoritative credential and permission checks on each request, cross-node display invalidation, elected marketing polling, distributed image locks, fail-closed shared admission, synchronous required ingestion staging and supervised optional tasks that drain on shutdown.
- Preserve ingestion, marketing globe, Once events and authentication changes merged since the revert.

## Authentication fix

`Tuist.Authentication.TokenVerificationCache` retains only successful proofs that the complete secret/pepper input matches the current stored bcrypt hash. Its keys are SHA-256 digests; no plaintext token or authenticated subject is retained. The one-minute node-local cache coalesces concurrent misses per key without serializing unrelated credentials. Scheduled pruning limits retained entries to 10,000, with brief overshoot between pruning intervals.

Token rows are loaded before proof lookup, and expiry, user activity, scopes and authorization are evaluated from current state. Deleting a token, changing its hash, expiring it or changing its scopes cannot be bypassed by a warmed proof. This avoids the stale-access window of restoring the old subject/permission cache, without a token-format migration or rotating existing credentials.

The proof cache is separate from the display cache and is not invalidated on node joins/departures. Cluster flapping therefore cannot force all active credentials to rerun bcrypt. Verification rejects unavailable-cache lookups rather than falling back to unbounded bcrypt work. JWT and user-token authentication is not cached.

## Regression gates

- Token traffic tests assert one bcrypt call across repeated requests and concurrent cold misses, fresh scopes, immediate project/account revocation, expiry and user deactivation. The mixed-credential authentication regression sends 400 requests over 20 distinct project/account credentials through the real context and database and requires exactly 20 bcrypt calls, without a wall-clock assertion.
- Cache tests cover changed secrets/hashes, TTL, unsuccessful verification, unrelated-key progress and repeated membership events.
- `server/verification/bcrypt_load.exs` runs in its own VM at bcrypt cost 12. A burst of 2,000 requests at concurrency 64 must succeed with exactly one bcrypt call. Both the CI build-plan job and unsharded fallback run this guard. It is a CPU-path regression guard, not a complete API load test.
- The two-server harness additionally exercises 400 real `/api/cache/access` requests with both project and account tokens, at cost 12, with exactly one verification per credential per replica and immediate revocation afterward. Optional `TUIST_E2E_TOKEN_CACHE_STRESS=1` adds 7,680 requests over 128 distinct credentials, checks actual TTL expiry, post-rejoin cache isolation and forced LRW eviction, and requires zero bcrypt calls during every warm phase. Its existing failover, invalidation, images, shutdown and shared-limiter checks remain available.

## Rollout requirements

Do not equate historical pre-revert verification results with validation of this restoration. Run the complete two-server harness against disposable services, then exercise project/account-token traffic on staging/canary at representative production concurrency. Observe HTTP throughput and latency (especially `/oauth2/introspect`), web CPU, bcrypt work, database pool pressure, Oban queue age and Erlang membership stability before promoting. Keep the existing replica/HPA settings unchanged during this verification.

On the first rollout, old nodes can reject modern requests until replacement completes; old nodes may also retain subject/authorization caches until their normal TTL expires. A newly created cluster-cookie Secret requires all replacement pods to use the same cookie. Verify membership and allow the rollout to finish before testing distributed ownership. Roll back the image if introspection or queue latency regresses; do not treat increasing pods as a substitute for diagnosing hot-path CPU work.

This restoration does not change refresh-token rotation semantics or claim to make in-memory analytics buffers durable after hard node loss. PostgreSQL, ClickHouse and object storage remain the authorities for persistent state. Network partitions can duplicate regenerable display/image work.

## Local validation performed

Validation used the repository's pinned dependency versions, disposable databases, and owned local server processes. No live cluster was inspected or modified.

- Focused `mix test` run covering credentials, accounts/projects, authorization, ingestion, supervised tasks, MCP transport/events/Atlas identity, rate limits, caches and images: **1,016 passed, 2 excluded**.
- After adding the mixed-credential regression, `mix test test/tuist_web/plugs/authentication_plug_test.exs test/tuist/authentication/token_verification_cache_test.exs`: **25 passed**. Temporarily forcing a unique cache key on every lookup made the new test fail; the implementation was restored and both suites rerun successfully.
- `MIX_ENV=test mix run --no-start --no-compile verification/bcrypt_load.exs`: **2,000 requests, concurrency 64, rounds 12, one bcrypt verification, 293 ms** on the final follow-up run.
- Two full server processes with `TUIST_E2E_TOKEN_LOAD_ONLY=1` and `TUIST_E2E_TOKEN_CACHE_STRESS=1`: **8,080 authenticated HTTP requests** plus **800 successful readiness probes**, at cost 12 and concurrency 32. The basic 400-request run completed in **937 ms**, verified each credential once per replica and immediately rejected revoked credentials.
- Diverse-token phases used **128 credentials**: cold and actual TTL-expired traffic each performed **128 verifications per replica**; warm phases performed **zero**. The 2,048-request warm phase completed in **991 ms** (request p95 **32 ms**, readiness p95 **12 ms**). Restarting one replica caused **128** new verifications there and **zero** on its survivor. Pruning the other replica to one retained proof caused exactly **127** new verifications there and **zero** on its peer. All phases passed and the owned server/discovery/proxy processes were stopped. Cold proof creation remained expensive: the initial 1,024-request burst took **20.8 seconds**, with request p95 **2.7 seconds** and readiness max **3.1 seconds** on the two-scheduler local server processes.
- `verification/cluster_scale_out.exs`: address discovery, cross-node invalidation, session-free modern catalog requests, image-lock exclusion/independence and departure invalidation passed against two Erlang nodes.
- Formatting check and `git diff --check` passed. Strict Credo over the changed Elixir files reports only a pre-existing alias suggestion in `Accounts.registered_kura_endpoint_urls/1`, outside this change.
- Clustered self-hosted Helm profile linted and rendered; all **27 resources** passed schema validation. The managed production render had **144 valid resources**, with **98 custom resources skipped** for unavailable schemas and no errors. Rendering two replicas without discovery was correctly rejected.
- Actionlint passed for the server and Helm workflows after excluding existing custom-runner-label notices and an existing `SC2046` warning. The added guard steps produced no new findings.

The complete full-server image/rendering, Redis-outage and rolling-restart harness was not rerun as one combined scenario. Image behavior and shared-store failures have unit coverage; the authentication-only HTTP run and component-level cluster run do not substitute for the remaining full-server or live canary rollout checks above.
