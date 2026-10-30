---
{
  "title": "ネットワーク",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "送信元IPアドレスなど、Tuistのネットワーク設定。"
}
---
# ネットワーク {#network}

このページでは、Tuist をインフラストラクチャと統合する際に必要となる可能性のあるネットワーク関連の設定について説明します。

## 送信元 IP アドレス {#outbound-ip-addresses}

インフラストラクチャで IP アドレスによる受信トラフィックの制限を行っている場合、Tuist が使用する IP 範囲を許可リストに追加する必要があります。これは、Tuist がファイアウォールや VPN の背後にあるサービス（セルフホスト型の Git プロバイダーやアーティファクトストレージなど）と通信する必要がある場合や、GitHub Organization で [IP 許可リスト](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) を使用している場合に一般的です。

Tuist の統合に使用するサーバーアドレスと、ワークフローが利用する各プラットフォームのランナーアドレスを許可リストに追加してください。

### サーバーの IP アドレス {#server-ip-addresses}

Tuist のサービスおよび統合からの接続用に、以下の両方のアドレスを許可リストに追加してください：

| IP アドレス | CIDR 表記 |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist は HTTPS 経由でのみインフラストラクチャに接続するため、これらのアドレスからの HTTPS トラフィック（TCP ポート 443、または HTTPS エンドポイントがリッスンしているポート）のみを許可すれば十分です。Tuist に SSH アクセスは不要です。

### Tuist Runners {#tuist-runners}

<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> で実行されるジョブは、以下の送信元アドレスを使用します。ジョブが IP アドレスでトラフィックを制限するインフラストラクチャ（例えば、IP 許可リストを設定した GitHub Organization からリポジトリをチェックアウトする場合など）にアクセスする必要がある場合は、ワークフローが実行されるすべてのプラットフォームに対応するアドレスまたは範囲を許可リストに追加してください。

#### macOS {#tuist-runners-macos}

macOS ランナーのジョブ用に、以下の範囲を許可リストに追加してください：

| IP バージョン | CIDR 表記 |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Linux ランナーのジョブ用に、以下の範囲全体を許可リストに追加してください：

| IP バージョン | CIDR 表記 |
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
