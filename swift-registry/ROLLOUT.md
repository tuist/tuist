# swift-registry rollout plan

This document covers how the new `swift-registry` Phoenix service is brought
online next to the existing cache-served registry, and how registry traffic is
later migrated. The PR that introduces the service intentionally stands it up
in parallel with cache; **no client-facing traffic moves until follow-up PRs.**

## Scope of this PR

Lands the new service as a standalone Phoenix release plus Helm chart and
deploy workflows. Cache continues to serve `registry.tuist.dev/*` and
`tuist.dev/api/registry/*` exactly as today (the legacy Cloudflare Worker, the
cache controller routes, and the cache Oban registry queues are all unchanged
on this branch).

Specifically, **this PR does NOT**:

- change the Cloudflare Worker in `infra/registry-router/`,
- remove the registry routes/workers from `cache/`,
- change the host the CLI writes into generated `registries.json` files,
- change the example workspaces under `examples/xcode/`,
- update marketing copy that mentions registry hosts.

All of those happen in subsequent PRs, after the new service is verified at
each stage below.

## Stages

### 1. Land this PR

After merge, the canary and production deploy jobs in
`.github/workflows/swift-registry-deploy.yml` pick up changes under
`swift-registry/**` and `tuist_common/**`. The cascade is canary → production
(gated on canary success). The chart deploys behind ingress on
`swift-registry-canary.tuist.dev` and `swift-registry.tuist.dev`, neither of
which any client currently resolves through.

Prereqs (cluster-side, not in this PR):

- `SWIFT_REGISTRY` 1Password item exists in `tuist-k8s-canary` and
  `tuist-k8s-production` vaults with these fields, sourced from cache's
  existing flat items so the new service reuses the same Tigris bucket and
  GitHub token:

      S3_REGISTRY_BUCKET, S3_HOST, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY,
      S3_REGION, TUIST_SWIFT_REGISTRY_API_KEY (= TUIST_CACHE_API_KEY),
      REGISTRY_GITHUB_TOKEN

- `kubeconfig: tuist-canary` / `kubeconfig: tuist-production` items exist in
  the same vaults (already present, used by every other k8s service).
- `server-k8s-canary` / `server-k8s-production` GitHub Environments exist with
  the org's 1Password OIDC wiring (already present).
- DNS A/AAAA records for `swift-registry-canary.tuist.dev` and
  `swift-registry.tuist.dev` point at the canary and production cluster
  ingress respectively.
- ExternalSecrets Operator + cert-manager are installed (already used by every
  other k8s service).

### 2. Stage 1 verification — canary

Smoke-test against `swift-registry-canary.tuist.dev` directly:

- `curl -fsS https://swift-registry-canary.tuist.dev/up` → 200
- `curl -fsS -H 'Accept: application/vnd.swift.registry.v1+json' \
    https://swift-registry-canary.tuist.dev/availability` → 200
- Metadata fetch:
  `https://swift-registry-canary.tuist.dev/apple/swift-argument-parser` →
  200 with `Content-Version: 1` and a JSON list of releases.
- Manifest fetch:
  `https://swift-registry-canary.tuist.dev/apple/swift-argument-parser/1.0.0/Package.swift`
  → 200 with `text/x-swift` body served via nginx `/internal/local` from the
  pod PVC (cold cache will populate from S3 first).
- Source archive download:
  `https://swift-registry-canary.tuist.dev/apple/swift-argument-parser/1.0.0.zip`
  → 200 with archive bytes (the X-Accel-Redirect handoff to nginx
  `/internal/local` or `/internal/remote`).
- Alternate manifest `Link` header preserved on `Package.swift` responses
  when the package ships `Package@swift-X.Y.swift` variants.
- Operator scripts:
  - `mise run swift-registry:sync apple/swift-argument-parser 1.4.0 \
      --namespace swift-registry --context tuist-canary` → enqueues an Oban
    job; verify completion via Oban logs or `Oban.Job` query.
  - `mise run swift-registry:purge apple/swift-argument-parser 1.4.0 \
      --namespace swift-registry --context tuist-canary` → removes the
    version from S3 and from every running pod's `/storage` PVC.

### 3. Switch canary traffic

After Stage 2 passes, do the canary traffic flip in a follow-up PR:

- Update the Cloudflare Worker in `infra/registry-router/` to proxy
  `registry-canary.tuist.dev/*` and `canary.tuist.dev/api/registry/*` to
  `swift-registry-canary.tuist.dev` (or remove the canary host from the
  geo-router so it falls through to the new service).
- `wrangler deploy` from `infra/registry-router/`.
- Watch error rates and download latency on
  `swift-registry-canary.tuist.dev` for ≥24h.

Rollback: revert the worker change and `wrangler deploy` again. Cache's
canary registry routes still exist and resume serving immediately.

### 4. Switch production traffic

Same shape, against production hosts:

- Update the Worker to proxy `registry.tuist.dev/*` and
  `tuist.dev/api/registry/*` to `swift-registry.tuist.dev`.
- `wrangler deploy`.
- Watch ≥48h.

Rollback: same — revert worker change. Cache routes remain in place.

### 5. Decommission cache registry surface

Only after Stage 4 is stable, in a separate PR:

- Remove the registry pipeline + scope from `cache/lib/cache_web/router.ex`.
- Remove `cache/lib/cache/registry/*`, the `registry_sync` /
  `registry_release` Oban queues, and the `registry_*` config from
  `cache/config/{config,runtime}.exs` / `cache/.kamal/secrets.*`.
- Remove the `infra/helm/tuist/templates/registry-cache-*.yaml` chart
  templates if cache adoption of those k8s manifests is also being dropped.

### 6. Switch CLI clients

Independent of stages 3–5, once `swift-registry.tuist.dev` is stable:

- Re-introduce the `cli/Sources/TuistConstants/Constants.swift` helper that
  returns `swift-registry.tuist.dev` and the associated
  `RegistryConfigurationGenerator` / `RegistryLoginCommandService` /
  `RegistrySetupCommandService` changes (these were intentionally reverted
  on this branch).
- Re-introduce the updated checked-in `.swiftpm/configuration/registries.json`
  in `examples/xcode/...` and the marketing blog post hostname change.
- Ship in the next CLI release. Older CLIs continue working via the worker
  proxy.

## Staging

Staging (`swift-registry-staging.tuist.dev`,
`.github/workflows/swift-registry-staging-deploy.yml`) is wired in the chart
but its `SWIFT_REGISTRY` 1Password item is not provisioned yet — cache itself
runs staging without a real registry bucket
(`cache/.kamal/secrets.staging` leaves `S3_REGISTRY_BUCKET` blank). To bring
staging online, create the staging `SWIFT_REGISTRY` item either pointing at
the canary bucket (lightweight, shares data) or a dedicated staging Tigris
bucket (clean separation, requires Tigris provisioning), then trigger
`Swift Registry Staging Deploy` from the Actions tab against the desired SHA.

## Rollback safety summary

Because cache keeps serving the registry surface for the entire rollout and
the Cloudflare Worker is the single traffic switch, any stage above can be
reverted by re-deploying the previous Worker config. Removing cache's
registry code (Stage 5) is the only one-way step and is deferred to its own
PR after weeks of stable swift-registry traffic.
