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

Tuist outbound network traffic that reaches customer infrastructure originates from a fixed, reserved set of stable IP addresses. Allowlist every address in the set: Tuist will only ever egress from within it, and the set is sized so we can grow capacity or fail over between addresses without you having to change your allowlist.

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |

> [!TIP]
> Add all of the addresses above to your allowlist to ensure uninterrupted connectivity with Tuist services.

<!--
MAINTAINERS: this table is the customer-facing contract for the reserved egress
set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.
-->

