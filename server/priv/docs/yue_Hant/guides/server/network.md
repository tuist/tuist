---
{
  "title": "網絡",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist 的網絡設定，包括出站 IP 位址。"
}
---
# 網絡 {#network}

本頁介紹將 Tuist 與你的基礎設施整合時可能需要的網絡相關設定。

## 出站 IP 位址 {#outbound-ip-addresses}

如果你的基礎設施按 IP 位址限制入站流量，你可能需要將 Tuist 使用的 IP 範圍加入白名單。當 Tuist 需要與防火牆或 VPN 後方的服務（例如自託管 Git 供應商或構件儲存）通訊，或者你的 GitHub 組織使用 [IP 允許清單](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) 時，這種情況很常見。

將 Tuist 整合的伺服器位址，以及你的工作流程所用各平台的執行器位址加入白名單。

### 伺服器 IP 位址 {#server-ip-addresses}

將以下兩個位址加入白名單，以便 Tuist 服務和整合進行連線：

| IP 位址 | CIDR 表示法 |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist 只會透過 HTTPS 連線到你的基礎設施，因此你只需允許來自這些位址的 HTTPS 流量（TCP 連接埠 443，或你的 HTTPS 端點監聽的連接埠）。Tuist 不需要 SSH 存取權。

### Tuist Runners {#tuist-runners}

在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上執行的工作會使用以下的出站位址。如果工作需要連線到按 IP 位址限制流量的基礎設施（例如從設有 IP 允許清單的 GitHub 組織簽出儲存庫），請將你的工作流程所運行的每個平台的位址或範圍加入白名單。

#### macOS {#tuist-runners-macos}

將以下範圍加入 macOS 執行器工作的白名單：

| IP 版本 | CIDR 表示法 |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

將整個範圍加入 Linux 執行器工作的白名單：

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
