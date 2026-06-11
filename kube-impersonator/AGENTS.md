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
| `CA_CERT_FILE` | `/var/run/secrets/kubernetes.io/serviceaccount/ca.crt` | trusted cluster CA for upstream TLS |
| `POLICY_URL` | `http://tuist-ops-egress/api/v1/policy` | tailnet egress to ops |
| `POLICY_TIMEOUT_MS` | `5000` | per-request budget for the policy call |
| `REFRESH_TTL_SEC` | `300` | SA token re-read interval (projected tokens rotate) |

## Build / deploy

Built and deployed by `.github/workflows/pomerium-deployment.yml`
in one shot (same shape as `tuist-ops-deployment.yml`): the
`build-impersonator` job pushes
`ghcr.io/tuist/kube-impersonator:sha-<DEPLOY_SHA:0:12>`, and the
`deploy` job passes that tag to helm via
`--set kubeImpersonator.image.tag=...`. No tag committed in
`infra/helm/pomerium/values.yaml` — chart default is `""` and
the deploy fails fast if `--set` is missing.

A `workflow_dispatch` input lets you pre-build the image
elsewhere and skip the build job (`image_tag: sha-XYZ`).
