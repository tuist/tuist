---
{
  "title": "GitHub",
  "titleTemplate": ":title | Plataformas Git | Integraciones | Guías | Tuist",
  "description": "Aprende a integrar Tuist con GitHub para mejorar tus flujos de trabajo."
}
---
# Integración con GitHub {#github}

Los repositorios Git son el eje central de la gran mayoría de los proyectos de software. Nos integramos con GitHub para ofrecerte información de Tuist directamente en tus pull requests y ahorrarte configuración, como la sincronización de tu rama predeterminada.

## Configuración {#setup}

Deberás instalar la aplicación de GitHub de Tuist en la pestaña `Integrations` de tu organización: ![Una imagen que muestra la pestaña de integraciones](/images/guides/integrations/gitforge/github/integrations.png)

También puedes instalar la aplicación directamente desde GitHub. Inicia sesión en Tuist si es necesario, autoriza la aplicación de GitHub para que Tuist pueda verificar tu acceso a la instalación y elige la organización de Tuist que deseas conectar. Debes ser propietario de la organización de GitHub (o de la cuenta personal de GitHub) donde se instala la aplicación. Solo están disponibles las organizaciones de Tuist que administras y tu cuenta personal de Tuist. Si solo hay una cuenta disponible, Tuist la conecta automáticamente sin mostrar el selector. Cuando inicias desde Tuist, la organización ya está seleccionada y este paso se omite.

Después, puedes añadir una conexión de proyecto entre tu repositorio de GitHub y tu proyecto de Tuist:

![Una imagen que muestra cómo añadir la conexión del proyecto](/images/guides/integrations/gitforge/github/add-project-connection.png)

Una vez instalada la aplicación, también puedes vincular un proyecto sin usar el panel:

- **CLI:** `tuist project repository connect owner/name`, y `tuist project repository disconnect` para eliminar el vínculo.
- **API REST:** `PUT` y `DELETE` en `/api/projects/{account_handle}/{project_handle}/vcs-connection`.
- **Model Context Protocol:** las herramientas `connect_project_repository` y `disconnect_project_repository`.

El repositorio debe ser accesible para la instalación de la aplicación de GitHub y el proyecto adopta la rama predeterminada del repositorio. Los tokens de cuenta necesitan el ámbito `project:admin:write`.

> [!TIP]
> **Lista blanca de IP**
>
> Si tu organización de GitHub utiliza [listas de direcciones IP permitidas](https://docs.github.com/en/organizations/keeping-your-organization-secure/managing-security-settings-for-your-organization/managing-allowed-ip-addresses-for-your-organization) o tu instancia de GitHub está detrás de un firewall, asegúrate de añadir las <.localized_link href="/guides/server/network#outbound-ip-addresses">direcciones IP salientes</.localized_link> de Tuist a la lista blanca para que la integración pueda comunicarse con tu repositorio.

### GitHub Enterprise Server {#github-enterprise-server}

Tuist también se integra con instancias autoalojadas de GitHub Enterprise Server (GHES). En la tarjeta de integración de GitHub, cambia a la pestaña **Servidor empresarial**, introduce la URL base de tu GHES (por ejemplo, `https://github.example.com`) y haz clic en instalar.

Dado que las aplicaciones de GitHub están limitadas a una única instancia de GitHub, Tuist no puede reutilizar su aplicación de github.com en tu GHES; en su lugar, el botón de instalación te guía a través del [flujo de manifiesto de la aplicación](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-from-a-manifest) de GitHub: GHES acompaña a tu administrador en el registro de una nueva aplicación de Tuist en la instancia y luego devuelve las credenciales de la nueva aplicación a Tuist. Tuist almacena esas credenciales cifradas por instalación y las utiliza para cada llamada a la API, firma de webhook y enlace a tus repositorios a partir de entonces.

No se necesita configuración adicional del servidor de Tuist; el flujo de manifiesto genera y aprovisiona todo automáticamente.

#### Permisos de la aplicación y eventos de webhook {#github-app-permissions}

Tuist requiere los siguientes **permisos de repositorio** para comentarios en PR y comprobaciones del tamaño del bundle:

| Permiso | Acceso | Se usa para |
|---|---|---|
| Metadatos (`metadata`) | Solo lectura | Metadatos básicos del repositorio; requerido por GitHub para cada aplicación |
| Pull requests (`pull_requests`) | Lectura y escritura | Leer pull requests, incluido el SHA del commit head, y listar, publicar y actualizar comentarios en PR |
| Checks (`checks`) | Lectura y escritura | Crear y actualizar ejecuciones de checks, incluidas las comprobaciones de aprobación/rechazo del tamaño del bundle |

Tuist utiliza el evento de webhook `check_run` para gestionar las acciones de comprobación del tamaño del bundle. El flujo de manifiesto configura esta suscripción automáticamente.

Para la configuración manual de la aplicación en github.com con un servidor de Tuist autoalojado, consulta <.localized_link href="/guides/server/self-host/server#platform-github-registering-the-app">la guía de autoalojamiento</.localized_link>.

#### URLs separadas para el navegador y la API {#separate-browser-and-api-urls}

Si los ingenieros acceden a GitHub Enterprise a través de un nombre de host interno mientras los servicios de terceros utilizan un proxy externo, configura ambas direcciones antes de hacer clic en instalar:

| Campo | Ejemplo | Utilizado por |
|---|---|---|
| **URL del servidor** | `https://github.internal.company.com` | Tu navegador, para el registro y la instalación de la aplicación, y los enlaces a GitHub desde Tuist |
| **URL de la API** | `https://github-proxy.company.com/api/v3` | Los servidores de Tuist, para el intercambio del código del manifiesto, tokens de acceso, acceso al repositorio, comentarios en PR y checks |

La URL de la API es la URL base completa de la API REST, incluido `/api/v3` o la ruta equivalente expuesta por tu proxy. Tuist no añade `/api/v3` a una URL de API explícita. Déjala vacía si un único nombre de host funciona tanto para tu navegador como para Tuist; las conexiones existentes seguirán usando `<Server URL>/api/v3`.

Ambas direcciones deben enrutar hacia la **misma instancia de GitHub Enterprise**. Tu navegador solo necesita alcanzar la URL del servidor, no el proxy de la API. Los servidores de Tuist solo necesitan alcanzar la URL de la API, no el nombre de host interno del navegador.

Para el proxy externo:

- Utiliza HTTPS con un certificado de confianza para los servidores de Tuist y DNS público que resuelva a direcciones IP públicas. Las anulaciones de la URL de la API no omiten las protecciones de IP privada/SSRF de Tuist. La anulación debe dirigirse a tu instancia Enterprise, no a `github.com` ni a un extremo `*.github.com`.
- Añade a la lista blanca cada <.localized_link href="/guides/server/network#outbound-ip-addresses">dirección IP saliente</.localized_link> de Tuist.
- Reenvía los extremos de la API REST que utiliza Tuist, incluidos `POST /api/v3/app-manifests/{code}/conversions`, `POST /api/v3/app/installations/{installation_id}/access_tokens` y los extremos de la API del repositorio para comentarios y checks. Estas son las rutas upstream de GitHub; tradúcelas si tu proxy expone un prefijo diferente.
- Reenvía las solicitudes a GitHub sin redirecciones HTTP ni una página de inicio de sesión interactiva. Tuist no sigue automáticamente las redirecciones de la API Enterprise, por lo que no pueden omitir las comprobaciones de IP pública. El extremo de conversión del manifiesto debe ser accesible durante la configuración, antes de que Tuist tenga las credenciales de la aplicación. Las descargas de registros de GitHub Actions son una excepción: Tuist sigue las redirecciones de archivos firmados solo a través de HTTPS, verifica y fija cada destino a una IP pública y no reenvía el token de instalación.

GitHub puede devolver enlaces de paginación utilizando su nombre de host interno. Tuist reajusta los enlaces desde la instancia de GitHub configurada a la URL de la API, conservando el prefijo de ruta de tu proxy; los enlaces a orígenes no relacionados se rechazan.

Por separado, GitHub debe poder entregar webhooks a `https://tuist.dev/webhooks/github` (o `/webhooks/github` en tu servidor de Tuist autoalojado). Los ingenieros deben poder volver a Tuist para completar las devoluciones de llamada del navegador. La URL de la API no cambia ninguno de estos destinos.

Los administradores de la organización también pueden cambiar o borrar la URL de la API en una integración Enterprise existente usando **Guardar URL de la API** en la tarjeta de integración. No es necesario reinstalar la aplicación ni reconectar el proyecto. Borrarla restaura `<Server URL>/api/v3`. Al guardar se valida el formato de la URL, no la conectividad del proxy. El procesamiento de webhooks puede tardar hasta un minuto en utilizar una dirección cambiada porque las búsquedas de instalaciones están almacenadas en caché; las solicitudes ya en curso pueden seguir utilizando la dirección anterior.

> [!NOTE]
> **Solo plan Enterprise en el servidor de Tuist alojado**
>
> En el servidor de Tuist alojado (`https://tuist.dev`), la integración con GitHub Enterprise Server está disponible exclusivamente para organizaciones en el plan **Enterprise**. Las implementaciones de Tuist autoalojadas pueden usarla en cualquier plan.

## Comentarios en pull/merge requests {#pull-merge-request-comments}

La aplicación de GitHub publica un informe de ejecución de Tuist, que incluye un resumen del PR, con enlaces a las últimas <.localized_link href="/guides/features/previews#pullmerge-request-comments">previsualizaciones</.localized_link> o <.localized_link href="/guides/features/selective-testing#pullmerge-request-comments">tests</.localized_link>:

Tuist actualiza un único comentario a medida que llegan los resultados. Las compilaciones de Gradle aparecen por separado para cada proyecto raíz y conjunto de tareas solicitadas; volver a ejecutar las mismas tareas sustituye el resultado anterior de esa invocación. El historial completo de compilaciones sigue estando disponible en Tuist.

Los comentarios están habilitados de forma predeterminada, conservando los informes para las integraciones existentes. Para desactivarlos o volver a activarlos para un proyecto, abre **Configuración del proyecto → Integraciones** y alterna **GitHub → Comentarios del informe de ejecución**. Cada proyecto tiene su propia configuración; las conexiones de repositorio siguen gestionándose en la configuración de la organización.

Desactivar los comentarios no desactiva las subidas de compilaciones o tests, los resúmenes de trabajos de GitHub Actions, las conexiones de repositorio ni otras funcionalidades de integración de GitHub. Los comentarios existentes no se eliminan.

![Una imagen que muestra el comentario en el pull request](/images/guides/integrations/gitforge/github/pull-request-comment.png)

> [!NOTE]
> **Requisitos**
>
> El comentario solo se publica cuando tus ejecuciones de CI están <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticadas</.localized_link>.

> [!NOTE]
> **Github_ref**
>
> Si tienes un flujo de trabajo personalizado que no se activa con un commit de PR, sino, por ejemplo, con un comentario de GitHub, es posible que debas asegurarte de que la variable `GITHUB_REF` esté establecida en `refs/pull/<PR_NUMBER>/merge` o en `refs/pull/<PR_NUMBER>/head`.
>
> Puedes ejecutar el comando correspondiente, como `tuist share`, con la variable de entorno `GITHUB_REF` con prefijo: <code v-pre>GITHUB_REF="refs/pull/${{ github.event.issue.number }}/head" tuist share</code>

## Resumen del trabajo de GitHub Actions {#github-actions-job-summary}

La CLI de Tuist y el plugin de Gradle escriben los resultados de tests y compilaciones en el [resumen del trabajo](https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/) en GitHub Actions. El resumen enlaza al informe completo en Tuist, donde hay disponibles análisis más detallados, como tests inestables y deltas del tamaño del bundle.

Para Gradle, cada informe de compilación o test subido correctamente añade su propio resumen, conservando otro contenido escrito por herramientas como `gradle/actions/setup-gradle`. Esto requiere una versión del plugin que incluya compatibilidad con resúmenes de trabajos; las versiones anteriores del plugin de Gradle solo informan a través del comentario de PR de la aplicación de GitHub. La aplicación de GitHub no necesita estar conectada para los resúmenes de trabajos, y desactivar **Comentarios del informe de ejecución** no les afecta.

Cuando hay disponible un destino de resumen de GitHub Actions, Gradle espera a que finalicen las subidas y los resúmenes antes de salir, incluso si `uploadInBackground` está habilitado. GitHub captura el resumen cuando finaliza el paso del flujo de trabajo.

![Una imagen que muestra el informe de ejecución de Tuist en el resumen del trabajo de GitHub Actions](/images/guides/integrations/gitforge/github/github-actions-job-summary.png)

Esto es especialmente útil con [colas de merge](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue). Una ejecución de cola de merge no está asociada a un pull request, por lo que no se publica ningún comentario, pero el resumen del trabajo sigue mostrando los resultados.

> [!NOTE]
> **Requisitos**
>
> Los resúmenes de trabajos requieren una subida exitosa del informe. En el servidor de Tuist alojado, tus ejecuciones de CI deben estar <.localized_link href="/guides/integrations/continuous-integration#authentication">autenticadas</.localized_link>. Las instancias autoalojadas también pueden aceptar informes sin credenciales cuando está habilitada la publicación de informes de confianza de red.
