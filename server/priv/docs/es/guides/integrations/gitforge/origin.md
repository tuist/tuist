---
{
  "title": "Origin",
  "titleTemplate": ":title | Forjas de Git | Integraciones | Guías | Tuist",
  "description": "Conecta repositorios nativos de Cursor Origin a los informes de pull request de Tuist."
}
---
# Integración con Origin {#origin}

Tuist puede publicar informes de compilación, tests, previsualizaciones y bundles en pull requests de repositorios nativos de [Cursor Origin](https://cursor.com/docs/api/origin). Actualiza el informe de ejecución de Tuist existente de la app en lugar de publicar un nuevo comentario por cada subida.

Instalar la app no ejecuta compilaciones ni tests. Tus flujos de trabajo existentes siguen subiendo resultados a Tuist, y la integración lleva esos resultados a tus pull requests.

## Configuración {#setup}

Un administrador de la cuenta de Tuist debe abrir **Settings → Integrations**, elegir **Install Origin App** en la tarjeta de Origin y aprobar el acceso en Cursor. Elige la cuenta o namespace de Origin y los repositorios a los que Tuist debe acceder, luego vuelve a Tuist. La conexión pertenece a la cuenta de Tuist, no a un proyecto individual.

También puedes instalar la app directamente desde Origin. Tras aprobar el acceso, inicia sesión en Tuist si es necesario y elige la organización a conectar. Solo están disponibles las organizaciones que administras y tu cuenta personal. Si solo hay una cuenta disponible, Tuist la conecta automáticamente sin mostrar el selector. Si empiezas desde Tuist, la organización ya está seleccionada y este paso se omite.

Elige **Add new project connection** para abrir el modal de selección de repositorio. Selecciona un proyecto de Tuist sin conectar y uno de los repositorios descubiertos desde la cuenta de Origin conectada, luego elige **Create Connection**. Si hay varias cuentas de Origin conectadas, elige primero la cuenta. Solo los repositorios nativos de Origin están disponibles para conexión. Tuist verifica de nuevo el acceso a pull requests antes de conectar el proyecto y adopta la rama predeterminada del repositorio.

Usa **Manage integration** para abrir el flujo de consentimiento de Cursor en una nueva pestaña y ajustar el acceso al repositorio o conectar otra cuenta de Origin. Los fallos de carga de repositorios muestran **Retry**, separados de una lista vacía de repositorios exitosa.

Usa un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> para autenticar las subidas de resultados.

## Informes y permisos {#reports-and-permissions}

Al aprobar la app, otorgas los permisos necesarios para conectar repositorios y publicar informes:

| Permiso | Utilizado para |
| --- | --- |
| Pull requests: lectura | Encontrar la pull request abierta para el commit informado. |
| Revisiones de pull requests: lectura y escritura | Leer, publicar y actualizar el comentario del informe de ejecución de Tuist. |
| Metadatos del repositorio: lectura | Descubrir repositorios y sus ramas predeterminadas. Incluido automáticamente por Origin. |

Tuist no necesita acceso a tu código fuente ni permiso para fusionar pull requests.

Para asociar resultados con una pull request, las subidas deben incluir la URL de clonación de Origin del repositorio, la referencia Git y el SHA completo del commit. Tuist publica el informe solo cuando esos datos identifican una única pull request abierta en su commit head actual. Los resultados de commits reemplazados no sobrescriben el informe actual.

La tarjeta de Origin enumera las conexiones entre proyectos y repositorios. Elige **Manage → Remove connection** en una conexión de proyecto para detener sus informes sin desinstalar la app. Desinstala la app en Cursor para revocar su acceso; Tuist elimina la instalación y sus conexiones de proyecto cuando procesa la notificación de instalación.

## Servidores autoalojados {#server-configuration}

Si alojas tu propio servidor de Tuist, registra y configura primero una app de Origin para tu despliegue. Sigue las <.localized_link href="/guides/server/self-host/server#platform-origin">instrucciones de autoalojamiento de Origin</.localized_link>, luego vuelve a los pasos de configuración anteriores para conectar cuentas y proyectos.
