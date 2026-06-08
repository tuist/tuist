# tuist-ops (Elixir/Phoenix)

Internal-tooling Phoenix app for Tuist team operations. Lives in the
production cluster (alongside `server/` and `slack/` — matches the
"internal Tuist-team tooling lives in the same cluster as customer
workload" pattern), in its own namespace, with its own Helm release,
own ESO secrets, and own CNPG Postgres. Decoupled at every layer
except the cluster itself.

Reached at `https://ops.tuist.dev` (public, Slack-only routes) and
`http://ops.<tailnet>.ts.net` (on-tailnet, internal callers like
Pomerium).

## What lives here

**JIT elevation Slack bot + Pomerium ext_authz endpoint** (current):
- `lib/tuist_ops/jit/` — core business logic
  - `approvals.ex` — state machine for Request → Elevation
  - `elevation.ex`, `request.ex` — Ecto schemas
  - `policy.ex` — role-based self-approve + approver-allowed gates
  - `slack_blocks.ex`, `slack_client.ex` — Slack Block Kit + HTTP client
  - `tailscale_client.ex` — Tailscale users API (role lookup, cached 30s)
  - `workers/revert_worker.ex` — Oban job that marks elevation reverted at TTL
- `lib/tuist_ops_web/controllers/slack_controller.ex` — Slack slash + interactive endpoints (`/webhooks/slack/*`)
- `lib/tuist_ops_web/controllers/policy_controller.ex` — Pomerium ext_authz endpoint (`/api/v1/policy`)

**Planned migrations from `server/`** (not yet moved, structure ready to receive):
- `/ops/db` LiveView (read-only Postgres inspection) — will land as
  `lib/tuist_ops_web/live/database_live.ex` plus any business-logic
  modules under `lib/tuist_ops/database/`.
- Any other `/ops/*` feature added in the future.

When a new ops feature lands, the pattern is:
- Business logic under `lib/tuist_ops/<feature>/`
- Web surface under `lib/tuist_ops_web/{controllers,live}/`
- Tests under `test/<feature>/`

Top-level modules (`Application`, `Repo`, `Environment`, the web
endpoint and router) stay shared across features.

## Routing convention

Routes are mounted at root, never under `/ops`. The `/ops` prefix
that exists today at `tuist.dev/ops/db` is the legacy form;
`ops.tuist.dev` makes the subdomain the prefix and the URL path
drops to `/db`. So a new feature exposed at `ops.tuist.dev/incidents`
lives at `lib/tuist_ops_web/live/incidents_live.ex` with router
entry `live "/incidents"`, NOT `live "/ops/incidents"`. The
canonical URL form is `ops.tuist.dev/<feature>`; a redirect at
`tuist.dev/ops/<feature>` → `ops.tuist.dev/<feature>` may live on
the `server/` side during migration windows.

## Stack
- Phoenix 1.7 (no LiveView yet — adds when the first `/ops/*` page
  migrates from `server/`)
- Postgres via its own CNPG cluster in the production cluster (same operator the main server uses)
- Oban for the timed revert worker

## Runtime behavior
- Single instance, deployed only to the production cluster (own Helm
  release, own namespace, own DB — co-located with the customer
  workload but isolated at every layer above the cluster).
- Migrations run on boot unless `SKIP_MIGRATIONS=true`.

## Identity boundary
- Pomerium authenticates humans to ops surfaces via Google Workspace
  OIDC, NOT via Tuist's customer OIDC IdP. Slack and Tailscale are the
  only external identity surfaces this app talks to.
- The `server/` app has zero knowledge of internal cluster access or
  any other ops tooling that ends up here. Customer-facing failures
  don't take down ops; ops failures don't take down customer-facing.
