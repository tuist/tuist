---
{
  "title": "Network",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Network configuration for Tuist, including outbound IP addresses."
}
---
# Network {#network}

This page covers network-related configuration that may be needed when integrating Tuist with your infrastructure.

## Outbound IP addresses {#outbound-ip-addresses}

If your infrastructure restricts inbound traffic by IP address, you may need to allowlist the IP ranges used by Tuist. This is common when Tuist needs to communicate with services behind a firewall or VPN, such as self-hosted Git providers or artifact storage, or when your GitHub organization uses [IP allow lists](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

Allowlist the Tuist IP range and the server addresses below. If your workflows run on <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, also allowlist the runner addresses.

### Tuist IP range {#tuist-ip-range}

Tuist operates its own network under [AS218377](https://stat.ripe.net/AS218377), registered to Tuist GmbH in the RIPE Database. macOS jobs on Tuist Runners hosted in Tuist's own racks already reach the internet from this range, and the rest of Tuist's traffic is moving to it. Add it to your allowlist so the move requires no changes on your side.

| IP version | CIDR notation |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

> [!NOTE]
> Add the IPv6 range if your allowlist supports IPv6 entries.

The ranges are located in Berlin, Germany. Their location is published as an [RFC 8805](https://www.rfc-editor.org/rfc/rfc8805) geofeed at [tuist.dev/geofeed.csv](https://tuist.dev/geofeed.csv) and referenced from their RIPE Database objects, so geolocation services and location-based routing place them correctly.

### Server IP addresses {#server-ip-addresses}

Outbound network traffic from Tuist services, such as the server and its integrations, currently originates from a fixed, reserved set of stable IP addresses. Allowlist every address in the set: it is sized so we can grow capacity or fail over between addresses without you having to change your allowlist.

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

> [!TIP]
> Add all of the addresses above to your allowlist to ensure uninterrupted connectivity with Tuist services.

Tuist only connects to your infrastructure over HTTPS, so you only need to allow HTTPS traffic (TCP port 443, or the port your HTTPS endpoint listens on) from these addresses. Tuist does not need SSH access.

### Tuist Runners {#tuist-runners}

Jobs that run on <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> use the outbound addresses below. If a job needs to reach infrastructure that restricts traffic by IP address, for example to check out a repository from a GitHub organization with an IP allow list, allowlist the addresses or ranges for every platform your workflows run on.

#### macOS {#tuist-runners-macos}

macOS jobs on Tuist's own racks reach the internet from the [Tuist IP range](#tuist-ip-range). Jobs on other macOS hosts use the following addresses.

| IP address | CIDR notation |
|---|---|
| 62.210.150.71 | `62.210.150.71/32` |
| 62.210.150.138 | `62.210.150.138/32` |
| 62.210.150.147 | `62.210.150.147/32` |
| 62.210.150.178 | `62.210.150.178/32` |
| 62.210.193.23 | `62.210.193.23/32` |
| 62.210.193.35 | `62.210.193.35/32` |
| 62.210.193.45 | `62.210.193.45/32` |
| 62.210.194.9 | `62.210.194.9/32` |
| 62.210.194.25 | `62.210.194.25/32` |
| 62.210.194.125 | `62.210.194.125/32` |
| 62.210.194.173 | `62.210.194.173/32` |
| 62.210.195.116 | `62.210.195.116/32` |

#### Linux {#tuist-runners-linux}

Linux runner jobs reach the internet from the following reserved IPv4 range. Allowlist the entire range so your workflows continue connecting as the fleet grows or hosts are replaced.

| IP version | CIDR notation |
|---|---|
| IPv4 | `5.135.7.160/27` |

> [!NOTE]
> This range is allocated through OVHcloud and is separate from the [Tuist IP range](#tuist-ip-range) used by rack-hosted macOS jobs.

<!--
MAINTAINERS: the server table is the customer-facing contract for the reserved
egress set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.

The rack's Mac minis leave from `management.edge.wan.egress.prefix` in
infra/rack-switch-fleet/sites/ber1.json, inside the Tuist IP range, so the
macOS table lists only the rented hosts. A new rack site has to egress from
the range too, or its address has to be added to the table.

The Tuist IP range is registered to ORG-TG278-RIPE (LIR de.tuist) and announced
from AS218377. Only list a prefix here once it is registered to Tuist GmbH in
the RIPE Database with a route/route6 object and a ROA for AS218377.
Add it to server/priv/static/geofeed.csv too, with the location of the site
that announces it.

The Linux range must match `capi.ovhRunnerEgress.cidr` in
infra/helm/tuist/values-managed-production.yaml. Publish this range-only guide
with the production cutover after verifying every runner on the new block.
Rollback to primary IPs requires restoring the old allowlist entries; see the
internal OVH runner egress runbook. This OVH allocation is not an AS218377 announcement
and must not be added to the Tuist-owned range table or geofeed.
-->
