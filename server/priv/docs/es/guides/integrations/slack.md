---
{
  "title": "Slack",
  "titleTemplate": ":title | Integraciones | Guías | Tuist",
  "description": "Aprende a usar la integración de Tuist para Slack."
}
---
# Integración de Tuist para Slack {#slack}

La integración de Tuist para Slack muestra información sobre compilaciones, tests y paquetes directamente en tus canales. Convierte el monitoreo de algo que tu equipo debe recordar hacer en algo que ocurre automáticamente. Por ejemplo, tu equipo puede recibir resúmenes diarios del rendimiento de las compilaciones, tasas de aciertos de caché o tendencias del tamaño de los paquetes, así como alertas instantáneas en el momento en que una métrica clave se degrada o un test se vuelve inestable.

Esta página describe qué hace la integración, cómo instalarla canal por canal y cómo gestiona Tuist tus datos. Para más detalles sobre cómo Tuist recopila, gestiona y almacena datos de terceros, consulta nuestra [política de privacidad](https://tuist.dev/privacy).

## Cómo funciona la integración {#how-it-works}

Tuist envía notificaciones a Slack mediante los [Incoming Webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks) de Slack. La integración solo solicita el ámbito `incoming-webhook`. Cada destino de notificación (informe del proyecto, regla de alerta, alerta de test inestable, acción de automatización) corresponde a un único canal de Slack que eliges durante la instalación. Slack crea una URL de webhook por canal y Tuist la almacena para entregar los mensajes.

Tuist nunca lee mensajes, listas de miembros ni ningún otro dato de tu espacio de trabajo. La integración solo escribe notificaciones en los canales que has autorizado explícitamente.

## Configuración {#setup}

### Informes del proyecto {#project-reports}

Los informes del proyecto entregan un resumen diario de las métricas de compilación, test y caché de tu proyecto en un canal de Slack de tu elección.

1. Abre la configuración de notificaciones de tu proyecto en el panel de Tuist.
2. Haz clic en **Seleccionar canal de Slack** y elige el espacio de trabajo y el canal en el que quieres que Tuist publique. Slack te pedirá que autorices el ámbito `incoming-webhook` y selecciones un único canal.
3. Elige los días de la semana y la hora del día en la que quieres recibir el informe diario.

![Una imagen que muestra la configuración de notificaciones con el informe de Slack](/images/guides/integrations/slack/notifications-settings.png)

Una vez configurado, Tuist envía informes diarios automáticos al canal seleccionado:

<img src="/images/guides/integrations/slack/report.png" alt="Una imagen que muestra un mensaje de informe de Slack" style="max-width: 500px;" />

> [!NOTE] PRIVATE CHANNELS
> <!-- -->
> Para publicar en un canal privado, abre primero el canal dentro de Slack y añádelo a la lista de canales visibles para la integración durante el paso de autorización.
> <!-- -->

### Reglas de alerta {#alert-rules}

Las reglas de alerta te notifican en Slack cuando las métricas clave se degradan significativamente, ayudándote a detectar compilaciones más lentas, degradación de la caché o ralentizaciones en los tests lo antes posible.

Para crear una regla de alerta, ve a la configuración de notificaciones de tu proyecto y haz clic en **Añadir regla de alerta**. Puedes configurar:

- **Nombre**: Un nombre descriptivo para la alerta
- **Categoría**: Qué medir (duración de la compilación, duración de los tests, tasa de aciertos de caché o tamaño del paquete)
- **Métrica**: Cómo agregar los datos (p50, p90, p99 o promedio)
- **Desviación**: El porcentaje de cambio que desencadena una alerta
- **Ventana deslizante**: Cuántas ejecuciones recientes comparar
- **Rama**: Para las alertas de tasa de aciertos de caché, restringe la comparación a las ejecuciones de una única rama. Déjalo vacío para considerar todas las ramas. Las alertas de tamaño de paquete siempre apuntan a una única rama.
- **Canal de Slack**: El canal de destino. Autorizas el canal mediante el mismo flujo de `incoming-webhook` descrito anteriormente.

Por ejemplo, podrías crear una alerta que se active cuando la duración de compilación p90 aumente más de un 20 % en comparación con las 100 compilaciones anteriores.

Limitar una alerta de tasa de aciertos de caché a tu rama predeterminada es útil cuando solo esa rama alimenta la caché. Las ramas de pull request que tocan un módulo de bajo nivel no encuentran la caché legítimamente, e incluirlas haría que la alerta se disparara ante regresiones esperadas.

Una alerta de tasa de aciertos de caché solo compara ventanas que pueda comparar de forma justa. Ambas ventanas deben contener tantas ejecuciones como el tamaño de la ventana deslizante, y una fuente de datos de caché que solo aparezca en una de las dos ventanas se excluye de ambas. Por lo tanto, una rama que aún no haya acumulado el doble del tamaño de la ventana deslizante en ejecuciones, o un nombre de rama que no coincida con nada, nunca activará la regla. Si limitas una regla a una rama con poco tráfico, mantén la ventana deslizante lo suficientemente pequeña para que la rama la llene.

Cuando se activa una alerta, recibirás un mensaje como este en tu canal de Slack:

<img src="/images/guides/integrations/slack/alert.png" alt="Una imagen que muestra un mensaje de alerta de Slack" style="max-width: 500px;" />

> [!NOTE] COOLDOWN PERIOD
> <!-- -->
> Después de que se active una alerta, no volverá a dispararse para la misma regla durante 24 horas. Esto evita la fatiga por notificaciones cuando una métrica se mantiene elevada.
> <!-- -->

### Alertas de tests inestables {#flaky-test-alerts}

Las alertas de tests inestables se activan en el momento en que Tuist detecta un nuevo test inestable, ayudándote a detectar la inestabilidad de los tests antes de que afecte a tu equipo.

Para crear una regla de alerta de test inestable, ve a la configuración de notificaciones de tu proyecto y haz clic en **Añadir regla de alerta de test inestable**. Puedes configurar:

- **Nombre**: Un nombre descriptivo para la alerta
- **Umbral de activación**: El número mínimo de ejecuciones inestables en los últimos 30 días necesario para activar una alerta
- **Canal de Slack**: El canal de destino, autorizado mediante el flujo de `incoming-webhook`.

Cuando un test se vuelve inestable y cumple tu umbral, recibirás una notificación con un enlace directo para investigar el caso de test:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="Una imagen que muestra un mensaje de alerta de test inestable de Slack" style="max-width: 500px;" />

## Desconectar la integración {#disconnect}

Para detener una notificación, elimina el canal de Slack configurado del informe, la regla de alerta o la acción de automatización en tu panel de Tuist. Para revocar completamente el acceso de Tuist, elimina la integración de webhook desde Slack a través de **Configuración y administración → Gestionar aplicaciones**.
