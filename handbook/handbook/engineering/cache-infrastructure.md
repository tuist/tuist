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

The first three are customer-facing. `scw-fr-par-runners` is private: it serves the macOS runner fleet's build cache over the private network the Mac minis attach to, and is not offered as a region to accounts.

Each region is one box today. A region's capacity grows by adding boxes, not by splitting an account across them, because an account's cache pods are kept together on a single box.

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
