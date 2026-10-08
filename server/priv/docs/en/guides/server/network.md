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

### Tuist server {#tuist-server}

Outbound traffic from the Tuist server, such as the <.localized_link href="/guides/integrations/gitforge/github">GitHub integration</.localized_link>, originates from a fixed, reserved set of stable IP addresses. Allowlist every address in the set: the server will only ever egress from within it, and the set is sized so we can grow capacity or fail over between addresses without you having to change your allowlist.

| IP address | CIDR notation |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

> [!TIP]
> Add all of the addresses above to your allowlist to ensure uninterrupted connectivity with Tuist services.

### Tuist Runners {#tuist-runners}

Jobs on <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> reach the internet from the public IP address of the host they run on, not from the server addresses above. If your workflows check out code or reach services behind an IP allowlist, for example a GitHub organization with an IP allow list, allowlist the runner addresses too.

| Platform | IP address | CIDR notation |
|---|---|---|
| macOS | 62.210.150.71 | `62.210.150.71/32` |
| macOS | 62.210.150.138 | `62.210.150.138/32` |
| macOS | 62.210.150.147 | `62.210.150.147/32` |
| macOS | 62.210.150.178 | `62.210.150.178/32` |
| macOS | 62.210.193.23 | `62.210.193.23/32` |
| macOS | 62.210.193.35 | `62.210.193.35/32` |
| macOS | 62.210.193.45 | `62.210.193.45/32` |
| macOS | 62.210.194.9 | `62.210.194.9/32` |
| macOS | 62.210.194.25 | `62.210.194.25/32` |
| macOS | 62.210.194.125 | `62.210.194.125/32` |
| macOS | 62.210.194.173 | `62.210.194.173/32` |
| macOS | 62.210.195.116 | `62.210.195.116/32` |
| Linux | 51.255.75.64 | `51.255.75.64/32` |
| Linux | 51.255.75.145 | `51.255.75.145/32` |
| Linux | 51.255.75.147 | `51.255.75.147/32` |
| Linux | 51.255.75.149 | `51.255.75.149/32` |
| Linux | 51.255.75.186 | `51.255.75.186/32` |
| Linux | 51.255.93.93 | `51.255.93.93/32` |
| Linux | 217.182.192.213 | `217.182.192.213/32` |
| Linux | 217.182.192.222 | `217.182.192.222/32` |
| Linux | 217.182.192.227 | `217.182.192.227/32` |
| Linux | 217.182.193.152 | `217.182.193.152/32` |

> [!WARNING]
> This list changes when we add or replace runner hosts. Check this page again if a runner job starts failing with an IP allowlist error.

<!--
MAINTAINERS: this table is the customer-facing contract for the reserved egress
set. It must stay in lockstep with `ciliumEgressGateway.server.failoverController.egressIpAllowlist`
in infra/helm/platform/values-tuist.yaml (the controller fails closed if the
active Floating IP is outside that allowlist). When reserving additional
Floating IPs in the tuist-workloads project, add their /32s to BOTH places
*before* they are ever used as egress.

The Tuist Runners table lists the public addresses of the production
`*-runners-fleet-*` ScalewayAppleSiliconMachines (macOS) and
`*-ovh-fleet-runners-linux-*` OVHDedicatedMachines (Linux). Runner jobs egress
from their host directly, so update the table whenever those Machines are added
or replaced:
  kubectl --context tuist-k8s-production get machines -n tuist
-->

