# pomerium chart

Per-env wrapper around the upstream Pomerium chart that fronts a
workload cluster's apiserver. One Helm release per env, deployed
into each workload cluster (NOT mgmt).

## What it provides

- `https://kube-<env>.tuist.dev` — the kubectl gateway. Users dial
  this with kubectl after running through Pomerium's exec
  credential plugin to obtain a session token (Pomerium handles the
  Google OIDC dance via browser; cached for ~24h).
- `https://authenticate.kube-<env>.tuist.dev` — Pomerium's
  authenticate service, the OAuth callback URL.

## Identity flow

1. `kubectl --context tuist-k8s-<env> get pods`
2. Pomerium exec plugin presents cached session JWT
3. Pomerium validates: signed by us, not expired, email in tuist.dev domain
4. Pomerium calls ext_authz: `POST http://ops.tuist.ts.net/api/v1/policy` with the Envoy CheckRequest body containing `host`, `headers`, etc.
5. tuist-ops reads `host` to derive env, reads claim header for subject, queries Tailscale role + active elevation, returns Envoy CheckResponse with `Impersonate-User` + `Impersonate-Group` headers to inject
6. Pomerium injects headers, forwards to `https://kubernetes.default.svc:443`
7. apiserver impersonates the user with the resolved tier, RBAC binds, request succeeds or fails on RBAC

## Manual prereqs (per env)

1. **Create the Pomerium 1P item** `POMERIUM_<TUIST_ENV>` in the matching env's vault with these fields:
   - `shared_secret` (32 bytes base64): `openssl rand -base64 32`
   - `cookie_secret` (32 bytes base64): same
   - `databroker_storage_connection_string`: `postgres://...` to a small Postgres for session state (can share the env's CNPG)
   - `idp_client_id` / `idp_client_secret`: Google Workspace OIDC credentials (created via Workspace admin → APIs & Services → Credentials → OAuth client ID. Type: web. Authorised redirect URI: `https://authenticate.kube-<env>.tuist.dev/oauth2/callback`)
2. **Create the DNS records** at Cloudflare for `kube-<env>.tuist.dev` and `authenticate.kube-<env>.tuist.dev` pointing at the cluster's ingress.
3. **cert-manager** must already have a `letsencrypt` ClusterIssuer (it does — used by the existing Tuist server ingress).
4. **Tailscale operator** must already be deployed in the cluster with egress enabled (it is — used by the apiserver proxy for view-tier access today).

## Bits to verify before first deploy

The chart skeleton uses a few Pomerium config keys whose exact names depend on upstream Pomerium version. Verify against [Pomerium reference config](https://www.pomerium.com/docs/reference) for the pinned `appVersion` in `Chart.yaml`:

- The shape of `pomerium.config.routes[].policy` (PPL vs YAML PPL).
- Where to set `externalAuthorizationURI` (or equivalent) — likely under `pomerium.config.ext_authz_provider` or similar global key.
- The exact env var names Pomerium reads for the IdP client id/secret when not in config (the chart may pass them via env, not config).

These three settings are the only Pomerium-specific risk in the chart; the rest is standard Kubernetes wiring (Ingress, Service, ExternalSecret).

## Deploy

```bash
helm dep update infra/helm/pomerium
helm upgrade --install pomerium-kube infra/helm/pomerium \
  -n pomerium --create-namespace \
  -f infra/helm/pomerium/values-staging.yaml \
  --kube-context tuist-k8s-staging
```

Repeat for canary and production once the staging deploy is proven.
