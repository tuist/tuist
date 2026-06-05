# tuist-jit (Elixir/Phoenix)

Small Phoenix app that implements just-in-time elevation for `kubectl` access
to Tuist's Kubernetes clusters. Deliberately decoupled from the customer-facing
`server/` so an outage of one does not affect the other.

## What it does

1. **Receives Slack webhooks.** Two endpoints, both Slack-signed:
   - `/webhooks/slack/slash` — receives `/elevate <env> [duration] <intent>`.
     Creates a `Request` row and posts an approval card to a Slack channel.
   - `/webhooks/slack/interactive` — receives Approve/Deny/Revoke button
     callbacks. Gates approval against the actor's tailnet role (queried via
     `GET /api/v2/tailnet/-/users`), writes an `Elevation` row on Approve, and
     schedules a `RevertWorker` Oban job for TTL.
2. **Serves Pomerium's ext_authz endpoint.** `/api/v1/policy` returns the
   impersonation headers (`Impersonate-User`, `Impersonate-Group`) Pomerium
   should inject for a given (subject, env). Reads the elevation rows this
   same app wrote, plus the tailnet role, to derive the right tier per call.

## Stack
- Phoenix 1.7 (no LiveView, no HTML — webhooks + JSON API only)
- Postgres (own CNPG cluster in `tuist-mgmt`)
- Oban for the timed revert worker

## Layout
- `lib/tuist_jit/` — core business logic
  - `approvals.ex` — state machine for Request → Elevation
  - `elevation.ex`, `request.ex` — Ecto schemas
  - `policy.ex` — role-based self-approve + approver-allowed gates
  - `slack_blocks.ex`, `slack_client.ex` — Slack Block Kit + HTTP client
  - `tailscale_client.ex` — Tailscale users API (role lookup, cached 30s)
  - `workers/revert_worker.ex` — Oban job that marks elevation reverted at TTL
- `lib/tuist_jit_web/` — HTTP surface
  - `controllers/slack_controller.ex` — slash + interactive endpoints
  - `controllers/policy_controller.ex` — Pomerium ext_authz endpoint
  - `plugs/slack_webhook_plug.ex` — Slack signature verification
- `priv/repo/migrations/` — Ecto migrations for `tailscale_jit_requests` and
  `tailscale_jit_elevations`

## Runtime behavior
- Single instance per environment (no need for multi-replica — load is a
  handful of requests per day).
- Migrations run on boot unless `SKIP_MIGRATIONS=true`.
- Lives in the `tuist-mgmt` cluster, not in any workload cluster. JIT for a
  workload cluster shouldn't depend on the workload cluster being healthy.

## Identity boundary
- Pomerium authenticates users via Google Workspace OIDC, NOT via Tuist's
  customer OIDC IdP. Slack and Tailscale are the only external identity
  surfaces this app talks to. The `tuist/` server has zero involvement in
  internal cluster access.
