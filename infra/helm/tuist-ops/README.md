# tuist-ops chart

Deploys the `tuist-ops` Phoenix app + its CNPG Postgres + the ESO
ExternalSecrets that feed them. Single deploy, targeted at the mgmt
cluster only — internal ops tooling has no business running in the
workload clusters it manages.

## What's in the box

- **Deployment** — single-replica `ghcr.io/tuist/tuist-ops:<tag>` pod
  with `Recreate` strategy. Reads runtime credentials from the ESO-
  synced `*-runtime` Secret + DATABASE_URL from CNPG's `*-app` Secret.
- **Service** — ClusterIP + `tailscale.com/expose: true` annotation
  so Pomerium pods in workload clusters can reach it on the tailnet
  as `ops.<tailnet>.ts.net`.
- **Ingress** — public ingress on `ops.tuist.dev`, **only routing
  `/webhooks/slack/*`**. The Pomerium ext_authz endpoint
  (`/api/v1/policy`) and any future LiveView paths (`/db`, etc.) are
  reachable only on the tailnet, never publicly.
- **CNPG Cluster** — single-instance Postgres, 5Gi storage, daily
  backups to Tigris under `s3://tuist-cnpg-backups/tuist-ops`.
- **ExternalSecrets** — three of them:
  - `tuist-ops-runtime` — Slack + Tailscale credentials from `TUIST_OPS_BOT`
  - `tuist-ops-app`     — `SECRET_KEY_BASE` from the same 1P item
  - `tuist-ops-backup-credentials` — Tigris keys from the shared `S3_BACKUP_CREDENTIALS`

## Manual prereqs (do these before first deploy)

1. **Create `TUIST_OPS_BOT` 1P item** in the mgmt vault with fields:
   - `tailscale_client_id`, `tailscale_client_secret`, `tailscale_tailnet`
   - `slack_signing_secret`, `slack_bot_token`, `slack_approvals_channel_id`
   - `secret_key_base` — generate via `mix phx.gen.secret`
2. **Update the Slack app**'s slash command URL to
   `https://ops.tuist.dev/webhooks/slack/slash` and the interactivity
   request URL to `https://ops.tuist.dev/webhooks/slack/interactive`.
   The bot token and signing secret stay the same as the prior
   TAILSCALE_JIT_BOT item — same Slack app, just a different host.
3. **Create the Tailscale OAuth client** with `users:read` scope (only).
   The previous client (which had `policy_file:write`) can be deleted
   since the ACL is no longer mutated at runtime.
4. **Cloudflare DNS** — A/AAAA record for `ops.tuist.dev` pointing at
   the mgmt cluster's ingress-nginx external IP.
5. **Tailscale operator** in the mgmt cluster must be running with
   the cluster egress feature enabled (it is — same operator as the
   workload clusters).
6. **CloudNativePG operator** in mgmt (it's already there for any
   other CNPG cluster in mgmt, or install via the platform chart).

## Image build

Built and pushed by `.github/workflows/tuist-ops.yml` on every push to
`main` (and on `workflow_dispatch`). Two tags per build:
- `ghcr.io/tuist/tuist-ops:sha-<first-12-of-commit>`
- `ghcr.io/tuist/tuist-ops:latest`

Prefer the SHA tag for deploys so rollbacks are precise.

## Deploy

```bash
helm upgrade --install tuist-ops infra/helm/tuist-ops \
  -n tuist-ops --create-namespace \
  -f infra/helm/tuist-ops/values-managed-mgmt.yaml \
  --set image.tag=sha-$(git rev-parse HEAD | cut -c1-12) \
  --kube-context tuist-mgmt
```

A dedicated `tuist-ops-deployment.yml` workflow (mirroring
`slack-deployment.yml`) for automated `helm upgrade --install` on
push-to-main is a follow-up; for the first deploy and any rollbacks
the manual command above is the path.
