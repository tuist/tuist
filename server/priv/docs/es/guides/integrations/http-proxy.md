---
{
  "title": "Proxy HTTP",
  "titleTemplate": ":title | Integraciones | Guías | Tuist",
  "description": "Aprende cómo Tuist enruta su tráfico HTTP a través de un proxy corporativo cuando se establece HTTPS_PROXY o HTTP_PROXY."
}
---
# Proxy HTTP {#http-proxy}

Cuando `HTTPS_PROXY` o `HTTP_PROXY` está definido en el entorno, Tuist enruta automáticamente a través de ese proxy las conexiones HTTP que gestiona. Esto aplica tanto a la CLI de Tuist como al plugin de Gradle de Tuist, sin necesidad de configuración adicional.

El comportamiento coincide con la convención usada por `curl`, `git` y la mayoría de herramientas para desarrolladores, por lo que cualquier entorno que ya defina estas variables para otras herramientas funciona con Tuist sin más ajustes.

## Qué se proxifica {#what-is-proxied}

Solo los clientes HTTP propiedad de Tuist se enrutan a través del proxy:

- los endpoints de caché, previews, analítica y registro,
- y las llamadas que el plugin de Gradle realiza a los servicios de Tuist (caché remota de compilación, análisis de compilaciones, análisis de tests, cuarentena de tests, distribución de tests).

## Orden de búsqueda de variables {#variable-lookup-order}

Tuist lee el primer valor no vacío en este orden:

1. `HTTPS_PROXY`
2. `https_proxy`
3. `HTTP_PROXY`
4. `http_proxy`

El valor debe ser una URL como `http://proxy.corp:8080`. Se admiten credenciales en línea (`http://user:password@proxy.corp:8080`).
