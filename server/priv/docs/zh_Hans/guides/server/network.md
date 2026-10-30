---
{
  "title": "网络",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist 的网络配置，包括出站 IP 地址。"
}
---
# 网络 {#network}

本页介绍将 Tuist 与你的基础设施集成时可能需要的网络相关配置。

## 出站 IP 地址 {#outbound-ip-addresses}

如果你的基础设施按 IP 地址限制入站流量，你可能需要将 Tuist 使用的 IP 范围加入允许列表。当 Tuist 需要与防火墙或 VPN 后面的服务通信（例如自托管的 Git 提供商或制品存储），或者你的 GitHub 组织使用 [IP 允许列表](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) 时，这种情况很常见。

将 Tuist 集成所需的服务器地址以及工作流所用各平台的运行器地址加入允许列表。

### 服务器 IP 地址 {#server-ip-addresses}

将以下两个地址加入允许列表，以支持来自 Tuist 服务和集成的连接：

| IP 地址 | CIDR 表示法 |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist 仅通过 HTTPS 连接到你的基础设施，因此你只需允许来自这些地址的 HTTPS 流量（TCP 端口 443，或你的 HTTPS 端点监听的端口）。Tuist 不需要 SSH 访问权限。

### Tuist Runners {#tuist-runners}

在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上运行的作业使用下面的出站地址。如果作业需要访问按 IP 地址限制流量的基础设施（例如从具有 IP 允许列表的 GitHub 组织检出代码库），请将工作流运行的每个平台对应的地址或范围加入允许列表。

#### macOS {#tuist-runners-macos}

将以下范围加入允许列表，以支持 macOS 运行器作业：

| IP 版本 | CIDR 表示法 |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

将整个范围加入允许列表，以支持 Linux 运行器作业：

| IP 版本 | CIDR 表示法 |
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
