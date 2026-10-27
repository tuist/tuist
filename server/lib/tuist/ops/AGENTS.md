# Ops (Context)

This context owns ops reporting workers and the internal feature-flag control API.

## Responsibilities
- Schedule Slack reports for daily/hourly business metrics.
- The hourly sign-up report posts new users and organizations to `#gtm` every day, including weekends. Slack API failures must propagate to Oban for retries.
- Each sign-up report covers the completed UTC hour preceding the job's immutable `inserted_at`, with inclusive start and exclusive end. Never derive its window from retry time or `scheduled_at`. Slack digests show at most 20 accounts with bounded lines and an omitted count so large batches cannot exceed Slack's section-text limit.
- Internal reports authenticate with `TUIST_SLACK_TUIST_TOKEN`, sourced by ESO from `SLACK/tuist_token` in the per-environment `tuist-k8s-<env>` 1Password vault. An `account_inactive` response requires restoring the Slack identity or replacing that credential; code retries cannot repair it. After a secret replacement, ESO must sync and the server pods must reload their environment before validating `auth.test` and channel delivery.
- Query growth stats for users, orgs, projects, and command events.
- Provide bounded, read-only ClickHouse queries and schema discovery for internal operations consumers.
- `FeatureFlags` exposes only its explicit catalog through Atlas workload-authenticated routes. Atlas must authorize dedicated `feature_flags:read/write` scopes and derive the human actor and interface from its authenticated execution context. Customer API credentials cannot use these routes. Shared-identity Slack agents are denied by Atlas, and server writes accept only the `mcp`, `worker` and `api` interfaces.
- Resource evaluation accepts exactly one positive Tuist account/project ID. Resolve a project's owning account in the same query, then batch only applicable shared rules and those actors' overrides. Pass the resulting flag map through the actual feature/identity helpers without touching FunWithFlags' evaluation cache; do not duplicate environment defaults, dependencies or kill-switch inversion in the ops layer. The query budget is two core reads plus at most two rename-eligibility existence checks. Return the serving environment, source flag and effective feature explicitly; these decisions are neither historical exposure nor proof of sticky controller activation or cache convergence. Keep the scoped observability context isolated from the caller.
- Mutations require a current revision, reason and change UUID. Serialize gate writes in PostgreSQL and persist the request, workload principal and before/after state atomically. Identical retries return the original result; conflicting UUID reuse and stale revisions return 409. Publish cache invalidation only after commit. Acquire FunWithFlags' per-flag percentage advisory transaction lock before the table lock, including for clears/resets. This serializes the legacy adapter's entire percentage read-modify-write without reversing its lock order. Advisory/table lock timeouts return `persistence_failed` (503) after rollback; unexpected database errors must still raise. Reject account/project IDs above PostgreSQL int8's maximum before querying and percentages whose normalized ratio underflows to zero before constructing a gate.
- Rollout uses FunWithFlags 1.13's deterministic percentage-of-actors gate, not percentage-of-time. Set a percentage strictly between 0 and 100; explicit actor exclusions retain precedence. Global disable preserves actor/percentage gates; scoped clear restores inheritance. `clear/all` removes every gate, but is not universal feature-off: enabling a kill switch stops its feature, and environment defaults/dependencies can override ordinary gates. Read the catalog description before choosing a rollback.
- Control reads return persisted rules, not a promise of every replica's current decision. PubSub invalidation is best effort and evaluation cache TTL is 600 seconds; storage failures can retain stale cache values. Correlate observed evaluations with target account/project and release, never infer exposure from today's configuration. No automatic health scheduler or correlation-based rollback policy is installed by these tools. A monitored ramp requires explicit baseline/window/minimum exposure and rollback criteria before an agent writes; an error sample alone is not an error rate or causal proof.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.
- Internal ClickHouse inspection uses its own repository and dedicated read-only credentials.
- `Tuist.Release.migrate` reconciles the dedicated ClickHouse user, role, grants, password, and limits before managed rollouts.

## Guardrails
- If changes add or modify stored customer data, update `server/data-export.md`.
- Preserve the ClickHouse query limits and keep external table functions, cluster table functions, and unrestricted system metadata inaccessible.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`

- `runner_linux_vrack` is an account-scoped, default-off dispatch flag. Initial rollout enrolls only Tuist after host cohort isolation; disabling affects new dispatch and does not remove routes or terminate recorded jobs.
