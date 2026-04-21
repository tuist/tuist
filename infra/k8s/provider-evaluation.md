# Kubernetes Provider Evaluation — Server Migration off Render

> **Status**: proposal for team review
> **Author**: prepared for the infra discussion, 2026-04-21
> **Decision needed**: pick a managed Kubernetes provider for the Tuist server migration off Render

## TL;DR

**Two finalists, both strong**: **Syself Managed Kubernetes on Hetzner Cloud (Nuremberg)** or **Google Kubernetes Engine (europe-west3, Frankfurt)**.

We lean **Syself** slightly because our cache nodes already run on Hetzner and the vendor consolidation is meaningful — same provider, same credentials, same operational muscle memory. GKE is a very defensible alternative if the team prefers the most boring-infrastructure managed k8s experience available and is willing to pay ~2–3× more for it.

Either way we leave Render, keep Frankfurt-adjacent data locality, and stop paying Render's ceiling.

| Decision | Answer |
|---|---|
| K8s provider | **Syself on Hetzner NBG1** (lean) or **GKE europe-west3** (co-finalist) |
| DNS | Cloudflare (keep) |
| Observability | Grafana Cloud (keep — already in use via `infra/grafana-alloy/`) |
| Secrets | Keep encrypted `.yml.enc` files baked into image, mount `<env>.key` via k8s Secret, runtime vars via plain k8s Secrets. Upgrade to external-secrets later. |
| Node sizing (start) | 2× 4 vCPU / 8 GB nodes for production, 1× smaller node for staging+canary on shared nodes, autoscaler on |
| Expected monthly cost | **Syself: ~€100–200** / **GKE: ~$330–400** (vs ~$700 Render today) |

Pending: team sign-off on Syself vs GKE, quote from Syself confirming their platform fee for our topology.

---

## Why we're doing this

- **Render's limitations are biting**: pricing ceiling, limited workload flexibility (no sidecars, no proper workers split, no job primitives), no path to host our own Postgres/ClickHouse later.
- **Cost**: Render ~$700/mo today across production + canary + staging. We can do the same on k8s for ~€150–200/mo.
- **In-cluster data services, soon**: we want to move Postgres and/or ClickHouse out of Supabase/ClickHouse Cloud and into the same cluster in the near term — this is not a hypothetical 12-month consideration. Render can't host that; a k8s cluster can. The provider's stateful-workload fitness is a first-class decision input, not a future-proofing nice-to-have.
- **Consolidation**: we already operate Hetzner for cache nodes. Adding another Hetzner workload means one vendor, one billing relationship, one set of credentials.

## Constraints we designed around

1. **Data locality**: Supabase (AWS eu-central-1 Frankfurt) and ClickHouse Cloud Frankfurt are staying. The k8s cluster needs to be in Frankfurt or very close.
2. **GDPR / EU-only data processing.**
3. **Low ops tolerance**: 4-person team. We want managed k8s, not "run your own control plane at 3am".
4. **Ecosystem compatibility**: cert-manager, external-dns, ingress-nginx, standard CSI — all must work out of the box.
5. **Stateful workloads, soon**: we plan to bring Postgres (and likely ClickHouse) in-cluster in the near term. The provider needs to support database workloads at real IOPS — ideally via local NVMe on dedicated hardware, or at minimum SAN-grade SSDs with snapshots and point-in-time recovery.

## Provider comparison (candidates we actually evaluated)

Monthly cost normalized to: control plane + 2× 4 vCPU / 8 GB nodes + 1 LoadBalancer + 100 GB block storage + ~1 TB egress.

| Provider | Nearest DE region | Latency to AWS eu-central-1 | Managed CP? | Est. monthly | Verdict |
|---|---|---|---|---|---|
| **Syself on Hetzner** | Nuremberg / Falkenstein | ~4–8 ms | ✓ fully | **~€100–200** | **Co-finalist (leaning)** |
| **GKE Standard** | Frankfurt (europe-west3) | ~1–3 ms | ✓ fully | **~$330–400** | **Co-finalist** |
| DigitalOcean DOKS | Frankfurt (FRA1) | ~1–3 ms | ✓ fully | ~$160–200 | Third place — safer on bus factor than Syself, less future-proof than GKE |
| k3s DIY on Hetzner | Nuremberg | ~4–8 ms | You own it | ~€55 | Budget pick, rejected |
| Linode/Akamai LKE | Frankfurt | ~1–3 ms | ✓ fully | ~$120–180 | Solid; bus-factor on Akamai LKE investment a small question |
| STACKIT SKE | Frankfurt | ~1–3 ms | ✓ fully | ~€160–200 | Revisit only if German sovereignty is an enterprise customer ask |
| EKS | Frankfurt | <1 ms (same cloud as data) | CP only, nodes are yours | ~$355+ | Heaviest ops burden of the managed set; no win over GKE at our scale |
| GKE Autopilot | Frankfurt | ~1–3 ms | ✓ ultra-managed | ~$540+ | Per-pod pricing adds 30–60% vs Standard for our shape; skip |
| AKS | Germany West Central (Frankfurt) | ~1–3 ms | ✓ fully | ~$280–350 | Fine, no reason to prefer over GKE at this scale |
| OVHcloud MKS | Gravelines/Strasbourg (FR) | ~12–18 ms | ✓ fully | ~€85 | No DE region — latency penalty |
| Scaleway Kapsule | Amsterdam (no DE yet) | ~7–12 ms | ✓ fully | ~€82 | No Frankfurt as of April 2026 |
| IONOS MKS | Frankfurt | ~1–3 ms | ✓ fully | ~€90–110 | Smaller ecosystem, less third-party testing |
| gridscale GSK | Frankfurt | ~1–3 ms | ✓ fully | ~€120 | Niche; we'd be on the smaller side of their customer base |
| Civo | Frankfurt | ~1–3 ms | ✓ managed k3s | ~$100 | Small shop; fine for staging, risky for prod DB |

### Co-finalist 1: Syself on Hetzner

| Dimension | Why it fits |
|---|---|
| **Vendor consolidation** | We already run Hetzner for cache nodes. Same billing, same Terraform provider, same operational muscle memory. This is the single biggest differentiator over GKE. |
| **Actually managed** | Control plane, HA etcd, CSI driver, autoscaling, upgrades — Syself handles it. This is the whole point of leaving Render. |
| **Cost** | ~60–80% cheaper than hyperscalers for equivalent spec. ~2–3× cheaper than GKE. |
| **Near-term in-cluster DB** | Syself supports **mixing Hetzner Cloud VMs + Hetzner Robot dedicated nodes in a single cluster**. For the imminent Postgres/ClickHouse in-cluster move, we put the DB on an AX41/AX52/AX102 bare-metal node with local NVMe (~1M IOPS) while app pods stay on Cloud VMs. GKE's equivalent is Persistent Disk Extreme or Hyperdisk at 15k–350k IOPS — solid, but network-attached and 5–10× the cost for equivalent throughput. |
| **Latency** | Nuremberg is ~4–8 ms from AWS Frankfurt. Imperceptible for a Phoenix app doing a handful of DB round-trips per request. |
| **EU-native** | German company, GDPR-friendly, same jurisdiction as our data. No Schrems II friction. |

**Risks we're accepting with Syself:**

1. **Bus factor**: smaller company than Google. If they fold, we have two escape hatches: either migrate to k3s-on-Hetzner ourselves using the same nodes, or move to GKE. Our Helm chart is designed provider-agnostic precisely so this is a weekend's work, not a quarter's.
2. **Pricing opacity**: platform fee is tiered and not fully self-serve. Before we commit, we need a concrete quote. A ~€200/mo platform fee flips the economics; ~€50/mo makes this a clear win.
3. **No self-serve onboarding**: in 2026, Syself still requires a sales demo to get platform access. You cannot sign up, launch a cluster, and evaluate in an afternoon — which is unusual for infrastructure this size and matters for two reasons. First, it blocks evaluation momentum: we have to schedule, wait, and sit through a call before we learn anything concrete. Second, it's a hint about the operational model we'd inherit if we adopt them: a vendor that gates trial access is likely to gate production support the same way (email a CSM vs. click in a dashboard). Not a dealbreaker, but a real texture difference vs. GKE / DOKS / Linode where everything — signup, cluster creation, support tickets — is self-serve.
4. **Ecosystem size**: fewer community tutorials than "install X on GKE". In practice everything works — they ship upstream k8s — but Googling specific problems is quieter.

### Co-finalist 2: GKE Standard (europe-west3)

| Dimension | Why it fits |
|---|---|
| **Gold-standard managed k8s** | GKE is widely considered the most polished managed k8s experience. Control plane upgrades, node auto-repair, node auto-upgrade, cluster autoscaler — all first-party, all battle-tested. |
| **Same metro as data** | europe-west3 is Frankfurt. Latency to Supabase (AWS eu-central-1) is 1–3 ms. Slightly better than Hetzner Nuremberg's 4–8 ms, though neither is user-perceptible. |
| **Ecosystem size** | Every Helm chart, every tutorial, every Terraform module is tested on GKE first. Fewest "does this work here" surprises. |
| **Future DB story** | Persistent Disk Extreme or Hyperdisk ML can push 15k+ IOPS per volume with proper snapshots and point-in-time recovery. Good for in-cluster Postgres, though pricier than Hetzner bare metal. |
| **No bus factor** | Google isn't going anywhere. |
| **Identity & secrets** | Workload Identity gives pods scoped GCP IAM without mounted credentials — cleanest secrets story available. |

**Risks and tradeoffs with GKE:**

1. **Cost**: ~2–3× Syself. Control plane fee ($74/mo) + node pricing + cross-cloud egress to Supabase/ClickHouse (roughly $0.12/GB outside GCP) add up. At our scale this is real money, not rounding error.
2. **US vendor**: some EU customers care about Schrems II. Data stays in Frankfurt, but the legal entity is US. Hasn't been a customer ask for us yet, but worth flagging.
3. **Vendor split**: we'd run cache on Hetzner and server on GKE. More Terraform, more billing relationships, more credentials to rotate. (Note: server↔cache east-west traffic is negligible in our architecture, so this is a management-surface concern, not an egress-cost one.)

### Why we lean Syself

Three reasons, in order of weight:

1. **Near-term in-cluster DB story**: we plan to self-host Postgres (and likely ClickHouse) in-cluster soon. Hetzner Robot bare metal with local NVMe is the best price/IOPS ratio available anywhere — AX41/AX52/AX102 nodes give ~1M IOPS on local NVMe for ~€40–130/mo per node. GKE's equivalent is Persistent Disk Extreme or Hyperdisk: solid, but network-attached (extra µs of latency per op), capped at 15k–350k IOPS, and 5–10× the cost for equivalent throughput. Syself's ability to **mix Hetzner Cloud VMs (app pods) with Hetzner Robot bare metal (DB pods) in a single cluster** is exactly the topology a serious self-hosted Postgres on k8s wants.
2. **Vendor consolidation**: we've already committed to Hetzner for cache. Running the server on Hetzner too means one vendor for all compute, one billing page, one Terraform provider, one set of network peering to reason about.
3. **Cost**: ~€100/mo vs ~$350/mo for GKE. Plus the Robot bare metal DB node(s) later. At steady state, total infra spend on Hetzner+Syself is likely 2–3× cheaper than the GKE-equivalent with Persistent Disk for DBs.

**GKE is the right pick if** (a) the team decides the in-cluster DB plan is actually farther out than we think, making hyperscaler-grade managed k8s polish more important than DB IOPS-per-euro today, (b) we weight Google's bus factor advantage heavily, or (c) we decide Schrems II / US-vendor concerns don't matter to us. This is a defensible choice; we wouldn't regret either — but given the near-term DB plans, Syself is the stronger fit.

**Escape hatch**: our Helm chart is provider-agnostic (cert-manager + external-dns + ingress-nginx + no provider IAM lock-in), so moving Syself → GKE (or the reverse) later would be a weekend, not a quarter.

### Third place: DigitalOcean DOKS

Safer on bus factor than Syself, less future-proof than GKE. We'd pick this only if both finalists fall through.

- ✅ Frankfurt (FRA1), rock-solid ecosystem, great docs, predictable self-serve pricing, HA control plane for $40/mo.
- ❌ ~2× the cost of Syself. Moderate-IOPS block storage — if Postgres comes in-cluster at scale, we'd want to leave DOKS.

## Why we're not doing k3s DIY

We looked hard at self-managing k3s on Hetzner (via `hetzner-k3s` or `kube-hetzner` Terraform module). The raw cost is ~€55/mo — compelling.

Honest breakdown of what k3s bundles vs what we'd still own:

| Concern | Syself manages | k3s DIY |
|---|---|---|
| Multi-master HA | ✓ | We set up 3 masters with embedded etcd |
| etcd S3 backups | ✓ | We configure; restore drills are on us |
| CP minor upgrades (1.30 → 1.31) | ✓ one-click | We run System Upgrade Controller, own rollback |
| CVE patching | ✓ | We subscribe to k3s releases |
| Node kubelet/kube-proxy upgrades | ✓ | Kured + unattended-upgrades, configured by us |
| API availability SLA | 99.95% | None |
| 3am incidents | Their oncall | Our oncall |

**Engineering time estimate** (rough, from research): Syself ≈ 1–3 hrs/quarter. k3s DIY ≈ 4–10 hrs/quarter plus tail risk. At fully-loaded engineer cost, the ~€100/mo savings vs Syself roughly matches the labor delta **in steady state**. But the tail risk — one broken upgrade, one etcd corruption — costs a full engineering day we don't have.

**Decision**: not worth it for a 4-person product team running a commercial SaaS. If cost becomes the dominant constraint later, we can revisit.

## Cost comparison

| Line item | Today (Render) | Syself on Hetzner NBG1 | GKE europe-west3 |
|---|---|---|---|
| Production compute | ~$425–500/mo (1 instance, Pro Max class) | 2× CPX31 = €33/mo | 2× e2-standard-2 ≈ $100/mo |
| Staging + canary | ~$200/mo | 1× CPX21 = €8/mo (shared, namespaced) | 1× e2-small ≈ $13/mo |
| Control plane | — | Included in platform fee | $74/mo per cluster |
| Load balancer / ingress | Bundled | Hetzner LB11 = €5.39/mo | Regional LB ≈ $18/mo |
| Persistent volumes | Bundled | 100 GB = €4.40/mo | 100 GB PD-SSD ≈ $17/mo |
| Egress (~1 TB) | Bundled | Included in Hetzner traffic allowance | ~$120/mo (outside GCP) |
| Managed k8s platform fee | — | ~€50–150/mo (quote pending) | — (included in CP) |
| **Total** | **~$700/mo** | **~€100–200/mo** | **~$340–400/mo** |

Savings vs Render: **~50–70% with Syself**, **~45% with GKE**. The Syself number depends on their platform fee quote. Either way, both beat Render meaningfully.

## Sizing plan

Render today: **single FRA instance, rolling deploys, ~$700/mo across production + canary + staging**.

Starting shape on either Syself or GKE:

- **Production**: 2× 4 vCPU / 8 GB nodes (Syself: CPX31; GKE: e2-standard-2 or n2-standard-2). Gives us rolling-deploy capacity with real HA across nodes.
- **Staging + canary**: 1× smaller node (Syself: CPX21; GKE: e2-small) shared between namespaces.
- **Autoscaler**: enabled, max 5 worker nodes.
- **PodDisruptionBudget**: min 1 pod available during node drains.
- **HPA**: on CPU (70% target) + memory, min 2 replicas in production.

This matches current capacity with headroom for traffic spikes and real zero-downtime deploys.

## Open questions before we commit

1. **Syself vs GKE — team call.** Both are strong. Syself is cheaper and consolidates with our Hetzner cache setup; GKE is the gold standard managed experience with no bus factor and a slightly better latency story. We lean Syself, happy to flip.
2. **Quote from Syself** for our target topology (1 cluster, 2-3 workers, room for Robot bare metal later). Needed to confirm the €100–200/mo estimate.
3. **Render cutover window**: prefer hard-switch via DNS flip after parallel validation, or a short maintenance window?
4. **Preview environments**: in scope for this migration, or follow-up? They use `TUIST_HOSTED=0`, `EMBED_CLICKHOUSE=true` — a different shape.

## Next steps

Once the team is aligned on Syself vs GKE:

1. If Syself: request quote for our topology. If GKE: provision a project and a cluster in europe-west3.
2. Provision cluster (can run in parallel with Render, no disruption).
3. Ship Helm chart changes + Dockerfile tweaks + CI pipeline in one PR.
4. Staging cutover (low risk) — exercise the deploy path.
5. Production cutover runbook — `infra/k8s/MIGRATION.md`.

---

## Sources

Pricing and feature data collected 2026-04-21. Full citation list maintained in the internal evaluation thread; key sources:

- [DigitalOcean Kubernetes pricing](https://www.digitalocean.com/pricing/kubernetes)
- [GKE pricing](https://cloud.google.com/kubernetes-engine/pricing)
- [EKS pricing](https://aws.amazon.com/eks/pricing/)
- [AKS pricing](https://azure.microsoft.com/en-us/pricing/details/kubernetes-service/)
- [Akamai/Linode pricing](https://www.linode.com/pricing/)
- [Scaleway Kapsule](https://www.scaleway.com/en/kubernetes-kapsule/), [region availability](https://www.scaleway.com/en/product-availability-by-region/)
- [Syself](https://syself.com/hetzner), [Syself pricing](https://syself.com/pricing)
- [STACKIT Kubernetes Engine](https://www.stackit.de/en/product/kubernetes/)
- [IONOS Managed Kubernetes](https://cloud.ionos.com/managed/kubernetes)
- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [hetzner-k3s](https://github.com/vitobotta/hetzner-k3s)
- [kube-hetzner (Terraform)](https://github.com/mysticaltech/terraform-hcloud-kube-hetzner)
- [Benchmarking Hetzner storage classes for DB workloads on k8s](https://sveneliasson.de/benchmarking-hetzners-storage-classes-for-database-workloads-on-kubernetes)
