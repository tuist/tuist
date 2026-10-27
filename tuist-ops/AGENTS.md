# Internal operations

Standalone Phoenix app for JIT cluster elevation, operator project-access grants,
and Slack-requested previews. It has its own production namespace, Helm release,
secrets, and CNPG database, independent of the customer server.

## Boundaries and security

- Business logic lives under `lib/tuist_ops/<feature>/`, web surfaces under
  `lib/tuist_ops_web/`. Mount routes at the subdomain root (`/db`, not `/ops/db`).
- Pomerium/Google Workspace authenticates human ops access, not the customer's
  Tuist OIDC provider. `X-Pomerium-Claim-Email` is spoofable on raw ingress:
  `/grants/*` must remain Pomerium-fronted.
- Public `ops.tuist.dev` ingress exposes only Slack-signed webhook routes.
  `/api/v1/policy` and other internal surfaces are tailnet-only.
- Canary/production cluster access defaults to `view`; staging's write tier is
  standing access and `/elevate staging` is rejected. Read `infra/AGENTS.md` for the human-only
  `/elevate` request/approval flow; agents must never request or approve elevation.
- Keep role decisions in `JIT.Policy`, using tailnet roles from
  `JIT.TailscaleClient`, not email allowlists.
- `/elevate-github <login> [duration] <intent>` uses the same human approval flow,
  but changes live organization membership. Elevate only active `member`s, never
  existing admins or non-members. `RevertWorker` must demote back to `member`,
  retry failures, and surface `revert_failed` on Slack; that job enforces expiry.
  The GitHub App needs organization Members read/write permission.
- Project-access read grants are self-serve with a reason; admin grants require
  Slack approval. The customer server verifies signed Ed25519 grants offline.
  See `infra/k8s/operator-project-access-audit.md` for the audit/deployment runbook.
- Previews record their audit trail here but mutate Kubernetes through
  `.github/workflows/preview-deploy.yml`; do not add workload-cluster credentials
  to this app. Keep workflow outcome reporting on the originating Slack card.
- Migrations run on boot unless `SKIP_MIGRATIONS=true`.

Tool versions live in `mise.toml`; use `mix test` for tests. Deployment is defined
by `infra/helm/tuist-ops/` and `.github/workflows/tuist-ops-deployment.yml`.
