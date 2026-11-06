---
{
  "title": "Ağ",
  "titleTemplate": ":title | Server | Kılavuzlar | Tuist",
  "description": "Giden IP adresleri dahil olmak üzere Tuist için ağ yapılandırması."
}
---
# Ağ {#network}

Bu sayfa, Tuist'i altyapınızla entegre ederken ihtiyaç duyulabilecek ağ ile ilgili yapılandırmaları kapsar.

## Giden IP adresleri {#outbound-ip-addresses}

Altyapınız gelen trafiği IP adresine göre kısıtlıyorsa, Tuist tarafından kullanılan IP aralıklarını izin listesine eklemeniz gerekebilir. Bu durum, Tuist'in güvenlik duvarı veya VPN arkasındaki hizmetlerle (örneğin kendi kendine barındırılan Git sağlayıcıları veya yapıt depolama) iletişim kurması gerektiğinde veya GitHub kuruluşunuz [IP izin listeleri](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) kullandığında yaygındır.

Tuist entegrasyonları için sunucu adreslerini ve iş akışlarınızın kullandığı her platform için çalıştırıcı adreslerini izin listesine ekleyin.

### Sunucu IP adresleri {#server-ip-addresses}

Tuist hizmetlerinden ve entegrasyonlarından gelen bağlantılar için her iki adresi de izin listesine ekleyin:

| IP adresi | CIDR gösterimi |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist altyapınıza yalnızca HTTPS üzerinden bağlanır, bu nedenle bu adreslerden yalnızca HTTPS trafiğine (TCP port 443 veya HTTPS uç noktanızın dinlediği port) izin vermeniz yeterlidir. Tuist'in SSH erişimine ihtiyacı yoktur.

### Tuist Çalıştırıcıları {#tuist-runners}

<.localized_link href="/guides/features/runners">Tuist Çalıştırıcıları</.localized_link> üzerinde çalışan işler aşağıdaki giden adresleri kullanır. Bir işin, örneğin IP izin listesine sahip bir GitHub kuruluşundan bir depoyu çekmek gibi, trafiği IP adresine göre kısıtlayan bir altyapıya erişmesi gerekiyorsa, iş akışlarınızın çalıştığı her platform için adresleri veya aralıkları izin listesine ekleyin.

#### macOS {#tuist-runners-macos}

macOS çalıştırıcı işleri için aşağıdaki aralıkları izin listesine ekleyin:

| IP sürümü | CIDR gösterimi |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Linux çalıştırıcı işleri için tüm aralığı izin listesine ekleyin:

| IP sürümü | CIDR gösterimi |
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
