---
{
  "title": "Cache infrastructure",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "How Tuist's globally distributed cache nodes are provisioned, deployed, and operated."
}
---
# Cache infrastructure

Tuist operates a globally distributed cache that holds build artifacts close to the developers reading them. Latency is the whole point, so the service runs on bare metal in several regions rather than in one place.

The fleet is mid-migration between two generations. Kura, a Rust cache mesh, runs on nodes that are ordinary members of our Kubernetes clusters. It is replacing an older Elixir cache service that runs on separately managed hosts. This page describes the current model first, because that is what new work targets, and the fleet being retired second.

## How cache nodes work today

A Kura node is a bare-metal box running Ubuntu that has joined one of our Kubernetes clusters as a worker. There is no separate configuration system for it. It gets its configuration the same way every other node does, and Kura itself is scheduled onto it as a workload.

That is the substantive change. The old fleet had its own operating system, its own deployment tool, its own secret delivery mechanism, its own reverse proxy, and its own telemetry agent, none of which were the ones the rest of the platform used. A cache host was a different kind of machine that happened to be ours. Now it is the same kind of machine as everything else, which means one way to grant access, one way to deliver secrets, one way to ship telemetry, and one place to look when something is wrong.

| Concern | How it is handled |
| --- | --- |
| Operating system | Ubuntu, installed once during preparation |
| Cluster membership | Cluster API, with an operator-minted kubelet identity and secure shell self-join |
| Application | Kura, a Rust service, deployed by Helm and reconciled from `KuraInstance` resources |
| Storage | Local disk: a metadata store for manifests and replication state, append-only segment files for artifact bodies |
| Ingress and certificates | Regional ingress controllers with certificates issued through cert-manager |
| Secrets | 1Password, synchronized into the cluster by the External Secrets Operator |
| Observability | Grafana Cloud, through the in-cluster telemetry agent that covers every workload |

## Regions

| Region | Provider | Location |
| --- | --- | --- |
| `eu-central` | Scaleway Dedibox | Europe, central |
| `us-east` | OVHcloud | Vint Hill, Virginia |
| `us-west` | OVHcloud | Hillsboro, Oregon |
| `scw-fr-par-runners` | Scaleway Elastic Metal | Paris |

The first three serve customers. `scw-fr-par-runners` is private: it serves the macOS runner fleet's build cache over the private network the Mac minis attach to.

Customers do not choose among them. An account is placed in the region its cache traffic comes from, and the placement follows that traffic when it durably moves; what an account states is where its data may live (the storage region setting), which is a compliance boundary rather than a placement. Each account also has a cache hostname without a region in it, so a client that writes the endpoint down keeps working when its cache moves.

Each region is one box today. A region's capacity grows by adding boxes, not by splitting an account across them, because an account's cache pods are kept together on a single box.

## How an instance is sized

An account's cache instance is bounded on four dimensions: memory, CPU, disk, and egress. Each is a pair, a floor the instance is guaranteed and a ceiling it may reach at peak, and the two are deliberately unequal. Floors decide how many accounts fit on a box, because the scheduler places pods against the sum of their floors and nothing else. Ceilings decide how large a burst an account absorbs before it is shed, and they oversubscribe the box on purpose: headroom above a floor costs nothing until someone uses it.

What differs between the dimensions is where the number comes from.

| Dimension | Floor | Ceiling |
| --- | --- | --- |
| Memory | Granted per plan | Granted per plan |
| CPU | Measured per instance | Granted per plan |
| Disk | Granted per plan, then grown from measured shedding | The same value: the claim is the quota |
| Egress | Granted per region, overridable per account | Granted per region |

**CPU is the one we measure.** Every other floor is a number we choose in advance, which works when a plan predicts the need. For CPU it does not: instances on the same plan differ from each other by nearly two orders of magnitude, and the two replicas of one instance differ by around ten times, because one serves traffic while the other stands by. No value chosen per plan can see either. So the controller watches each instance's actual usage, keeps a week of it, and asks for what that instance has been observed to need. A flat reservation is what it replaced, and that reservation, not real load, is what once filled a region to the point that new accounts could not be placed in it while the box ran at under a tenth of its capacity.

The ceiling is still granted per plan, because how much an account may take is an entitlement while how much it needs is an observation.

**Compressible and incompressible dimensions behave differently at the ceiling, and that is why the ceilings are not set alike.** Exceeding a memory ceiling kills the process, so the ceiling has to be far enough above real use that a normal burst never reaches it. CPU is compressible: exceeding the reservation only means being slowed down, and only while the box is contended. But the mechanism that enforces a CPU ceiling is not proportional the way the one for bandwidth is. It hands out a budget every tenth of a second and stops the container dead once that budget is spent, even on a machine that is otherwise idle, so a ceiling set close to real use produces stalls that look like the service being slow rather than being limited. The CPU ceilings are therefore set several times above observed use: high enough to bound a runaway instance, far enough away that ordinary work never meets them.

The values themselves live in `server/lib/tuist/kura/regions.ex`, which is where to change them. They are not repeated here, because a number in two places is a number that will disagree with itself.

## Bringing a node into the fleet

The controllers never order hardware. A box is ordered by hand, prepared, and then adopted.

1. **Order the box** in the provider console. OVHcloud for the US regions, Dedibox for `eu-central`.

2. **Prepare it.** One task installs Ubuntu, the fleet's secure shell key, and the sudo password, then sets the adoption marker as its final step:

   ```bash
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-ovh <service-name> <fleet-name>
   PREP_NAMESPACE=tuist-production mise run baremetal:prep-dedibox <server-id>
   ```

   The install runs asynchronously and takes roughly twenty to forty minutes. `PREP_NAMESPACE` selects the environment, which selects both the 1Password vault and the values file the marker is read from. Pass `PREP_SKIP_MARK=1` to stage capacity without releasing it into the pool yet.

3. **Declare the fleet** at the new box count in `infra/helm/tuist/values-managed-<env>.yaml` and deploy. The controller claims the marked box and self-joins it in two to five minutes. Adoption is a claim plus a self-join; the operating system install never runs on this path, which is what keeps it fast.

Scaling afterwards is `kubectl scale machinedeployment`.

## Deploying

Kura is a mesh, and it is deployed with rolling updates, so nodes running different versions serve traffic side by side during a rollout. Every change has to be safe under that overlap: compatible across one version of skew in both directions, no change to the on-disk or replication formats that an older peer cannot read, and no local optimization that alters the bytes a client receives. The detail lives in `kura/AGENTS.md` and is worth reading before changing anything on the replication path.

## Operating

**Access.** Cache nodes are cluster nodes, so they are reached through the same read-only-by-default path as any other workload, with writes going through the just-in-time elevation flow. There is no separate secure shell path for routine work; the fleet key exists for provisioning and recovery.

**Secrets.** Held in 1Password and synchronized by the External Secrets Operator. Rotating one means updating the item and letting the operator resynchronize.

**Observability.** Metrics, logs, and traces reach Grafana Cloud through the in-cluster agent. Dashboards are version-controlled in `infra/grafana-dashboards/` and synchronized with Grafana Cloud.

**Release.** Releasing a box wipes and reinstalls Scaleway Elastic Metal machines. Dedibox and OVHcloud machines are left installed and can be re-adopted.

## The fleet being retired

The older cache service is an Elixir application in a container, fronted by nginx, running on hosts managed with NixOS and deployed with Colmena and Kamal. Its configuration lives in `cache/platform/` and its host list in `cache/config/deploy*.yml`.

It is still serving production traffic across roughly ten regions while Kura regions come up beside it. It is being retired region by region rather than in one cutover, and nothing new should be built on it. If you need the provisioning and deployment detail for a host that is still in service, `cache/platform/` and `cache/AGENTS.md` have it.

NixOS applies only to that fleet. New cache nodes do not use it.

## Related

- `kura/AGENTS.md` and `kura/docs/architecture.md` for the mesh itself
- `infra/cluster-api-provider-tuist/AGENTS.md` for the machine kinds and the adoption flow
- `infra/AGENTS.md` for how the clusters fit together
