---
{
  "title": "네트워크",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "아웃바운드 IP 주소를 포함한 Tuist의 네트워크 구성입니다."
}
---
# 네트워크 {#network}

이 페이지에서는 Tuist를 인프라와 통합할 때 필요할 수 있는 네트워크 관련 구성을 다룹니다.

## 아웃바운드 IP 주소 {#outbound-ip-addresses}

인프라에서 IP 주소별로 인바운드 트래픽을 제한하는 경우, Tuist가 사용하는 IP 범위를 허용 목록에 추가해야 할 수 있습니다. 이는 Tuist가 방화벽이나 VPN 뒤의 서비스(예: 자체 호스팅 Git 제공자 또는 아티팩트 스토리지)와 통신해야 하거나, GitHub 조직에서 [IP 허용 목록](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization)을 사용할 때 흔히 발생합니다.

Tuist 통합을 위한 서버 주소와 워크플로가 사용하는 각 플랫폼의 러너 주소를 허용 목록에 추가하세요.

### 서버 IP 주소 {#server-ip-addresses}

Tuist 서비스 및 통합에서의 연결을 위해 다음 두 주소를 모두 허용 목록에 추가하세요:

| IP 주소 | CIDR 표기법 |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist는 HTTPS를 통해 인프라에만 연결하므로, 이러한 주소에서 HTTPS 트래픽(TCP 포트 443 또는 HTTPS 엔드포인트가 수신하는 포트)만 허용하면 됩니다. Tuist는 SSH 액세스가 필요하지 않습니다.

### Tuist Runners {#tuist-runners}

<.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>에서 실행되는 작업은 아래의 아웃바운드 주소를 사용합니다. 작업이 IP 주소별로 트래픽을 제한하는 인프라(예: IP 허용 목록이 설정된 GitHub 조직에서 리포지토리를 체크아웃해야 하는 경우)에 접근해야 한다면, 워크플로가 실행되는 모든 플랫폼에 대한 주소 또는 범위를 허용 목록에 추가하세요.

#### macOS {#tuist-runners-macos}

macOS 러너 작업을 위해 다음 범위를 허용 목록에 추가하세요:

| IP 버전 | CIDR 표기법 |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Linux 러너 작업을 위해 전체 범위를 허용 목록에 추가하세요:

| IP 버전 | CIDR 표기법 |
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
