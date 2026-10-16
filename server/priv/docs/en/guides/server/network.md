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

Allowlist both the Tuist IP range and the server addresses below.

### Tuist IP range {#tuist-ip-range}

Tuist operates its own network under [AS218377](https://stat.ripe.net/AS218377), registered to Tuist GmbH in the RIPE Database. Traffic from Tuist, including <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, is moving to the following ranges. Add them to your allowlist now so the move requires no changes on your side.

| IP version | CIDR notation |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

> [!NOTE]
> Add the IPv6 range if your allowlist supports IPv6 entries.

### Server IP addresses {#server-ip-addresses}

Traffic from the Tuist server, such as Git forge integrations and webhooks, currently originates from the following addresses:

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

> [!TIP]
> Add all of the addresses above to your allowlist to ensure uninterrupted connectivity with Tuist services.

<!--
MAINTAINERS: the server table is the customer-facing contract for the reserved
egress set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.

The Tuist IP range is registered to ORG-TG278-RIPE (LIR de.tuist) and announced
from AS218377. Only list a prefix here once it is registered to Tuist GmbH in
the RIPE Database with a route/route6 object and a ROA for AS218377.
-->
