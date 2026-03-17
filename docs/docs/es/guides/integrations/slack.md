---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Integración con Slack {#slack}

Si tu organización utiliza Slack, puedes integrar Tuist para mostrar información
directamente en tus canales. Esto convierte la supervisión de algo que tu equipo
tiene que acordarse de hacer en algo que simplemente ocurre. Por ejemplo, tu
equipo puede recibir resúmenes diarios del rendimiento de las compilaciones, las
tasas de aciertos de caché o las tendencias en el tamaño de los paquetes.

## Configuración {#setup}

### Conecta tu espacio de trabajo de Slack {#connect-workspace}

En primer lugar, conecta tu espacio de trabajo de Slack a tu cuenta de Tuist en
la pestaña «Integraciones» de `` :

![Una imagen que muestra la pestaña de integraciones con la conexión a
Slack](/images/guides/integrations/slack/integrations.png)

Haz clic en « **» (Conectar Slack)** para autorizar a Tuist a publicar mensajes
en tu espacio de trabajo. Esto te redirigirá a la página de autorización de
Slack, donde podrás aprobar la conexión.

> [!NOTA] APROBACIÓN DEL ADMINISTRADOR DE SLACK
> <!-- -->
> Si tu espacio de trabajo de Slack restringe la instalación de aplicaciones, es
> posible que tengas que solicitar la aprobación de un administrador de Slack.
> Slack te guiará a través del proceso de solicitud de aprobación durante la
> autorización.
> <!-- -->

### Informes de proyectos {#project-reports}

Después de conectar Slack, configura los informes para cada proyecto en la
pestaña de notificaciones de la configuración del proyecto:

![Una imagen que muestra la configuración de notificaciones con la configuración
de informes de
Slack](/images/guides/integrations/slack/notifications-settings.png)

Puedes configurar:
- **Canal**: Selecciona el canal de Slack que recibirá los informes
- **Programar**: Elige qué días de la semana quieres recibir los informes
- ****: Establece la hora del día

> [!ADVERTENCIA] CANALES PRIVADOS
> <!-- -->
> Para que la aplicación Tuist de Slack publique mensajes en un canal privado,
> primero debes añadir el bot de Tuist a ese canal. En Slack, abre el canal
> privado, haz clic en el nombre del canal para abrir la configuración,
> selecciona «Integraciones», luego «Añadir aplicaciones» y busca Tuist.
> <!-- -->

Una vez configurado, Tuist envía informes diarios automáticos al canal de Slack
que hayas seleccionado:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Reglas de alerta {#alert-rules}

Recibe notificaciones en Slack mediante reglas de alerta cuando las métricas
clave experimenten un retroceso significativo, lo que te ayudará a detectar lo
antes posible las compilaciones más lentas, la degradación de la caché o la
ralentización de las pruebas, minimizando así el impacto en la productividad de
tu equipo.

Para crear una regla de alerta, ve a la configuración de notificaciones de tu
proyecto y haz clic en **Añadir regla de alerta**:

Puedes configurar:
- **Nombre**: un nombre descriptivo para la alerta
- **Categoría**: Qué medir (duración de la compilación, duración de la prueba o
  tasa de aciertos de la caché)
- **** e de métricas: Cómo agregar los datos (p50, p90, p99 o promedio)
- **Desviación**: El cambio porcentual que activa una alerta
- **Ventana móvil**: ¿Cuántas ejecuciones recientes se deben comparar?
- **Canal de Slack**: Dónde enviar la alerta

Por ejemplo, podrías crear una alerta que se active cuando la duración de la
compilación p90 aumente más de un 20 % en comparación con las 100 compilaciones
anteriores.

Cuando se active una alerta, recibirás un mensaje como este en tu canal de
Slack:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [!NOTA] PERÍODO DE ENFRIAMIENTO
> <!-- -->
> Una vez que se activa una alerta, no se volverá a activar por la misma regla
> durante 24 horas. Esto evita la saturación de notificaciones cuando una
> métrica se mantiene elevada.
> <!-- -->

### Alertas de prueba irregulares {#flaky-test-alerts}

Recibe una notificación al instante cuando una prueba se vuelva inestable. A
diferencia de las reglas de alerta basadas en métricas que comparan ventanas
móviles, las alertas de pruebas inestables se activan en el momento en que Tuist
detecta una nueva prueba inestable, lo que te ayuda a detectar la inestabilidad
de las pruebas antes de que afecte a tu equipo.

Para crear una regla de alerta de pruebas inestables, ve a la configuración de
notificaciones de tu proyecto y haz clic en « **» (Añadir regla de alerta de
pruebas inestables)**:

Puedes configurar:
- **Nombre**: un nombre descriptivo para la alerta
- **Umbral de activación**: El número mínimo de ejecuciones inestables en los
  últimos 30 días necesario para activar una alerta
- **Canal de Slack**: Dónde enviar la alerta

Cuando una prueba se vuelve inestable y alcanza tu umbral, recibirás una
notificación con un enlace directo para investigar el caso de prueba:

<img src="/images/guides/integrations/slack/flaky-test-alert.png" alt="An image that shows a Slack flaky test alert message" style="max-width: 500px;" />

## Instalaciones locales {#on-premise}

Para las instalaciones locales de Tuist, tendrás que crear tu propia aplicación
de Slack y configurar las variables de entorno necesarias.

### Crear una aplicación de Slack {#create-slack-app}

1. Ve a la [página de aplicaciones de la API de
   Slack](https://api.slack.com/apps) y haz clic en « **» (Crear nueva
   aplicación).**
2. Seleccione « **» (Iniciar sesión) en el manifiesto de la aplicación** y elija
   el espacio de trabajo en el que desea instalar la aplicación
3. Pega el siguiente manifiesto, sustituyendo la URL de redireccionamiento por
   la URL de tu servidor Tuist:

```json
{
    "display_information": {
        "name": "Tuist",
        "description": "Get regular updates and alerts for your builds, tests, and caching.",
        "background_color": "#6f2cff"
    },
    "features": {
        "bot_user": {
            "display_name": "Tuist",
            "always_online": false
        }
    },
    "oauth_config": {
        "redirect_urls": [
            "https://your-tuist-server.com/integrations/slack/callback"
        ],
        "scopes": {
            "bot": [
                "chat:write",
                "chat:write.public"
            ]
        }
    },
    "settings": {
        "org_deploy_enabled": false,
        "socket_mode_enabled": false,
        "token_rotation_enabled": false
    }
}
```

4. Revisa y crea la aplicación

### Configurar variables de entorno {#configure-environment}

Configure las siguientes variables de entorno en su servidor Tuist:

- `SLACK_CLIENT_ID` - El ID de cliente de la página de información básica de tu
  aplicación de Slack
- `SLACK_CLIENT_SECRET` - El secreto de cliente de la página de información
  básica de tu aplicación de Slack
