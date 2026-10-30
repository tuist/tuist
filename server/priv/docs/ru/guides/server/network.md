---
{
  "title": "Сеть",
  "titleTemplate": ":title | Server | Руководства | Tuist",
  "description": "Настройка сети для Tuist, включая исходящие IP-адреса."
}
---
# Сеть {#network}

На этой странице описана конфигурация сети, которая может потребоваться при интеграции Tuist с вашей инфраструктурой.

## Исходящие IP-адреса {#outbound-ip-addresses}

Если ваша инфраструктура ограничивает входящий трафик по IP-адресу, возможно, потребуется добавить в белый список диапазоны IP-адресов, используемые Tuist. Это часто необходимо, когда Tuist должен взаимодействовать со службами за межсетевым экраном или VPN, такими как самостоятельно размещаемые Git-провайдеры или хранилища артефактов, либо когда ваша организация GitHub использует [списки разрешенных IP-адресов](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

Добавьте в белый список адреса серверов для интеграций Tuist и адреса раннеров для каждой платформы, которую используют ваши рабочие процессы.

### IP-адреса сервера {#server-ip-addresses}

Добавьте в белый список оба адреса для подключений от сервисов и интеграций Tuist:

| IP-адрес | Обозначение CIDR |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist подключается к вашей инфраструктуре только по HTTPS, поэтому нужно разрешить HTTPS-трафик (TCP-порт 443 или порт, на котором слушает ваша HTTPS-точка входа) с этих адресов. Доступ по SSH Tuist не требуется.

### Туист Раннеры {#tuist-runners}

Задачи, выполняемые на <.localized_link href="/guides/features/runners">Туист Раннерах</.localized_link>, используют указанные ниже исходящие адреса. Если задаче нужно обратиться к инфраструктуре, которая ограничивает трафик по IP-адресу, например для клонирования репозитория из организации GitHub со списком разрешенных IP-адресов, добавьте в белый список адреса или диапазоны для каждой платформы, на которой работают ваши рабочие процессы.

#### macOS {#tuist-runners-macos}

Добавьте в белый список следующие диапазоны для задач раннеров macOS:

| Версия IP | Обозначение CIDR |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Добавьте в белый список весь диапазон для задач раннеров Linux:

| Версия IP | Обозначение CIDR |
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
