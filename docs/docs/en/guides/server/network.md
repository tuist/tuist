---
{
  "title": "Network",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Network configuration for Tuist, including outbound IP address ranges."
}
---
# Network {#network}

This page covers network-related configuration that may be needed when integrating Tuist with your infrastructure.

## Outbound IP addresses {#outbound-ip-addresses}

If your infrastructure restricts inbound traffic by IP address, you may need to allowlist the IP ranges used by Tuist. This is common when Tuist needs to communicate with services behind a firewall or VPN, such as self-hosted Git providers or artifact storage, or when your GitHub organization uses [IP allow lists](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

Tuist outbound network traffic can originate from one of the following IP address ranges:

| IP range | CIDR notation |
|---|---|
| 74.220.51.0 – 74.220.51.255 | `74.220.51.0/24` |
| 74.220.59.0 – 74.220.59.255 | `74.220.59.0/24` |

::: tip
Add both ranges to your allowlist to ensure uninterrupted connectivity with Tuist services.
:::
