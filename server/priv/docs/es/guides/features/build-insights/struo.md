---
{
  "title": "Análisis de compilaciones de Struo",
  "titleTemplate": ":title · Análisis de compilaciones · Funcionalidades · Guías · Tuist",
  "description": "Sigue las ejecuciones de Struo en directo e inspecciona acciones, duraciones, fallos y decisiones de caché en el panel de control de Tuist."
}
---
# Análisis de compilaciones de Struo {#struo-build-insights}

<a id="once-build-insights"></a>

Struo envía las ejecuciones a Tuist mientras se ejecutan, para que puedas seguir el progreso sin esperar al registro final de CI. Abre el enlace del panel que se muestra al inicio de una ejecución para inspeccionar su gráfico, el estado de las acciones y las decisiones de caché.

> [!IMPORTANT]
> **Requisitos**
>
> - Completa <.localized_link href="/guides/get-started/struo-project">Primeros pasos con Struo</.localized_link> y autentica la máquina que ejecuta Struo.

## Informa de tus compilaciones {#report-your-builds}

Sigue usando tus comandos de Struo:

```bash
struo build MyApplication
```

El informe en tiempo real es de mejor esfuerzo. Un endpoint de informes no disponible o una sesión caducada no hace fallar la compilación. Vuelve a iniciar sesión con `struo auth login --provider tuist` si la sesión caduca.

## Qué muestra el panel {#what-the-dashboard-shows}

Usa **Compilaciones** y **Ejecuciones de compilación** para comparar ejecuciones a lo largo del tiempo, entre ramas y en entornos locales o de CI. Cada ejecución puede incluir:

- El comando solicitado, el estado, la hora de inicio y la duración.
- La versión de Struo y la información del host reportada.
- Acciones y sus dependencias, estado, duración y resultados de caché.
- Errores de acción reportados.
- Rama de Git, commit y contexto de CI cuando el cliente los reporta.

Busca y filtra las acciones para encontrar trabajo fallido o lento. Los nombres de acción y los archivos fuente reportados ayudan a vincular el trabajo con el código; los clientes más antiguos pueden proporcionar menos detalles. Las acciones en caché u omitidas no son trabajo ejecutado, y la falta de tiempos no es una ejecución de duración cero.

Tuist no ingiere actualmente el flujo de registros de acciones en bruto de Struo. Conserva los registros de CI para obtener la salida completa del proceso; los resúmenes de ejecución y los errores estructurados no sustituyen a esos registros.

La vista **Caché** separa las decisiones de acción de las transferencias de objetos de contenido. Consulta <.localized_link href="/guides/features/cache/struo">Caché de Struo</.localized_link> para interpretar la actividad de caché.

## Tests {#tests}

Los comandos de tests también generan ejecuciones de Struo. Sus suites y casos reportados aparecen bajo **Tests**; los shards alojados publican además una ejecución de tests combinada. Consulta <.localized_link href="/guides/features/test-insights/struo">Análisis de tests de Struo</.localized_link>.

## Agentes de programación y Grafana {#coding-agents-and-grafana}

Las <.localized_link href="/guides/features/agentic-coding/mcp#struo-runs">herramientas de Model Context Protocol</.localized_link> permiten que un agente liste ejecuciones de Struo y lea los totales de acciones y caché de una ejecución. Las mismas lecturas están disponibles a través de la API HTTP.

Usa la <.localized_link href="/guides/integrations/grafana">integración con Grafana</.localized_link> para métricas finales de salud de compilación de Struo. Struo no reporta actualmente los ahorros de tiempo de caché transcurrido, por lo que esa medición permanece como no disponible en lugar de cero.
