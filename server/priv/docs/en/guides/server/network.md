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

Outbound network traffic from Tuist services, such as the server and its integrations, originates from a fixed, reserved set of stable IP addresses. Allowlist every address in the set: Tuist will only ever egress from within it, and the set is sized so we can grow capacity or fail over between addresses without you having to change your allowlist.

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

> [!TIP]
> Add all of the addresses above to your allowlist to ensure uninterrupted connectivity with Tuist services.

Tuist only connects to your infrastructure over HTTPS, so you only need to allow HTTPS traffic (TCP port 443, or the port your HTTPS endpoint listens on) from these addresses. Tuist does not need SSH access.

### Tuist Runners {#tuist-runners}

Jobs that run on macOS <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> reach the internet directly from the machine they run on, not through the addresses above. If a job needs to reach infrastructure that restricts traffic by IP address, for example to check out a repository from a GitHub organization with an IP allow list, also allowlist the following addresses:

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

> [!NOTE]
> This list changes when we add machines to the fleet. We are moving the runners to a dedicated IP range so the list stays stable.

These addresses belong to the machines in the fleet, which run jobs from every account that uses Tuist Runners. Allowlisting them also lets other accounts' jobs reach your infrastructure.

#### Dedicated egress address {#dedicated-egress-address}

If your account needs a stable address that only its jobs use, for example for a GitHub organization IP allow list, a dedicated egress address is available on the **Enterprise plan**. Your jobs then reach the internet only from that address. [Contact us](mailto:contact@tuist.dev) to set it up.

<!--
MAINTAINERS: the first table is the customer-facing contract for the reserved egress
set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.
-->

