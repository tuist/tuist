# kube-impersonator

Sidecar deployed alongside Pomerium in each workload cluster's
`pomerium` namespace. Pomerium handles the OIDC dance; this
sidecar handles the per-request impersonation header injection
based on tuist-ops's policy decision.

## Why

Pomerium fronts kubectl at `kube-<env>.tuist.dev` and authenticates
humans via Google Workspace OIDC. The apiserver needs
`Impersonate-User` + `Impersonate-Group` headers on every request
to map the human to a Kubernetes RBAC tier. Pomerium can set
**static** request headers per route, but the impersonation tier
must be **dynamic**:

- Owner / Admin tailnet role → `tuist-admins` (view)
- Member → `tuist-eng` (view)
- Any of the above with an active elevation row in
  tuist-ops's `tailscale_jit_elevations` table → add
  `tuist-<env>-write` (edit)

tuist-ops's PolicyController makes that decision per request. This
sidecar is the glue: receives every request from Pomerium, calls
PolicyController, injects the headers, forwards to the apiserver.

## Architecture

```
kubectl → ingress-nginx (TLS terminate)
       → Pomerium :8080 (OIDC, sets X-Pomerium-Claim-Email)
       → kube-impersonator 127.0.0.1:8081
            ├─ GET tuist-ops-egress/api/v1/policy
            │     Host: kube-<env>.tuist.dev
            │     X-Pomerium-Claim-Email: marek@tuist.dev
            │   → 200 OK
            │     Impersonate-User: marek@tuist.dev
            │     Impersonate-Group: tuist-admins
            │     Impersonate-Group: tuist-staging-write   (if elevated)
            └─ adds Authorization: Bearer <SA token>
       → https://kubernetes.default.svc:443
```

## Failure mode

Closed. If PolicyController is unreachable or returns non-200, the
sidecar returns 502 to kubectl. Better to interrupt kubectl access
than forward to the apiserver with no impersonation decision (which
would either error out as Pomerium's SA, or worse, silently
escalate).

## Config (env)

| var | default | purpose |
|-----|---------|---------|
| `LISTEN_ADDR` | `:8081` | local Pomerium dials this |
| `APISERVER_URL` | `https://kubernetes.default.svc:443` | upstream |
| `SA_TOKEN_FILE` | `/var/run/secrets/kubernetes.io/serviceaccount/token` | k8s automount |
| `POLICY_URL` | `http://tuist-ops-egress/api/v1/policy` | tailnet egress to ops |
| `POLICY_TIMEOUT_MS` | `5000` | per-request budget for the policy call |
| `REFRESH_TTL_SEC` | `300` | SA token re-read interval (projected tokens rotate) |

## Build / deploy

Image is built and pushed to `ghcr.io/tuist/kube-impersonator` by
`.github/workflows/kube-impersonator-image.yml` on every push that
touches this directory. Pomerium chart references the tag via
`kubeImpersonator.image.tag` in `infra/helm/pomerium/values.yaml`.
