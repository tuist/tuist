# cloudflare-operator

Kubernetes controller that reconciles CRDs under `cloudflare.tuist.dev`
against the Cloudflare API. It exists so zone-level Cloudflare
configuration lives in git and reaches production through a reviewed
PR, not through the Cloudflare dashboard.

**Scope today: `CloudflareRateLimit` only.** Additional CRDs (cache
rules, WAF custom rules, zone settings, AI Crawl Control) are
follow-up work; each is a separate PR so the first production
deployment has one small reviewable surface.

## Why an operator, not Terraform

Terraform requires a state backend (S3-style bucket + locking) and
turns every edit into a `terraform apply` pipeline. The tenant here
is a small team on a Kubernetes-heavy stack; the natural GitOps loop
is "desired state in git → reconciler in the cluster → API is actual
state," matching Kubernetes' own model. The operator uses stable
`Ref` identifiers Cloudflare stores on each rule so it can find and
update the same rule across reconciles with no client-side state.

## Safe-first-deploy design

The rate-limit CRD is designed so the first deployment against a
live zone is provably zero-risk:

- **`spec.mode` defaults to `read_only`.** In read_only the operator
  computes the intended diff, logs it, mirrors it into
  `status.proposedChanges`, and never issues a Cloudflare write —
  including no ruleset creation and no rule delete on finalizer
  cleanup. Flip to `active` only after a zero-change reconcile has
  been observed.
- **`spec.paused` halts the loop entirely.** Break-glass without
  editing every other field.
- **Adoption vs create is explicit.** `spec.adopt.ruleId` binds the
  CR to an existing Cloudflare rule id (e.g. one created via the
  dashboard) and the operator merges only the fields the CR
  explicitly sets over that rule's live configuration —
  Cloudflare-stored fields the operator does not model are preserved
  verbatim. To create a brand-new rule the CR must have
  `spec.createNewRule: true` and no `spec.adopt`; the CRD schema
  enforces "one of the two must be set". This makes accidental
  duplicate rules structurally impossible.
- **`spec.retainOnDelete` defaults to `true`.** A `kubectl delete` on
  the CR drops the finalizer without deleting the Cloudflare rule.
  Flip to `false` for rules the operator itself created and that
  should follow the CR out of git.
- **`spec.zoneId` is CRD-level immutable** (CEL `x-kubernetes-validations`).
  Combined with `status.managedZoneId` (written on the first
  successful reconcile and used by the delete path), the operator
  cannot orphan a rule if someone tries to mutate the zone id.
- **`ratelimit.characteristics` must include `cf.colo.id`.** CRD-level
  CEL validation enforces this — Cloudflare's Advanced Rate
  Limiting requires it for correct per-datacenter counting.

## Reconciliation model

Each CR either:

- **Pins an existing rule** (`spec.adopt.ruleId` set). The operator
  finds the rule by id, merges CR-set fields over the live payload,
  and updates only when the merge would change something. First
  adoption of a matching dashboard rule is a no-op.
- **Manages a new rule** (`spec.adopt` unset, `spec.createNewRule:
  true`). The operator computes a stable ref from name + UID
  (`makeRef`, hex-encoded SHA-256 prefix, fits Cloudflare's
  `^[a-zA-Z0-9_]{1,32}$`) and creates/updates by ref.

Reconcile requeues every `--resync-interval` (5 min default), which
is also how quickly a dashboard edit gets corrected back to what git
says — provided the CR is in `active` mode.

## Deploying

The operator ships as a container image and a Helm chart at
`infra/helm/cloudflare-operator/`. It runs in the management cluster
(not per-workload cluster) because the resources it manages are
zone-global.

Cloudflare API token lives in a Kubernetes Secret referenced by the
chart. The token needs `Zone:Read` and `Zone WAF:Edit` scoped to
the account and zone under management.

## Local development

Requires Go 1.25.

```
cd infra/cloudflare-operator
go build ./...
go test ./...
```

The reconciler is tested with a scripted fake implementing the
narrow `RulesetAPI` interface, so tests don't need real Cloudflare
credentials.

## Related

- `server/lib/tuist_web/plugs/public_page_header_plug.ex` — sets the
  `x-tuist-public` response header the sample rate limit rule keys on.
- Hive spec #72 (GitOps and health monitoring for the workload
  clusters) — once Flux is running, this operator's CRDs get
  committed to git and Flux applies them to the management cluster.
  Until then the deployment workflow does `kubectl apply` directly.
