---
{
  "title": "Slack",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with Slack."
}
---
# Integración con Slack {#slack}

Si tu organización utiliza Slack, puedes integrar Tuist para obtener información
directamente en tus canales. De este modo, la supervisión deja de ser algo que
el equipo tiene que acordarse de hacer y se convierte en algo que simplemente
ocurre. Por ejemplo, tu equipo puede recibir resúmenes diarios del rendimiento
de la compilación, las tasas de aciertos de la caché o las tendencias de tamaño
de los paquetes.

## Configurar {#setup}

### Conecta tu espacio de trabajo Slack {#connect-workspace}

En primer lugar, conecta tu espacio de trabajo de Slack a tu cuenta de Tuist en
la pestaña `Integrations`:

Una imagen que muestra la pestaña de integraciones con conexión a
Slack](/images/guides/integrations/slack/integrations.png)

Haz clic en **Connect Slack** para autorizar a Tuist a publicar mensajes en tu
espacio de trabajo. Esto te redirigirá a la página de autorización de Slack
donde podrás aprobar la conexión.

> [NOTA] APROBACIÓN DEL ADMINISTRADOR DE SLACK Si su espacio de trabajo de Slack
> restringe la instalación de aplicaciones, es posible que tenga que solicitar
> la aprobación de un administrador de Slack. Slack le guiará a través del
> proceso de solicitud de aprobación durante la autorización.

### Informes de proyectos {#project-reports}

Después de conectar Slack, configure los informes para cada proyecto en la
pestaña de notificaciones de la configuración del proyecto:

![Una imagen que muestra la configuración de notificaciones con la configuración
de informes de
Slack](/images/guides/integrations/slack/notifications-settings.png)

Se puede configurar:
- **Canal**: Seleccione qué canal de Slack recibe los informes
- **Programar**: Elija qué días de la semana desea recibir los informes
- **Hora**: Ajuste la hora del día

Una vez configurado, Tuist envía informes diarios automatizados a tu canal Slack
seleccionado:

<img src="/images/guides/integrations/slack/report.png" alt="An image that shows a Slack report message" style="max-width: 500px;" />

### Normas de alerta {#alert-rules}

Reciba notificaciones en Slack con reglas de alerta cuando las métricas clave
retrocedan significativamente para ayudarle a detectar compilaciones más lentas,
degradación de la caché o ralentizaciones de las pruebas lo antes posible,
minimizando el impacto en la productividad de su equipo.

Para crear una regla de alerta, vaya a la configuración de notificaciones de su
proyecto y haga clic en **Añadir regla de alerta**:

Se puede configurar:
- **Nombre**: Nombre descriptivo de la alerta
- **Categoría**: Qué medir (duración de la compilación, duración de la prueba o
  tasa de aciertos de la caché)
- **Métrica**: Cómo agregar los datos (p50, p90, p99 o media)
- **Desviación**: El cambio porcentual que activa una alerta
- **Ventana móvil**: Con cuántas ejecuciones recientes comparar
- **Canal Slack**: Dónde enviar la alerta

Por ejemplo, puede crear una alerta que se active cuando la duración de la
compilación p90 aumente en más de un 20% en comparación con las 100
compilaciones anteriores.

Cuando se active una alerta, recibirás un mensaje como este en tu canal de
Slack:

<img src="/images/guides/integrations/slack/alert.png" alt="An image that shows a Slack alert message" style="max-width: 500px;" />

> [Después de que se active una alerta, no volverá a activarse para la misma
> regla durante 24 horas. Esto evita la fatiga de notificaciones cuando una
> métrica se mantiene elevada.

## Instalaciones in situ {#on-premise}

Para las instalaciones Tuist locales, tendrás que crear tu propia aplicación
Slack y configurar las variables de entorno necesarias.

### Crear una aplicación Slack {#create-slack-app}

1. Vaya a la página [Slack API Apps page](https://api.slack.com/apps) y haga
   clic en **Create New App**
2. Elija **Desde el manifiesto de una aplicación** y seleccione el espacio de
   trabajo en el que desea instalar la aplicación.
3. Pega el siguiente manifiesto, sustituyendo la URL de redirección por la URL
   de tu servidor Tuist:

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

4. Revisar y crear la aplicación

### Configurar variables de entorno {#configure-environment}

Establece las siguientes variables de entorno en tu servidor Tuist:

- `SLACK_CLIENT_ID` - El ID de cliente de la página de información básica de su
  aplicación Slack.
- `SLACK_CLIENT_SECRET` - El secreto del cliente de la página de información
  básica de su aplicación Slack.
