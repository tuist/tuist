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

Five kinds today, covering the surface the ops playbook cares about:

- `CloudflareRateLimit` — one entry in a zone's `http_ratelimit`
  ruleset. See `api/v1alpha1/cloudflareratelimit_types.go` and
  `config/samples/public-pages-rate-limit.yaml`.
- `CloudflareCacheRule` — one entry in a zone's
  `http_request_cache_settings` ruleset. Cache marketing, docs, OG
  images at the edge. See `config/samples/marketing-cache-rule.yaml`,
  `config/samples/og-images-cache-rule.yaml`.
- `CloudflareWAFCustomRule` — one entry in a zone's
  `http_request_firewall_custom` ruleset. The Custom Rules screen in
  the Cloudflare dashboard. See `config/samples/auth-managed-challenge.yaml`.
- `CloudflareZoneSetting` — one zone-level setting pinned to a value
  (challenge_ttl, ssl, security_level, always_use_https, etc.). The
  value is raw JSON so one CRD covers every setting shape. See
  `config/samples/challenge-passage.yaml`.
- `CloudflareAICrawlControl` — zone-level AI Crawl Control config.
  The wire format is newer than the Rulesets API and has iterated, so
  the CRD passes the payload through as raw JSON that the operator
  PUTs verbatim; drift-detection is a byte comparison.

## Reconciliation model

**Ruleset-based CRDs** (`CloudflareRateLimit`, `CloudflareCacheRule`,
`CloudflareWAFCustomRule`) share the same reconcile shape:

1. GET the zone's entrypoint ruleset for the phase; POST to create it
   if none exists yet.
2. Scan for a rule with a stable `ref` the operator derives from the
   CR's name and UID (namespaced per CRD kind so collisions between
   `CloudflareRateLimit/foo` and `CloudflareCacheRule/foo` don't
   happen on the wire).
3. Missing → POST. Drifted → PATCH. In sync → no-op.

Ruleset CRDs use a finalizer (`cloudflare.tuist.dev/finalizer`) so a
CR delete propagates to Cloudflare.

**Settings-based CRDs** (`CloudflareZoneSetting`,
`CloudflareAICrawlControl`) compare the desired JSON payload against
the value Cloudflare returns and PATCH/PUT when they differ. These do
**not** run a finalizer: deleting the CR just stops managing that
setting; it does not revert Cloudflare to a default. This is
intentional — a `kubectl delete` on a compliance-critical setting
should not silently roll it back.

Every successful reconcile requeues after `--resync-interval` (5 min
by default), which is also how quickly a dashboard edit gets corrected
back to what git says.

## Deploying

The operator ships as a container image and a Helm chart at
`infra/helm/cloudflare-operator/`. It runs in the management cluster
(not per-workload cluster) because the resources it manages are zone-
global.

Cloudflare API token lives in a Kubernetes Secret referenced by the
chart. Scopes needed on the token (per the five current CRDs): Zone
Read, Zone WAF Edit, Cache Rules Edit, Zone Settings Edit, and Zone
AI Crawl Control Edit — all scoped to the account and zones under
management. Give the token account-wide zone scopes if you plan to
manage multiple zones.

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
