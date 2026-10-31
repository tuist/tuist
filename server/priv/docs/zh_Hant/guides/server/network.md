---
{
  "title": "網路",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Tuist 的網路設定，包含出站 IP 位址。"
}
---
# 網路 {#network}

本頁說明在將 Tuist 與你的基礎設施整合時，可能需要的網路相關設定。

## 出站 IP 位址 {#outbound-ip-addresses}

如果你的基礎設施依 IP 位址限制入站流量，你可能需要將 Tuist 使用的 IP 範圍加入允許清單。當 Tuist 需要與防火牆或 VPN 後方的服務（例如自託管的 Git 提供者或構件儲存空間）通訊，或當你的 GitHub 組織使用 [IP 允許清單](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) 時，這種情況很常見。

將 Tuist 整合的伺服器位址，以及工作流程所用各平台的執行器位址加入允許清單。

### 伺服器 IP 位址 {#server-ip-addresses}

將以下兩個位址加入允許清單，以允許來自 Tuist 服務與整合的連線：

| IP 位址 | CIDR 標記法 |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist 僅透過 HTTPS 連線到你的基礎設施，因此你只需允許來自這些位址的 HTTPS 流量（TCP 連接埠 443，或你的 HTTPS 端點監聽的連接埠）。Tuist 不需要 SSH 存取權。

### Tuist Runners {#tuist-runners}

在 <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> 上執行的工作會使用下方的出站位址。如果工作需要存取依 IP 位址限制流量的基礎設施（例如從具有 IP 允許清單的 GitHub 組織檢出儲存庫），請將工作流程所執行的每個平台對應的位址或範圍加入允許清單。

#### macOS {#tuist-runners-macos}

將以下範圍加入允許清單，以供 macOS 執行器工作使用：

| IP 版本 | CIDR 標記法 |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

將整個範圍加入允許清單，以供 Linux 執行器工作使用：

| IP 版本 | CIDR 標記法 |
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
