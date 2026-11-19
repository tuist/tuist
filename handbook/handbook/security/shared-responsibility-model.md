---
{
  "title": "Shared responsibility model",
  "titleTemplate": ":title | Security | Tuist Handbook",
  "description": "Where the security boundary falls between Tuist GmbH and each of its infrastructure providers."
}
---
# Shared responsibility model

Tuist runs its own Kubernetes clusters on rented hardware. We do not use a managed application platform, so the boundary between us and our providers sits lower than a platform-as-a-service model would put it. Providers are accountable for physical infrastructure and for the managed services they operate themselves. Everything from the operating system upward, including Kubernetes, our primary database, and the analytics database, is ours.

This distinction matters more than it might sound. Under a platform model, the cluster, the runtime, and often the database sit on the provider's side of the line. Under ours they do not. Any statement that a provider handles our cluster, our primary database, or our analytics database is wrong.

## Where the line falls

| Layer | Responsible |
| --- | --- |
| Data centre, power, cooling, physical hardware | Provider |
| Host network, hardware-level volumetric attack filtering | Provider |
| Node operating system and its patching | Tuist |
| Kubernetes control plane, workers, networking, upgrades | Tuist |
| Platform components: ingress, certificate issuance, secret sync, autoscaling | Tuist |
| PostgreSQL and Valkey, both in-cluster | Tuist |
| ClickHouse, on dedicated bare metal in the cluster | Tuist |
| Object storage, edge network | Provider operates, Tuist configures and controls access |
| Telemetry storage | Provider stores, Tuist decides what is sent and who may read it |
| Application code, dependencies, data model | Tuist |
| Identity, authorization, and the access lifecycle | Tuist, on top of the identity provider |

## Hetzner: cluster compute

Cloud instances and bare metal that host our Kubernetes clusters. Machine lifecycle is driven by Cluster API with the Hetzner provider; load balancers and block storage are Hetzner services.

**Hetzner is responsible for** physical data centre security, power and cooling, the hardware and hypervisor, the host network, filtering of network-level volumetric attacks, and the availability of the cloud API, load balancer, and block storage services.

**Tuist is responsible for** everything above the machine: the node operating system and its patch level, the Kubernetes control plane and worker configuration, cluster upgrades, in-cluster network policy, workload and namespace isolation, firewall rules, and encryption of the data we place on attached volumes.

## Scaleway: macOS fleet and bare metal

Apple Silicon Mac minis and bare metal, ordered and released through Scaleway's API by our own Cluster API provider. The Mac minis run virtual machines that execute customer build jobs.

**Scaleway is responsible for** the data centre, the hardware, the host network, and the availability of the machines and their API.

**Tuist is responsible for** the contents and patch level of the macOS images we bake, the agent that registers each host as a cluster node, the virtual machine boundary that separates one customer's build from another's, credential handling on the host, and the separation of per-account caches.

## OVHcloud: cache regions

Bare metal in Vint Hill, Virginia and Hillsboro, Oregon hosting regional cache nodes.

The split matches Scaleway. Hardware and host network are OVHcloud's. The operating system, cluster membership, and the cache workload itself are ours.

## Tigris: object storage

Customer artifacts, build outputs, previews, database backups, and the cluster telemetry that Pulse stores.

**Tigris is responsible for** durability and availability of the store, encryption in transit and at rest, isolation between tenants, and the security of the storage infrastructure.

**Tuist is responsible for** bucket layout and lifecycle rules, access keys and their rotation, what data is written and how long it is kept, the authorization check that runs before any object is served, and encrypting sensitive values before they are stored.

For additional detail, see Tigris's [privacy policy](https://www.tigrisdata.com/docs/legal/privacy-policy/#6-security).

## ClickHouse: analytics database

Build and test analytics run on ClickHouse that we operate ourselves, on dedicated Hetzner bare-metal nodes. Those machines follow the Hetzner split above. The hardware and host network are Hetzner's, and the database is ours.

**Tuist is responsible for** the ClickHouse server image and its patch level, the operating system on those nodes, the schema and how long data is kept, backups to Tigris, who can connect and with what privileges, and the metrics and alerts for the service.

The server image is pinned to a ClickHouse long-term support release. Each replica stores its data on that node's own disk, and ClickHouse Keeper holds coordination and the access-control entities. ClickHouse writes backups into the environment's Tigris bucket, under the `clickhouse-backups` prefix and then the namespace: a full backup every Monday and, on the other days, an incremental based on that week's full. ClickHouse does not delete old backups. Retention is a lifecycle rule on that prefix, in whole weeks and longer than one chain, because deleting a full backup invalidates the incrementals based on it. Durability and encryption of those objects are Tigris's, as above. A failed backup job is kept so its log can be read.

The application connects as `default`. That password is generated into a cluster Secret, and the application user's queries share a memory budget set per environment. Replica-to-replica part fetches require their own credential. Before every server rollout the migration job re-derives the restricted operator and Grafana roles and resets their privileges. It rotates the operator password from the password Helm holds for the release, and re-applies Grafana's from 1Password. Neither role holds privileges over external sources, files, dictionaries, users, or access management. Both are read-only, with query bounds they cannot raise. Off the pod network, only the HTTP port is published, and only on the tailnet, for the macOS fleet's processor. The native protocol and the metrics port stay inside the cluster.

ClickHouse and Keeper expose Prometheus metrics, which Alloy scrapes into Pulse. Grafana Cloud alerts on ClickHouse read failures, on read latency, and on queries that are slow or cancelled.

## Cloudflare: domain name service and edge

Authoritative name service, certificate validation, and the workers that route the package registry path and serve the public status page.

**Cloudflare is responsible for** the availability and security of the edge network, absorbing volumetric denial-of-service traffic, and the worker runtime.

**Tuist is responsible for** name records, edge rules and rate limits, worker code, certificate issuance policy, and keeping origins from being reachable around the edge.

## Grafana Cloud: dashboards and alerting

Cluster logs, metrics, and traces are stored in Pulse, the observability database we run in each environment, which keeps its data in Tigris. Grafana Cloud reads Pulse through a private tunnel to show dashboards and evaluate alerts. It still stores telemetry from the legacy cache machines and its own synthetic checks.

**Grafana is responsible for** the availability and access control of dashboards, alerting, and the telemetry it still stores, and the security of its platform.

**Tuist is responsible for** operating Pulse, what is logged and what is deliberately kept out of logs, redaction before anything is shipped, retention settings, dashboards and alert rules, and who is allowed to read logs. The requirements are in the [Logging and monitoring policy](/security/secure-development-and-operations/logging-and-monitoring-policy).

## 1Password: secret storage

Every runtime secret originates in 1Password and is synchronized into the clusters by the External Secrets Operator.

**1Password is responsible for** the cryptographic design of the vault, its availability, and platform security.

**Tuist is responsible for** vault structure and membership, which secrets exist and when they rotate, the synchronization configuration, and ensuring a synchronized secret is not readable by the wrong workload or through human read-only cluster access.

## Google Workspace: identity

Workforce identity, and the authentication source for cluster access.

**Google is responsible for** the security and availability of the authentication platform.

**Tuist is responsible for** the account lifecycle described in the [Access control policy](/security/access-and-risk-management/access-control-policy), group membership, enforcing multi-factor authentication, and every authorization decision made once an identity has been established.

## Tailscale: private network

Internal service access and operator paths that are deliberately not exposed publicly.

**Tailscale is responsible for** the security and availability of its coordination service.

**Tuist is responsible for** the access control list, which is a static, version-controlled document rather than something mutated at runtime, device and tag membership, and the decision about what is reachable on the private network rather than the public internet.

## Other services

GitHub for source control, continuous integration, and container images. Stripe for payments. Mailgun for transactional email. Each provider secures its own platform; Tuist controls its configuration, who can access it, and what data is sent to it. All are assessed under the [Third-party risk management policy](/security/access-and-risk-management/third-party-risk-management-policy). Application errors go to Tuist's self-hosted Atlas and Pulse error ingest, which Tuist operates.

## What no provider covers

Worth stating plainly, because it is the part a standard shared responsibility model would place elsewhere:

- The Kubernetes clusters, including the control plane, and their upgrade cadence
- The operating system on every node, across Linux and macOS
- PostgreSQL and Valkey, which run inside our clusters rather than as managed services
- ClickHouse, which runs on dedicated bare-metal nodes rather than as a managed service
- The application, its dependencies, and its data model
- Identity, authorization, and the access lifecycle

If a control in one of these areas is not performed by us, it is not performed at all.

## Review

This document is reviewed annually and whenever a provider is added or removed.

If you have questions about this model, please reach out to the security team at [contact@tuist.dev](mailto:contact@tuist.dev).
