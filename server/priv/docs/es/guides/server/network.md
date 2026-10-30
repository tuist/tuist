---
{
  "title": "Red",
  "titleTemplate": ":title | Server | Guías | Tuist",
  "description": "Configuración de red para Tuist, incluidas las direcciones IP salientes."
}
---
# Red {#network}

Esta página cubre la configuración relacionada con la red que puede ser necesaria al integrar Tuist con tu infraestructura.

## Direcciones IP de salida {#outbound-ip-addresses}

Si tu infraestructura restringe el tráfico entrante por dirección IP, es posible que debas incluir en la lista blanca los rangos de IP utilizados por Tuist. Esto es común cuando Tuist necesita comunicarse con servicios detrás de un firewall o VPN, como proveedores de Git autoalojados o almacenamiento de artefactos, o cuando tu organización de GitHub utiliza [listas blancas de IP](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization).

Incluye en la lista blanca las direcciones del servidor para las integraciones de Tuist y las direcciones de los runners para cada plataforma que utilicen tus flujos de trabajo.

### Direcciones IP del servidor {#server-ip-addresses}

Incluye en la lista blanca ambas direcciones para las conexiones desde los servicios e integraciones de Tuist:

| Dirección IP | Notación CIDR |
|---|---|
| 116.202.0.10 | `116.202.0.10/32` |
| 116.202.4.195 | `116.202.4.195/32` |

Tuist solo se conecta a tu infraestructura a través de HTTPS, por lo que solo necesitas permitir el tráfico HTTPS (puerto TCP 443, o el puerto en el que escuche tu endpoint HTTPS) desde estas direcciones. Tuist no necesita acceso SSH.

### Runners de Tuist {#tuist-runners}

Los trabajos que se ejecutan en <.localized_link href="/guides/features/runners">Runners de Tuist</.localized_link> utilizan las direcciones de salida indicadas a continuación. Si un trabajo necesita acceder a una infraestructura que restringe el tráfico por dirección IP, por ejemplo, para clonar un repositorio de una organización de GitHub con una lista blanca de IP, incluye en la lista blanca las direcciones o rangos de todas las plataformas en las que se ejecuten tus flujos de trabajo.

#### macOS {#tuist-runners-macos}

Incluye en la lista blanca los siguientes rangos para los trabajos de runners en macOS:

| Versión de IP | Notación CIDR |
|---|---|
| IPv4 | `95.130.119.0/24` |
| IPv6 | `2a11:83c0::/29` |

#### Linux {#tuist-runners-linux}

Incluye en la lista blanca todo el rango para los trabajos de runners en Linux:

| Versión de IP | Notación CIDR |
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
