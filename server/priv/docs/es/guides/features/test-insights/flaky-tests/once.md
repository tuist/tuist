---
{
  "title": "Tests inestables de Once",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta e investiga tests inestables de Once utilizando los intentos de reintento reportados y el historial de CI."
}
---
# Tests inestables de Once {#once-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - Configura <.localized_link href="/guides/features/test-insights/once">Análisis de tests de Once</.localized_link> con resultados estructurados por caso de test.

<!-- @snippet: ./_intro -->

## Cómo funciona la detección de inestabilidad {#how-it-works}

### Reintentos de tests {#test-retries}

Cuando un runner informa varios intentos para el mismo test, Tuist los conserva. Un test que falla y luego pasa se reporta como inestable; uno que sigue fallando permanece como fallo. Habilita los reintentos en el runner subyacente cuando sea compatible. Conectar Once a Tuist no añade automáticamente reintentos a cada destino de test.

### Detección entre ejecuciones {#cross-run-detection}

El historial compartido de tests también permite a Tuist comparar resultados exitosos y fallidos del mismo test y commit en CI. Once debe reportar el contexto del commit y de CI para esta comparación; las ejecuciones locales siguen siendo visibles sin convertirse en evidencia automática de inestabilidad entre ejecuciones.

Los casos se identifican por el destino nativo, la suite y el nombre del caso. Mantén esas identidades estables para preservar su historial y utiliza informes completos por caso en lugar de inferir la fiabilidad a partir del resultado global de un destino.

## Investigar tests inestables {#investigate-flaky-tests}

Abre el historial del caso de test en Tuist para comparar sus intentos, fallos y los commits de CI afectados. Las consultas compartidas de tests también están disponibles a través de las <.localized_link href="/guides/features/agentic-coding/mcp">herramientas de Model Context Protocol</.localized_link>, de modo que un agente de programación pueda investigar los mismos resultados reportados.

## Gestionar tests inestables {#managing-flaky-tests}

Puedes marcar o desmarcar un test como inestable desde su página de detalles mientras investigas un fallo. La automatización predeterminada de detección de tests inestables también borra la marca tras su ventana de recuperación, normalmente 14 días sin otro desencadenante.

Los proyectos de Once no exponen actualmente una pestaña de configuración de **Automatizaciones**. La detección y el estado de test almacenado están disponibles, pero el flujo de configuración documentado para sistemas de compilación con aplicación de cuarentena aún no está expuesto para Once.

## Cuarentena {#quarantining}

Tuist puede atribuir los casos reportados a su estado de cuarentena almacenado, pero el cliente nativo de Once no recupera ni aplica actualmente las políticas de **Silenciado** o **Omitido** de Tuist. Cambiar ese estado en Tuist no impide que Once ejecute el test ni hace que su fallo deje de bloquear la CI.

Utiliza la política de filtrado o de fallos propia de tu runner cuando necesites cuarentena en tiempo de ejecución. No confíes únicamente en el estado del panel para cambiar el código de salida del comando.

## Notificaciones de Slack {#slack-notifications}

Los proyectos de Once no exponen actualmente el flujo de configuración del proyecto para alertas de Slack sobre tests inestables. Usa las consultas compartidas de tests a continuación para integrar el estado de inestabilidad reportado con tus propias notificaciones.

<!-- @snippet: ./_querying -->
