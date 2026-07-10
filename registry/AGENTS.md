# Tuist Registry Service

This directory contains the standalone Tuist package registry service
deployed at `https://registry.tuist.dev`. **The pod is a stateless read
frontend.** All write/sync work lives in the server under
`Tuist.Registry.Swift.*` and runs in a separate `TUIST_MODE=swift_registry_sync`
pod (see `server/AGENTS.md` and
`infra/helm/tuist/templates/swift-registry-sync-deployment.yaml`).

The service is multi-ecosystem by design: each ecosystem mounts its own
protocol-compliant API surface under a path prefix that names the
ecosystem. Today the only ecosystem is the **Swift Package Registry**
(SwiftPM, SE-0292), reachable at `/swift/*`.

The same Swift surface is also served under the legacy
`/api/registry/swift/*` prefix that cache exposed before the registry
was extracted, so existing clients keep working through the cutover.
Responses on the legacy prefix carry RFC 8594 `Deprecation: true` and
`Sunset` headers; the canonical `/swift/*` prefix does not.

## Responsibilities
- Serve the per-ecosystem read API (currently `/swift/*` and the legacy
  `/api/registry/swift/*`).
- Read package metadata from S3 (`registry/metadata/<scope>/<name>/index.json`).
- Emit 303 redirects to presigned S3 URLs for source archives.
- Serve manifest bodies in-process. Default `Package.swift` responses
  also include the `Link` header listing alternate manifests.
- Emit per-ecosystem download/manifest metrics via PromEx, scraped by
  the in-cluster Alloy receiver.

## Non-responsibilities
- **No DB.** No Postgres, no SQLite, no Ecto repo, no Oban journal.
- **No sync.** The pod does not fetch from GitHub, does not write to S3.
  Both happen in the server's `swift-registry-sync` mode.
- **No disk cache.** Hot reads are served from `Cachex` (in-memory,
  ETag-revalidated). Bytes the pod doesn't already have go through to
  Tigris, and Cloudflare in front absorbs repeat reads at the edge.

## Serving model
- **Source archives** are served as `303` redirects to presigned Tigris
  URLs. SE-0292 §4.4 explicitly permits this shape for signed archive
  URLs.
- **Default `Package.swift`** is loaded from Tigris into memory and
  served in-process with an alternate-manifest `Link` header attached.
- **Version-specific manifests** are also loaded from Tigris and served
  in-process so every manifest response keeps registry headers under
  the registry origin.
- **Metadata reads** (`list_releases`, `show_release`) return small
  JSON bodies loaded from Tigris.

## Code layout
- `lib/tuist_registry/` — read-side plumbing (S3 client, Config, PromEx).
- `lib/tuist_registry/swift/` — Swift Package Registry read surface
  (`Metadata`, `AlternateManifests`). `Metadata` owns the read-side
  cache and object-storage calls only.
- The S3 key layout (`KeyNormalizer`), Git URL parsing (`RepositoryURL`),
  and metadata contract (`Metadata`) live in
  `tuist_common/lib/tuist_common/registry/swift/` and are consumed by
  both this pod and the server's `swift_registry_sync` mode, so drift
  there is impossible by construction.
- `lib/tuist_registry_web/` — generic web layer (`UpController`,
  `Endpoint`, `Router`, error views).
- `lib/tuist_registry_web/controllers/swift/` — Swift Package Registry
  controller (`TuistRegistryWeb.Swift.RegistryController`).

## Development
- Install dependencies with `mise run install`.
- Run tests with `mise run test`. Tests don't need a database.
- Run formatting with `mise run format` or `mise run format --check`.
- Run Credo with `mise run credo`.

## Deployment
- The production host is `registry.tuist.dev`.
- The managed deployment is Kubernetes-based via the `registry` component in
  `infra/helm/tuist`.
- It runs in the same Helm release and namespace as the server for each
  environment, so the read frontend and `swift_registry_sync` writer roll
  together.
- Runtime secrets are synced through External Secrets Operator from
  1Password (`REGISTRY` item in `tuist-k8s-<env>` vault).
- Normal deploys run through `.github/workflows/server-deployment.yml`,
  which builds and deploys the registry read image together with the
  server image so the read frontend and `swift_registry_sync` writer roll
  from the same commit.

### Cluster prereqs
The chart assumes these are installed in the target cluster (they
already are on the managed clusters, installed by the platform chart):
- External Secrets Operator with a `ClusterSecretStore` named
  `onepassword`
- cert-manager with a `ClusterIssuer` named `letsencrypt-cloudflare`
- ingress-nginx
- external-dns (for per-env hostnames; `registry.tuist.dev` itself
  is owned by the existing Cloudflare Worker and is not managed by
  external-dns)

### `REGISTRY` 1Password item
Per environment vault (`tuist-k8s-{staging,canary,production}`), the
`REGISTRY` item must contain the **read-side** credentials:
- `s3_registry_bucket`, `s3_host`, `s3_access_key_id`,
  `s3_secret_access_key`, `s3_region`
- `sentry_dsn` (project-specific Sentry DSN)

The sync side reads the same item (it needs read+write to the same
bucket, plus a `registry_github_token` field — see
`infra/helm/tuist/templates/swift-registry-sync-deployment.yaml`).

The Tigris access key must allow read on the env's `tuist-registry-<env>`
(or `tuist-registry` for production) bucket.

## Smoke recipe
After a deploy, verify with:

```bash
# pick the right env
HOST=registry-canary.tuist.dev      # canary
INGRESS=91.98.12.147                # canary cluster ingress
# production: HOST=registry.tuist.dev, INGRESS=91.98.14.217
# staging:    HOST=registry-staging.tuist.dev, INGRESS=91.98.219.17

curl -sS --resolve "$HOST:443:$INGRESS" "https://$HOST/up"
# expect: 200

curl -sS --resolve "$HOST:443:$INGRESS" \
  -H 'Accept: application/vnd.swift.registry.v1+json' \
  "https://$HOST/swift/availability"
# expect: 200, Content-Version: 1

curl -sS --resolve "$HOST:443:$INGRESS" \
  -H 'Accept: application/vnd.swift.registry.v1+json' \
  "https://$HOST/swift/alamofire/alamofire"
# expect: 200 with a JSON releases map (or 404 if the bucket has no
# data for the scope yet, which is distinct from 5xx)
```

To force an immediate release sync instead of waiting for the 10-minute
cron, connect to the **server's** swift-registry-sync pod (not the read
frontend in this directory) and enqueue `Tuist.Registry.Swift.ReleaseWorker`
from an Elixir console.

## Related Context
- Server registry sync workers: `server/lib/tuist/registry/swift/`
- Sync deployment template: `infra/helm/tuist/templates/swift-registry-sync-deployment.yaml`
- Cache service: `cache/AGENTS.md`
- Kubernetes chart: `infra/helm/tuist/`
- Shared Elixir utilities: `tuist_common/AGENTS.md`
- Bounded-resources reference for the eventual streaming / warm-disk
  generation of this service: `kura/README.md`
