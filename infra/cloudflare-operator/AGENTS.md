# cloudflare-operator

Kubernetes controller that reconciles CRDs under `cloudflare.tuist.dev`
against the Cloudflare API. It exists so zone-level Cloudflare
configuration (rate limiting rules today; cache rules, WAF custom
rules, AI Crawl Control, and zone settings as follow-on CRDs) lives in
git and reaches production through a reviewed PR, not through the
Cloudflare dashboard.

## Why an operator, not Terraform

Terraform requires a state backend (S3-style bucket + locking) and
turns every edit into a `terraform apply` pipeline. The tenant here is
a small team on a Kubernetes-heavy stack; the natural GitOps loop is
"desired state in git → reconciler in the cluster → API is actual
state," matching Kubernetes' own model. The operator uses stable
`Ref` identifiers Cloudflare stores on each rule so it can find and
update the same rule across reconciles with no client-side state.

Off-the-shelf options were surveyed (Kubeflare, Crossplane's
provider-upjet-cloudflare, various small controllers). None cover the
Rate Limiting / Cache Rules / AI Crawl Control surface we need; this
operator fills the gap.

## Current CRDs

- `CloudflareRateLimit` — one entry in a zone's `http_ratelimit`
  ruleset. See `api/v1alpha1/cloudflareratelimit_types.go` and
  `config/samples/public-pages-rate-limit.yaml`.

Follow-on CRDs to add (in priority order):

- `CloudflareCacheRule` — for marketing / docs / OG image caching.
- `CloudflareCustomRule` — WAF custom rules (public-repo-safe ones
  only; IP allowlists stay in a private overlay).
- `CloudflareAICrawlerPolicy` — AI Crawl Control policy per zone.
- `CloudflareZoneSetting` — Challenge Passage, TLS, etc.

## Reconciliation model

Each CR has a stable `ref` the operator derives from the CR's name and
UID. On every reconcile:

1. GET the zone's entrypoint ruleset for the phase (`http_ratelimit`
   for rate limits). If Cloudflare has none yet, POST to create it.
2. Scan the ruleset for a rule with the matching `ref`.
3. Compare the live rule to the desired rule (rendered from the CR).
4. If missing → POST. If drifted → PATCH. If in sync → no-op.

A finalizer (`cloudflare.tuist.dev/finalizer`) makes CR deletion delete
the live Cloudflare rule before removing the finalizer, so git deletes
propagate.

Every successful reconcile requeues after `--resync-interval` (5 min
by default), which is also how quickly a dashboard edit gets corrected
back to what git says.

## Deploying

The operator ships as a container image and a Helm chart at
`infra/helm/cloudflare-operator/`. It runs in the management cluster
(not per-workload cluster) because the resources it manages are zone-
global.

Cloudflare API token lives in a Kubernetes Secret referenced by the
chart. The token needs Zone:Read, Zone WAF:Edit, and (once cache rules
land) Cache Rules:Edit scoped to the account and zone under
management.

## Local development

Requires Go 1.25.

```
cd infra/cloudflare-operator
go build ./...
go test ./...
```

The reconciler is tested with a scripted fake implementing the narrow
`RateLimitAPI` interface, so tests don't need real Cloudflare
credentials.

## Related

- `server/lib/tuist_web/plugs/public_page_header_plug.ex` — sets the
  `x-tuist-public` response header the sample rate limit rule keys on.
- Hive spec #72 (GitOps and health monitoring for the workload
  clusters) — once Flux is running, this operator's CRDs get committed
  to git and Flux applies them to the management cluster. Until then
  the deployment workflow does `kubectl apply` directly.
