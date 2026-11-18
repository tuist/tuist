---
{
  "title": "Сеть",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Настройка сети для Tuist, включая исходящие IP-адреса."
}
---
# Сеть {#network}

На этой странице описана конфигурация сети, которая может потребоваться при интеграции Tuist с вашей инфраструктурой.

## Исходящие IP-адреса {#outbound-ip-addresses}

Если ваша инфраструктура ограничивает входящий трафик по IP-адресам, возможно, потребуется добавить диапазоны IP-адресов Tuist в список разрешённых. Это часто необходимо, когда Tuist должен взаимодействовать со службами за файрволом или VPN, например с самостоятельно размещаемыми Git-провайдерами или хранилищами артефактов, либо когда ваша организация GitHub использует [списки разрешённых IP-адресов](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

Добавьте в список разрешённых адреса серверов для интеграций Tuist и адреса раннеров для каждой платформы, используемой вашими рабочими процессами.

### IP-адреса сервера {#server-ip-addresses}

Добавьте в список разрешённых оба адреса для подключений от служб и интеграций Tuist:

| IP-адрес | Запись CIDR |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist подключается к вашей инфраструктуре только по HTTPS, поэтому нужно разрешить HTTPS-трафик (TCP-порт 443 или порт, на котором слушает ваша HTTPS-точка) с этих адресов. Доступ по SSH не требуется.

### Туист Раннеры {#tuist-runners}

Задачи, выполняемые на <.localized_link href="/guides/features/runners">Туист Раннерах</.localized_link>, используют указанные ниже исходящие адреса. Если задаче нужно обратиться к инфраструктуре, которая ограничивает трафик по IP-адресам, например для клонирования репозитория из организации GitHub со списком разрешённых IP-адресов, добавьте в список разрешённых адреса или диапазоны для всех платформ, на которых работают ваши рабочие процессы.

#### macOS {#tuist-runners-macos}

Добавьте в список разрешённых следующие диапазоны для задач на macOS-раннерах:

| Версия IP | Запись CIDR |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Добавьте в список разрешённых весь диапазон для задач на Linux-раннерах:

| Версия IP | Запись CIDR |
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
