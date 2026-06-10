# pomerium chart

Self-contained chart (not a wrapper) deploying Pomerium in
all-in-one mode plus the `kube-impersonator` sidecar as the
per-env kubectl gateway. One Helm release per workload env
(staging / canary / production), deployed into that cluster.

## What it provides

- `https://kube-<env>.tuist.dev` — kubectl gateway. Users dial
  this via `pomerium-cli k8s exec-credential` registered as a
  kubeconfig exec plugin; on first call the plugin opens a
  browser for Google OIDC and caches the session for ~24h.
- `https://authenticate.kube-<env>.tuist.dev` — Pomerium's
  authenticate service (OAuth callback target).
- ClusterRoleBindings for `tuist-admins` / `tuist-eng` /
  `tuist-<env>-write` → `view` / `view` / `edit` respectively
  (`templates/access-tiers.yaml`).

## Identity flow

1. `kubectl --context kube-<env>.tuist.dev get pods`
2. `pomerium-cli` injects the cached Pomerium session JWT as a Bearer.
3. Pomerium validates the session (signed by us, not expired,
   email in `tuist.dev`).
4. Pomerium's route forwards to the `kube-impersonator` sidecar
   on `127.0.0.1:8081`. `pass_identity_headers: true` +
   `jwt_claims_headers: { X-Pomerium-Claim-Email: email }`
   attach the user's email.
5. Sidecar issues `GET http://tuist-ops-egress/api/v1/policy`
   over the tailnet (the egress Service is operator-managed,
   proxying to `ops.<tailnet>.ts.net`).
6. tuist-ops reads `host` to derive the env + the claim header
   to identify the user, checks `(subject, env)` against the
   active elevation row, returns HTTP 200 + `Impersonate-User`
   + one-or-more `Impersonate-Group` response headers.
7. Sidecar strips the inbound bearer, attaches the pod
   ServiceAccount token, copies the policy headers onto the
   request, forwards to `https://kubernetes.default.svc:443`.
8. apiserver impersonates, RBAC binds the group(s) to the right
   ClusterRole (view / edit), request succeeds or fails on
   that authorisation.

## Manual prereqs (per env)

1. **Create the Pomerium 1P item** `POMERIUM_<TUIST_ENV>` in the
   matching env's vault with:
   - `shared_secret` (32 bytes base64): `openssl rand -base64 32`
     — Pomerium's internal RPC signing key (not the databroker
     store).
   - `cookie_secret` (32 bytes base64): same generator.
   - `idp_client_id` / `idp_client_secret`: Google Workspace
     OIDC credentials. Today **one shared OAuth client covers
     all three envs** (intentional simplification at our scale):
     the same client_id / client_secret live in
     `POMERIUM_STAGING`, `POMERIUM_CANARY`, and
     `POMERIUM_PRODUCTION`. The client's "Authorized redirect
     URIs" list must include all three env hosts:
       - `https://authenticate.kube-staging.tuist.dev/oauth2/callback`
       - `https://authenticate.kube-canary.tuist.dev/oauth2/callback`
       - `https://authenticate.kube-prod.tuist.dev/oauth2/callback`
     Trade-off: a leaked credential affects all envs, not one.
     When the team grows, split into three per-env clients to
     match the rest of the design's per-env credential
     isolation (separate Tailscale OAuth clients, separate 1P
     vaults, etc.).

   Databroker is memory-backed (single replica, sessions
   invalidate on pod restart and users re-auth — acceptable at
   our scale). No connection string needed.

2. **DNS** for `kube-<env>.tuist.dev` and
   `authenticate.kube-<env>.tuist.dev` is created automatically
   by `external-dns` from the chart's Ingress hosts.

3. **cert-manager** must already have a
   `letsencrypt-cloudflare` ClusterIssuer (it does — used by
   the existing Tuist server ingress).

4. **Tailscale operator** must already be deployed in the
   cluster with the `tuist-ops-egress` ExternalName Service
   path working — that's what the sidecar dials.

## Deploy

```bash
helm upgrade --install pomerium-kube infra/helm/pomerium \
  -n pomerium --create-namespace \
  -f infra/helm/pomerium/values-staging.yaml \
  --kube-context tuist-k8s-staging
```

Repeat for canary + production once staging is proven. The
deployment workflow at `.github/workflows/pomerium-deployment.yml`
wraps this with the 1P kubeconfig fetch + per-env matrix.
