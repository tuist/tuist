# Kubernetes impersonation sidecar

Pomerium authenticates kubectl users; this sidecar asks tuist-ops for the current
impersonation tier, then proxies to the Kubernetes API with that identity and the
pod's service-account bearer. Read `infra/AGENTS.md` before cluster operations.

## Security contracts

- Trust identity from Pomerium's `X-Pomerium-Claim-Email`, not caller-selected
  impersonation headers. Resolve policy on every request through `/api/v1/policy`.
- Default tiers are read-only: Owner/Admin → `tuist-admins`, Member → `tuist-eng`.
  Canary/production require an active elevation for `tuist-<env>-write`; staging
  always adds `tuist-staging-write` and is outside the elevation flow.
- Fail closed with `502` if policy is unreachable or non-200. Never forward as
  the pod's service account without an impersonation decision.
- Preserve cluster CA verification and periodic service-account token reloads;
  projected tokens rotate. Environment defaults are defined in `main.go`.

## Orb listener (`orb.go`)

Amp orbs reach the API server at `kube-orb-<env>.tuist.dev`, which ingress-nginx
routes straight to `ORB_LISTEN_ADDR`, bypassing Pomerium. The listener is on the
pod IP, so the bearer is the only authentication:

- Verify the Amp workload identity token (RS256 only, issuer, exact audience
  `https://kube-orb-<env>.tuist.dev`, expiry, lifetime ≤ 15 min). Require
  `ORB_WORKSPACE_ID` and `ORB_PROJECT_ID`: Amp's audience is not secret, any
  workspace's orb can mint it, and every orb in our workspace can too, including
  personal projects. Require `token_use=exchanged`, a `thread_id`, `user_id` and
  verified `email`; project-setup tokens get nothing.
- Derive the policy Host (and so the env) from the verified audience, never
  from the request: in-cluster callers choose their own Host.
- JWKS refetches run at most once a minute, on a detached context, outside the
  cache lock; unknown-kid floods must not block cached-key verification.
- Send tuist-ops only the verified `X-Tuist-Amp-Email`/`-Thread-Id`; never
  forward client headers. The Pomerium listener must not forward those headers,
  and tuist-ops reads each door's headers only on that door's hosts.
- The orb token never reaches the apiserver. Each request logs one line with
  email, thread, groups and status, since Pomerium's access log does not see it.

Staging primarily uses Tailscale's API server proxy and ACL impersonation, not
this sidecar. Its `kube-staging.tuist.dev` off-tailnet fallback still uses this
policy path; keep it working. See `infra/helm/tailscale-operator/values-staging.yaml`.

Build locally from `kube-impersonator/` with `go build ./...`.
`.github/workflows/pomerium-deployment.yml` builds/deploys this sidecar together
with Pomerium. The image tag must be passed explicitly through
`kubeImpersonator.image.tag`; do not commit a fallback tag into chart defaults.
