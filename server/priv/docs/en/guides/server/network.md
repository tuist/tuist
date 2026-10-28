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

Allowlist the server addresses for Tuist integrations and the runner addresses for each platform your workflows use.

### Server IP addresses {#server-ip-addresses}

Allowlist both addresses for connections from Tuist services and integrations:

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist only connects to your infrastructure over HTTPS, so you only need to allow HTTPS traffic (TCP port 443, or the port your HTTPS endpoint listens on) from these addresses. Tuist does not need SSH access.

### Tuist Runners {#tuist-runners}

Jobs that run on <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> use the outbound addresses below. If a job needs to reach infrastructure that restricts traffic by IP address, for example to check out a repository from a GitHub organization with an IP allow list, allowlist the addresses or ranges for every platform your workflows run on.

#### macOS {#tuist-runners-macos}

Allowlist the following ranges for macOS runner jobs:

| IP version | CIDR notation |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Allowlist the entire range for Linux runner jobs:

| IP version | CIDR notation |
|---|---|
| IPv4 | `5.135.7.160/27` |

<!--
MAINTAINERS: the server table is the customer-facing contract for the reserved
egress set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.

The macOS IPv4 range is configured in infra/rack-switch-fleet/sites/ber1.json.
The public allowlist excludes Scaleway hosts; reassess it before using them
for runner jobs again.

The Linux range must match `capi.ovhRunnerEgress.cidr` in
infra/helm/tuist/values-managed-production.yaml. Publish this range-only guide
with the production cutover after verifying every runner on the new block.
Rollback to primary IPs requires restoring the old allowlist entries; see the
internal OVH runner egress runbook.
-->
