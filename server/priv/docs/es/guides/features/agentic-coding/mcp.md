---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Programación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Proporciona a los agentes de IA acceso a análisis de tests y más a través del endpoint MCP de Tuist."
}
---
# Protocolo de contexto de modelo

El [Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) es un estándar abierto que permite a los agentes de inteligencia artificial interactuar con servicios externos y fuentes de datos. Hace que aplicaciones como [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) y editores como [Zed](https://zed.dev), [Cursor](https://www.cursor.com) o [Visual Studio Code](https://code.visualstudio.com) sean interoperables con Tuist.

Tuist aloja un punto final del Model Context Protocol en el servidor en `https://tuist.dev/mcp`. Al conectar tu cliente a él, los agentes pueden acceder a los datos de tus proyectos de Tuist, incluidos análisis de tests, análisis de tests inestables y más. La mayoría de las herramientas son de solo lectura y están limitadas a los datos autenticados del proyecto de Tuist. Las herramientas de configuración de cuentas pueden listar cuentas, crear organizaciones, crear proyectos y añadir usuarios existentes a las organizaciones cuando el usuario autenticado tiene los permisos necesarios. Cada herramienta muestra anotaciones que indican si es de solo lectura, si puede provocar un cambio difícil de revertir y si puede cambiar el estado público de Internet. Las herramientas de configuración de cuentas requieren autenticación de usuario. No están disponibles para tokens de proyecto ni para tokens de cuenta ordinarios. Cuando un usuario autoriza un cliente en el navegador o reclama un registro `auth.md`, Tuist asocia esa credencial con el usuario únicamente en el punto final del Model Context Protocol, para que las herramientas de configuración puedan completar el flujo solicitado.

Tuist implementa el [protocolo 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http). Las solicitudes no tienen estado: los clientes envían sus metadatos de protocolo con cada solicitud y pueden llamar a las herramientas directamente sin inicialización. `server/discover` devuelve la identidad del servidor, las capacidades, las versiones compatibles y las instrucciones. No hay identificadores de sesión ni flujos de eventos independientes. Los clientes que usan el flujo de inicialización 2025-06-18 o 2025-03-26 siguen siendo compatibles; también operan sin sesiones de servidor.

## Model Context Protocol frente a skills

Las herramientas del Model Context Protocol y las <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> pueden solaparse en lo que hacen. Dada la superposición actual entre ambas, elige un enfoque por flujo de trabajo y úsalo de forma consistente en lugar de mezclar ambos en el mismo flujo.

Para clientes que admiten la instalación de plugins, usa los <.localized_link href="/guides/features/agentic-coding/plugins">plugins de Tuist</.localized_link> para instalar ambos juntos.

## Configuración

Añade `https://tuist.dev/mcp` como un servidor remoto del Model Context Protocol en tu cliente. Las instrucciones de inicialización del servidor y su tarjeta pública describen OAuth 2.0 con registro dinámico de cliente y el flujo estándar de autorización en el navegador de forma integrada, sin pedir a los agentes que obtengan o sigan documentos de autenticación externos. Estas instrucciones generales del servidor mantienen la guía del flujo de trabajo genérica: la autenticación de herramientas no autentica herramientas locales de línea de comandos ni integraciones del sistema de compilación, y los agentes deben verificar los cambios solicitados a través de las herramientas relevantes de Tuist. La configuración específica del sistema de compilación y las comprobaciones de autenticación se documentan en las guías de integración y en los prompts. Tuist sigue anunciando tanto los metadatos de descubrimiento de [Open Authorization](https://oauth.net/2/) como el actual [protocolo auth.md](https://workos.com/auth-md) en `https://tuist.dev/auth.md` por separado.

El punto final acepta el ciclo de vida de solicitudes sin estado del `2026-07-28` Model Context Protocol, incluido `server/discover`, junto con el ciclo de vida basado en sesiones anterior. Los clientes existentes pueden seguir usando su método de conexión actual.

Los clientes que admiten eventos del Model Context Protocol pueden suscribirse a eventos del proyecto. Consulta [Eventos](#events) para ver los requisitos de eventos y entrega disponibles.

Los clientes que ya admiten la autenticación remota en el navegador pueden seguir autenticándose en el navegador. Los clientes y agentes que admiten `auth.md` pueden registrarse de forma anónima, presentar una aserción de identidad de proveedor de confianza o iniciar una reclamación de correo electrónico autenticada por servicio. El registro devuelve una aserción de identidad firmada por Tuist, que el agente intercambia en el punto final de token estándar por un token de acceso de una hora. Tuist publica su clave pública de firma y admite la revocación estándar de tokens y la entrega de eventos de seguridad del proveedor.

Un agente no autenticado debe leer la cabecera `WWW-Authenticate` devuelta por el punto final del Model Context Protocol, obtener los metadatos del recurso protegido, obtener los metadatos del servidor de autorización y seguir su URL `agent_auth.skill`. Tuist también devuelve la misma URL local `auth_md` en el cuerpo de la respuesta no autorizada para que los clientes impulsados por modelos de lenguaje puedan descubrir el flujo sin depender de una integración nativa del cliente. El documento local del despliegue es la fuente de verdad para los nombres de los puntos finales, los cuerpos de las solicitudes, el sondeo de reclamaciones y el intercambio de aserciones.

Antes de que un agente inicie una reclamación de correo electrónico, debe pedir al usuario que confirme la dirección de correo electrónico de su cuenta de Tuist. No debe inferir esa dirección a partir de un perfil de proveedor, la configuración de Git, una variable de entorno o los metadatos de la sesión.

El punto final utiliza el grupo de ámbitos `mcp`. Una credencial anónima previa a la reclamación puede descubrir capacidades y leer la guía pública de integración, pero no se trata como un usuario conectado. Tras la autorización en el navegador o la reclamación, la credencial tiene ámbito de usuario y cada herramienta aplica las mismas comprobaciones de autorización que el panel. Consulta la <.localized_link href="/guides/server/authentication#scope-groups">documentación de grupos de ámbitos</.localized_link> para más detalles.

Las herramientas se resuelven a los proyectos que el usuario autenticado ya puede leer. Las herramientas de compilación de Xcode y Gradle aceptan un UUID de compilación o una URL del panel. El UUID debe identificar exactamente un proyecto; si aparece en varios proyectos, la herramienta devuelve "no encontrado" en lugar de seleccionar el informe de otro proyecto. Las lecturas del panel y de la API con ámbito de proyecto siguen estando disponibles. Los identificadores de actor informados son etiquetas no verificadas, no credenciales ni derechos de acceso adicionales.

Las herramientas de lista y detalle de compilaciones exponen metadatos opcionales `tuist_version`: la CLI de Tuist informante para Xcode y Cargo, el plugin de Tuist Gradle para Gradle y la biblioteca `tuist_ex` para Mix. Xcode también expone `tuist_generation_version` a partir de su evento de generación de proyecto vinculado, que puede diferir de la CLI que realiza la carga. Las observaciones faltantes son nulas, no se infieren del servidor ni de otro informe. Bazel utiliza su `bazel_version` existente; los detalles de ejecución de Once exponen `once_version`. Estos campos describen versiones informadas, no identidades verificadas ni versiones de contrato de red. Los puntos finales REST de compilación exponen los mismos metadatos. Las habilidades de integración existentes y de tests inestables no dependen de los campos de versión y no requieren cambios en el flujo de trabajo.

Los operadores de Tuist que investigan la cuenta de un cliente lo hacen a través de las herramientas internas de operaciones de Tuist, que registran cada llamada; una conexión directa a este punto final no obtiene acceso más allá de las propias membresías del usuario.

<details>
<summary>Claude Code</summary>

Ejecuta:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Cuando un cliente de Claude Code sin interfaz gráfica no expone al modelo una conexión fallida con el servidor nativo, exige al agente que inspeccione la respuesta no autenticada del [Protocolo de Transferencia de Hipertexto](https://developer.mozilla.org/en-US/docs/Web/HTTP) del punto final configurado antes de buscar documentación alojada o editar el proyecto. La respuesta indica al modelo el documento `auth.md` local del despliegue incluso cuando la autenticación mediante navegador no está disponible.

</details>


<details>
<summary>Codex</summary>

Ejecuta:

```bash
codex mcp add tuist --url https://tuist.dev/mcp
codex mcp login tuist
```

Completa el inicio de sesión en el navegador antes de iniciar una nueva ejecución de `codex exec`. Codex lee las instrucciones del servidor de Tuist durante la inicialización, por lo que las solicitudes de optimización de Gradle reciben automáticamente el flujo de autenticación y verificación.

</details>


<details>
<summary>Claude Desktop</summary>

Abre **Settings → Connectors → Add custom connector** y configura:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

Completa la [Autorización abierta](https://oauth.net/2/) en el navegador cuando se te solicite.

</details>


<details>
<summary>Pi</summary>

Pi no incluye un cliente de Model Context Protocol. Puedes instalar la extensión de terceros [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) después de revisar su código fuente e implicaciones de seguridad:

```bash
pi install npm:pi-mcp-adapter
```

Añade un archivo `.mcp.json` a nivel de proyecto:

```json
{
  "mcpServers": {
    "tuist": {
      "url": "https://tuist.dev/mcp",
      "auth": false
    }
  }
}
```

Establecer `auth` como `false` evita que el manejador de autenticación del navegador del adaptador oculte la respuesta no autorizada de Tuist. Un agente sin interfaz gráfica puede entonces leer la URL `auth_md` devuelta y seguir el flujo de registro, intercambio de aserciones de identidad y sondeo de reclamaciones de Tuist. Configura el token de acceso intercambiado como un token bearer o permite que el agente realice llamadas autenticadas de Model Context Protocol directamente.

Si prefieres la autenticación mediante navegador, establece `auth` como `"oauth"`. Para ese flujo, mantén un proceso activo con el [modo de llamada a procedimiento remoto](https://pi.dev/docs/latest/rpc) de Pi mientras se completa la autenticación:

```bash
pi --mode rpc
```

No dividas una autenticación pendiente en el navegador entre invocaciones separadas de `pi --print` porque el proceso que posee el estado de la devolución de llamada ha terminado.

</details>


<details>
<summary>OpenCode</summary>

Añade el servidor de Model Context Protocol de Tuist a `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "tuist": {
      "type": "remote",
      "url": "https://tuist.dev/mcp"
    }
  }
}
```

Luego autentica el servidor:

```bash
opencode mcp auth tuist
```

</details>


<details>
<summary>Cursor</summary>

Abre **Cursor Settings → Tools & Integrations → Model Context Protocol Tools** y añade:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Visual Studio Code</summary>

Usa **Command Palette → MCP: Add Server** y configura un servidor de [Protocolo de Transferencia de Hipertexto](https://developer.mozilla.org/en-US/docs/Web/HTTP) con:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

Abre **Agent panel → Settings → Add Custom Server** y configura:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Si tu agente admite `auth.md`, puede comenzar de forma anónima sin abrir un navegador. Una identidad de proveedor de confianza también puede completarse sin navegador cuando la identidad del proveedor ya está vinculada. Para correo electrónico autenticado por servicio, reclamación anónima o un primer vínculo de proveedor, el agente te muestra un enlace de verificación de Tuist y un código de seis dígitos. Abre el enlace, inicia sesión e introduce el código del agente en la página de Tuist. Nunca envíes el código de vuelta al agente. Los metadatos del servidor de autorización de Tuist apuntan directamente al `/auth.md` propio del despliegue, que contiene las estructuras exactas de solicitud y sondeo.

## Las integraciones con sistemas de compilación utilizan dos credenciales

La credencial utilizada para las herramientas de Model Context Protocol no autentica el plugin de Gradle ni los servicios remotos de Bazel. Antes de que un agente edite o verifique una integración de Gradle o Bazel, debe ejecutar:

```bash
tuist auth whoami --url https://tuist.dev
```

Si ese comando no está autenticado, el agente debe detenerse y pedir al usuario que ejecute:

```bash
tuist auth login --url https://tuist.dev
```

Para un despliegue local o autoalojado, reemplaza la URL en ambos comandos y en `tuist.toml`. Mantén la escritura del nombre de host idéntica en todas partes. Por ejemplo, `localhost` y `127.0.0.1` utilizan credenciales almacenadas separadas.


## Capacidades

### Herramientas

Las siguientes herramientas están disponibles a través del servidor de Model Context Protocol de Tuist:

Cada herramienta publica una descripción legible junto con esquemas explícitos de entrada y salida. Las llamadas exitosas devuelven contenido estructurado que se ajusta al esquema de salida anunciado, además del mismo resultado serializado como texto para clientes que aún no consumen contenido estructurado.

Las herramientas que toman el identificador de un único registro, como `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` o `cache_run_id`, también aceptan la URL del panel de Tuist de ese registro. Pega la URL directamente desde el navegador en lugar de extraer el identificador de ella.

#### Búsqueda en documentación y comunidad

Esta herramienta de solo lectura busca en la documentación de Tuist, la referencia de la [interfaz de programación de aplicaciones](https://en.wikipedia.org/wiki/API), las versiones de GitHub, el foro de la comunidad y los issues de GitHub a través del mismo motor de búsqueda que impulsa el sitio web de documentación. Los resultados de las versiones incluyen el producto, la versión, la fecha de publicación y el estado de prerelease. Las versiones estables se buscan por defecto y las prereleases se pueden incluir con `include_prereleases`. La herramienta solo está disponible en el servidor alojado por Tuist en `https://tuist.dev/mcp`.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `search_tuist` | Busca en la documentación pública de Tuist, la referencia de la interfaz de programación de aplicaciones, las versiones de GitHub, las discusiones de la comunidad y los issues de GitHub. Opcionalmente, restringe a una `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Respuestas respaldadas por el código fuente

Estas herramientas de solo lectura permiten a los agentes usar la revisión exacta del código fuente público de Tuist desplegada junto con el servidor alojado como fuente de verdad para respuestas que dependen del comportamiento actual. Solo están disponibles en `https://tuist.dev/mcp`.

Los clientes compatibles reciben descripciones fácticas de la revisión del código fuente de las herramientas, enlaces y límites de resultados durante la inicialización, junto con información de autenticación OAuth en línea. Estas descripciones no prescriben el estilo de respuesta ni un flujo de trabajo de verificación. Los usuarios pueden hacer una pregunta directamente sin invocar primero el prompt `ask_tuist`; el prompt sigue estando disponible para un flujo de trabajo explícito respaldado por el código fuente.

Cada operación tiene límites fijos de concurrencia, duración, recorrido, bytes leídos y tamaño de respuesta. Los resultados de búsqueda y listado incluyen los campos `truncated` y `truncation_reason`. Cuando un resultado está truncado, reduce la ruta, el patrón de archivo o el término de búsqueda en lugar de tratar el resultado como exhaustivo.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `search_tuist_code` | Responde preguntas sobre el comportamiento actual, valores por defecto, configuración, feature gates, manejo de errores o detalles no documentados buscando en los archivos de código fuente. Los resultados incluyen líneas circundantes, enlaces al código fuente fijados a la revisión y estadísticas de escaneo. | `pattern` |
| `list_tuist_files` | Descubre un subsistema de código fuente o tests cercanos cuando la ruta relevante es desconocida. Los listados tienen profundidad y conteos de resultados acotados. | Ninguno |
| `read_tuist_file` | Inspecciona un rango de líneas enfocado en un archivo de implementación, sitio de llamada o test después de encontrar la ruta relevante. Las respuestas truncadas proporcionan `next_start_line` para continuar. | `path` |

#### Proyectos

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_accounts` | Lista los handles de cuentas personales y de organización disponibles para el usuario autenticado, incluyendo si cada cuenta puede crear proyectos. | Ninguno |
| `get_organization` | Obtiene el directorio de miembros de una organización. Las invitaciones pendientes requieren el mismo permiso de administrador que el panel; los tokens de aceptación de invitación nunca se devuelven. | `account_handle` |
| `create_organization` | Crea una organización de Tuist para el usuario autenticado. | `handle` |
| `create_project` | Crea un proyecto de Tuist bajo una cuenta a la que el usuario autenticado pueda acceder. | `account_handle`, `project_handle` |
| `add_organization_member` | Añade un usuario existente de Tuist a una organización o actualiza el rol de un miembro existente. Acepta `user` (por defecto), `admin` o `viewer`, donde un viewer puede leer paneles y ejecuciones pero no puede cambiar nada. | `organization_handle`, `email` |
| `invite_organization_member` | Invita una dirección de correo electrónico a una organización, pertenezca o no a un usuario existente de Tuist. Tuist envía por correo un enlace de aceptación que caduca después de 14 días; cuando el servidor no puede enviar correo, `email_sent` es `false` y el enlace debe copiarse desde el panel. Acepta `user` (por defecto), `admin` o `viewer`. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Cancela una invitación pendiente a una organización para que su enlace ya no pueda ser aceptado. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `list_projects` | Lista todos los proyectos accesibles para el usuario autenticado. | Ninguno |
| `get_project` | Obtiene la configuración de un proyecto y la URL del repositorio conectado. | `account_handle`, `project_handle` |
| `connect_project_repository` | Vincula un proyecto a un repositorio de GitHub al que la instalación de la GitHub App de la cuenta pueda acceder. El proyecto adopta la rama por defecto del repositorio. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Elimina el vínculo de un proyecto con su repositorio de GitHub. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle` |

#### Tokens de cuenta

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_account_tokens` | Lista los metadatos de los tokens de cuenta sin exponer sus valores. | `account_handle` |
| `get_account_token` | Obtiene los metadatos de un token de cuenta sin exponer su valor. | `account_handle`, `token_id` |
| `list_project_tokens` | Lista los metadatos de los tokens de proyecto sin exponer sus valores. | `account_handle`, `project_handle` |

#### Runners de integración continua

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_runner_jobs` | Lista las tareas de los runners de integración continua para una cuenta. | `account_handle` |
| `get_runner_job` | Obtiene una tarea de un runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Lista los pasos registrados para una tarea de un runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Lista las métricas de máquina registradas para una tarea de un runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Lista hasta 500 líneas de registro capturadas para una tarea de un runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Lista los resúmenes de flujos de trabajo de integración continua para una cuenta. | `account_handle` |
| `list_runner_profiles` | Lista los perfiles de runners de integración continua para una cuenta, con la etiqueta `runs-on` de cada uno. | `account_handle` |
| `get_runner_catalog` | Lista las configuraciones de máquina y versiones de Xcode que puede usar un perfil de runner. | `account_handle` |
| `create_runner_profile` | Crea un perfil de runner con una plataforma, una configuración de máquina y, en macOS, una versión de Xcode. Opcionalmente, establece qué ramas guardan sus volúmenes de caché. Requiere administración de la cuenta o el ámbito `account:runners:write`. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Cambia la configuración de máquina, la versión de Xcode o qué ramas guardan los cambios de su volumen de caché personalizado de un perfil de runner. Los campos omitidos conservan su valor. Requiere administración de la cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Elimina un perfil de runner tras la confirmación del usuario. Los perfiles por defecto no se pueden eliminar. Requiere administración de la cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |

Las herramientas de volúmenes de runners exponen los mismos datos que el panel de Volúmenes. Las herramientas de lectura requieren acceso al runner; el borrado requiere administración de la cuenta o el ámbito `account:runners:write`, y la confirmación del usuario.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_runner_volumes` | Filtra por nombre y repositorio, ordena y paginación los volúmenes. | `account_handle` |
| `get_runner_volume` | Repositorio, plataforma, capacidad, espacio usado y último uso. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Referencias paginadas de tareas y flujos de trabajo, estado de la caché, resultado de acierto y tiempo de montaje. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Volúmenes montados por una tarea. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Series de almacenamiento, ejecuciones de tareas, tasa de aciertos y tendencias. Opcional `volume_id`, `start` y `end` (ISO 8601); por defecto siete días, máximo 90. | `account_handle` |
| `clear_runner_volume` | Borra el contenido guardado. Las tareas en ejecución mantienen sus copias privadas pero no pueden guardarlas; las tareas posteriores comienzan vacías. | `account_handle`, `volume_id` |

Las listas aceptan `page` y `page_size` (hasta 100). El inventario de volúmenes también acepta `name` y `repository` (coincidencias exactas, combinadas con AND), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) y `sort_order` (`asc`, `desc`). Las mediciones desconocidas y los resultados de acierto permanecen como `null`. El estado de la caché describe si se guardaron los cambios del volumen, no el éxito de la tarea.

#### Webhooks

Las herramientas de webhook usan el mismo permiso exclusivo para administradores que el panel. Los intentos de entrega contienen los datos de solicitud y respuesta registrados para el endpoint, pero nunca el secreto de firma del endpoint.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Lista los endpoints de webhook para una cuenta. | `account_handle` |
| `get_webhook_endpoint` | Obtiene un endpoint de webhook. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Lista los intentos de entrega para un endpoint. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Obtiene un intento de entrega. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Compilaciones de Xcode

Las herramientas de detalle de compilación para Xcode, Gradle, Bazel, Mix y Cargo exponen la estructura existente `custom_metadata: {tags, values}`, incluidas las observaciones de infraestructura cuando se informan. Los valores permanecen como cadenas y se conservan las claves desconocidas. Por ejemplo, `tuist.cpu.available_processors` describe los procesadores lógicos disponibles en tiempo de ejecución, mientras que `tuist.gradle.max_workers` es un límite de workers de Gradle y `tuist.jvm.max_heap_bytes` es un límite de heap de la JVM, no de la memoria del host. Estas son observaciones de cliente no confiables, no identidades de runner verificadas. Las observaciones ausentes permanecen ausentes; los registros importados y los clientes antiguos pueden no tener metadatos de infraestructura. Los metadatos de Once esperan una actualización coordinada del cliente/protocolo.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_xcode_builds` | Lista las ejecuciones de compilación de Xcode para un proyecto. | `account_handle`, `project_handle` |
| `get_xcode_build` | Obtiene información detallada sobre una ejecución de compilación de Xcode específica, incluida una URL de descarga temporal para el archivo que contiene el `.xcactivitylog` sin procesar. | `build_run_id` |
| `list_xcode_build_targets` | Lista los targets de compilación para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_files` | Lista los archivos compilados para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_steps` | Lista los pasos de compilación registrados con tiempos y resultados, sin texto de registro. | `build_run_id` |
| `get_xcode_build_step` | Obtiene un paso de compilación registrado, incluido su registro y la bandera de truncamiento. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Lista los problemas de compilación (advertencias y errores) para una ejecución de compilación específica. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Lista las tareas cacheables (aciertos/fallos de caché) para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Lista las salidas de [almacenamiento direccionable por contenido](https://en.wikipedia.org/wiki/Content-addressable_storage) para una ejecución de compilación de Xcode específica. | `build_run_id` |

`list_xcode_build_steps` devuelve páginas de 20 pasos por defecto (máximo 100 mediante `page_size`), con `page` y `pagination_metadata` para la navegación. Usa `search` para coincidir con títulos, proyectos o targets, o filtra por `project`, `target`, `category` exactos (por ejemplo, `swiftCompilation`) y `status` (`success` o `failure`). Ordena por `duration_ms` para mostrar primero los más lentos (el valor por defecto) o por `start_ms` para orden cronológico. Los IDs de paso desempatan y se devuelven como cadenas decimales para preservar su precisión completa de 64 bits. Los IDs están scoped a una compilación y no deben coincidir entre compilaciones.

Los parámetros opcionales `start_ms` y `end_ms` seleccionan pasos que se superponen con un rango de tiempo en milisegundos desde el inicio de la compilación; el final es exclusivo. Ambas herramientas aceptan un UUID de compilación o una URL del panel como `build_run_id`. Pasa el `id` de paso devuelto sin cambios como `step_id` para recuperar su registro. Los registros retienen hasta 64 KiB por paso, con `log_truncated` indicando la salida omitida.

Los pasos se recopilan por defecto cuando se procesan las compilaciones de Xcode. Los datos de pasos registrados se conservan durante 90 días. La respuesta de la lista incluye `availability`: `available` cuando existen pasos registrados, incluso si los filtros no coinciden con ninguno; `processing` cuando la compilación aún se está procesando y no tiene pasos todavía; o `unavailable` cuando los pasos no se registraron o han caducado.

Las mismas operaciones están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` y `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`, con los mismos filtros y paginación. Ambas requieren acceso de lectura al proyecto de la compilación.

#### Compilaciones de Gradle

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Devuelve la autenticación completa, la configuración del proyecto, el plugin de Gradle, la política de caché y el flujo de verificación de dos compilaciones. Los agentes deben llamarla antes de editar un proyecto Android o Gradle existente. | Ninguno |
| `list_gradle_builds` | Lista las ejecuciones de compilación de Gradle para un proyecto, incluidos metadatos personalizados. Filtra por una etiqueta personalizada con el parámetro opcional `tag`. | `account_handle`, `project_handle` |
| `get_gradle_build` | Obtiene los metadatos de compilación y los recuentos de tareas/caché. | `build_run_id` |
| `list_gradle_build_tasks` | Lista los resultados de las tareas, la identidad de compilación compuesta, la capacidad de caché y el estado incremental. | `build_run_id` |
| `list_gradle_build_steps` | Lista las tareas cronometradas, la configuración y las transformaciones, con búsqueda, metadatos y filtros de tiempo superpuestos. | `build_run_id` |
| `get_gradle_build_step` | Inspecciona los metadatos de paso registrados por ID opaco; los registros por paso no están disponibles. | `build_run_id`, `step_id` |

Las listas de pasos de Gradle y Bazel tienen por defecto 20 resultados (máximo 100), admiten `search`, `project`, `target`, `category` y `status` exactos, filtros superpuestos `start_ms` / `end_ms` (final exclusivo) y ordenación por `duration_ms` o `start_ms`. Pasa los IDs devueltos sin cambios; están scoped a su compilación. Las listas exponen `time_origin` y `coverage`. Los informes antiguos de Gradle usan `first_recorded_timestamp` porque no se subió ningún inicio de compilación. Los perfiles de Bazel exponen todos los intervalos registrados con cobertura `trace_profile` y `profile_start` como origen de tiempo. Las compilaciones antiguas recurren a resúmenes BEP retenidos. Los registros fuente caducan después de 90 días. Los detalles de Bazel incluyen registros de acciones sanitizados cuando se publican; el detalle de Gradle `log` es nulo. El prompt `compare_builds` usa esta cobertura para distinguir trazas completas de Bazel de resúmenes retenidos y dirige a los agentes a los detalles de los pasos para conocer los resultados de las acciones y los registros antes de comprobar la salida de invocación más amplia.

Los IDs de paso de Bazel devueltos desde resúmenes retenidos permanecen legibles si llega un perfil completo entre el listado y la obtención de un paso. Un perfil indexado cuyos datos de paso han caducado informa como no disponible. Las listas de pasos de Gradle incluyen operaciones en caché y omitidas de duración cero.

#### Invocaciones de Bazel

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Devuelve la autenticación, la configuración del proyecto, la configuración de Bazel y el flujo de verificación. | Ninguno |
| `list_bazel_invocations` | Lista las invocaciones completadas del [Protocolo de Eventos de Compilación de Bazel](https://bazel.build/remote/bep) con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales de caché remota correlacionados para un proyecto. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Obtiene una invocación de Bazel completada con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales de caché remota correlacionados. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Lista los intervalos de perfil de Bazel registrados, con filtros y cobertura explícita. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Inspecciona un paso de Bazel registrado y su resultado de acción publicado y registro sanitizado. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Lista los registros de prueba sanitizados capturados para una invocación de Bazel en orden de ejecución. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Obtiene un registro de prueba sanitizado capturado para una invocación de Bazel. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | Lista las observaciones brutas de la caché remota de Bazel con su operación, endpoint y hora de observación, opcionalmente filtradas por invocación, resultado u operación. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Obtiene una observación bruta de la caché remota de Bazel. | `account_handle`, `project_handle`, `cache_event_id` |

#### Compilaciones de Cargo

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_cargo_builds` | Lista las compilaciones de Cargo de un proyecto, empezando por las más recientes. Filtra por `git_branch`, `status`, `is_ci` o `command`. Los resultados de ejecución de pruebas de Cargo están disponibles a través de las herramientas de prueba, no en este listado de compilaciones. | `account_handle`, `project_handle` |
| `get_cargo_build` | Obtiene los metadatos de la compilación y los contadores agregados de caché, incluidos aciertos, fallos de tarea y tasa de aciertos. | `account_handle`, `project_handle`, `build_id` |

#### Compilaciones de Mix

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_mix_builds` | Lista las compilaciones de Mix (Elixir) de un proyecto, empezando por las más recientes, incluyendo metadatos personalizados. Filtra por `git_branch`, `status`, `is_ci` o `mix_env`. | `account_handle`, `project_handle` |
| `get_mix_build` | Obtiene los metadatos de la compilación, los conteos de diagnósticos y el resumen de la caché de dependencias. | `account_handle`, `project_handle`, `build_id` |

#### Ejecuciones de Once

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_once_runs` | Lista las ejecuciones de Once de un proyecto, empezando por las más recientes. Filtra por `kind` (`build`, `test` o `generic`), `status`, `is_ci` o `git_branch`. Las ejecuciones que no han finalizado tienen el estado `in_progress`. | `account_handle`, `project_handle` |
| `get_once_run` | Obtiene una ejecución con sus totales de acciones, resumen de caché y, para ejecuciones de prueba, los totales de pruebas. | `account_handle`, `project_handle`, `run_id` |

Los IDs de compilación de Cargo, compilación de Mix y ejecución de Once son únicos dentro de un proyecto. Las mismas lecturas están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` y `.../once/runs`, cada una con un endpoint de detalle para un ID.

#### Tareas, acciones, módulos y archivos

Estas herramientas con alcance de proyecto inspeccionan identidades de compilación persistentes entre ejecuciones. Comienza con `list_build_entities`, luego pasa un `id` estable devuelto con el mismo `kind` a `get_build_entity` o `list_build_entity_history`, junto con `account_handle` y `project_handle`. No se requiere ningún identificador de compilación o invocación.

| Herramienta | Descripción | Parámetros obligatorios |
| --- | --- | --- |
| `list_build_entities` | Lista las tareas, módulos, acciones o archivos de un tipo vistos en las compilaciones de un proyecto. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Obtiene una entidad de compilación con su identidad nativa y analíticas para el período elegido. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Lista las ejecuciones, compilaciones o eventos de caché registrados de una entidad de compilación, empezando por los más recientes. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Cadena de herramientas | Listas de historial |
| --- | --- | --- |
| `bazel_actions` | Acciones de Bazel | Ejecuciones de acciones reportadas por BEP |
| `gradle_tasks` | Tareas de Gradle | Ejecuciones de tareas |
| `xcode_modules` | Módulos de Xcode | Compilaciones y eventos de caché de módulo |
| `once_actions` | Acciones de Once | Ejecuciones |
| `mix_files` | Archivos compilados de Mix | Compilaciones |
| `mix_modules` | Módulos compilados de Mix | Compilaciones |

Estas herramientas se están desplegando gradualmente y solo devuelven datos para proyectos donde están habilitadas; para otros proyectos devuelven un error en lugar de un resultado vacío. Un tipo solo está disponible para proyectos que usan su cadena de herramientas de compilación. Las herramientas aceptan filtros acotados `start_at`/`end_at`, `environment` (`any`, `ci` o `local`) y una `branch` exacta. `list_build_entities` acepta `q`; `list_build_entity_history` admite cursores opacos `after`/`before`. Las observaciones de temporización o caché desconocidas permanecen no disponibles en lugar de convertirse en cero o fallos. El historial hace referencia al padre registrado y a la ejecución nativa para profundizar usando las herramientas de ejecución existentes.

Las métricas de `get_build_entity` incluyen `duration_samples`, el número de observaciones con temporización registrada: las duraciones cero genuinas cuentan, la temporización faltante no. Este recuento puede ser menor que el recuento de observaciones; las estadísticas de duración no disponibles permanecen nulas.

Las duraciones de los módulos de Xcode provienen de compilaciones de destino medidas en los registros de compilación. Las resoluciones de caché de módulo y los destinos sin trabajo de compilación no contribuyen muestras de duración. Las observaciones de compilación hacen referencia a la compilación de Xcode; los eventos de caché hacen referencia al comando de generación o caché.

Las acciones de Bazel se identifican por la etiqueta del destino, el mnemónico y la salida principal configurada, manteniendo acciones y configuraciones separadas distintas sin depender de resúmenes de caché dependientes de la entrada. El historial registra ejecuciones reportadas por BEP, no búsquedas de caché ni fases de perfil de traza. La cobertura completa de ejecución requiere `--build_event_publish_all_actions`; la entrega de artefactos es de mejor esfuerzo, por lo que las observaciones faltantes no son evidencia de que no se haya ejecutado ningún trabajo. Las cargas útiles antiguas de Kura sin identidad estable o inicio de ejecución siguen siendo aceptadas pero no indexadas. Las mediciones de tiempo de finalización ausentes permanecen no disponibles y las duraciones cero genuinas cuentan.

Las duraciones de los módulos de Mix miden la compilación del archivo contenedor, no el trabajo del módulo medido independientemente. Las acciones de Once usan ranuras declaradas de destino/capacidad/índice cuando el cliente reportó los mapeos de destino; las etiquetas de diagnóstico por sí solas no son identidades estables. Los clientes existentes y las herramientas a nivel de ejecución siguen siendo compatibles sin cambios.

Las lecturas analíticas tienen memoria y tiempo de ejecución acotados. Si una consulta supera esos límites, la herramienta devuelve un error en lugar de inventar un resultado vacío.

Las nuevas observaciones se indexan después del despliegue; esta función no rellena retroactivamente la telemetría de ejecución existente. Los metadatos de identidad sobreviven a las observaciones individuales bajo la <.localized_link href="/guides/server/data-retention">política de retención de datos</.localized_link>.

#### Pruebas

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_test_runs` | Lista las ejecuciones de pruebas de un proyecto. Los campos de `query` son `git_branch`, `scheme` y `status`: `field:"value"` coincide exactamente, `field~"value"` coincide con una subcadena que no distingue entre mayúsculas y minúsculas, y un `-` inicial niega cualquiera de los operadores. Por ejemplo, `-git_branch~"gh-readonly-queue"` excluye las ramas de la cola de fusión. Los filtros de consulta separados por espacios en blanco y los argumentos explícitos se combinan con semántica AND. | `account_handle`, `project_handle` |
| `get_test_run` | Obtiene métricas detalladas para una ejecución de prueba, incluidas URL de descarga temporales para su paquete de resultados (`.xcresult`) y archivo de sesión. | `test_run_id` |
| `list_test_module_runs` | Lista las ejecuciones de módulos de prueba para una ejecución de prueba específica. | `test_run_id` |
| `list_test_suite_runs` | Lista las ejecuciones de suites de prueba para una ejecución de prueba específica, opcionalmente filtradas por módulo. | `test_run_id` |
| `list_test_cases` | Lista los casos de test de un proyecto (admite filtros como `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Obtiene métricas detalladas para un caso de test, incluida la tasa de fiabilidad, la tasa de inestabilidad y los conteos de ejecuciones. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Lista las ejecuciones de casos de test, opcionalmente filtradas por caso de test o ejecución de prueba. | `account_handle`, `project_handle` |
| `get_test_case_run` | Obtiene detalles de fallos y repeticiones para una ejecución de caso de test específica. | `test_case_run_id` |
| `list_test_case_run_attachments` | Lista los archivos adjuntos para una ejecución de caso de test. Cada archivo adjunto incluye una URL de descarga temporal. | `test_case_run_id` |
| `list_test_case_events` | Lista los cambios de estado para un caso de test, como silenciarlo u omitirlo. | `test_case_id` |
| `update_test_case` | Actualiza el estado o la clasificación de inestabilidad de un caso de test. Un cambio puede enviar un evento a endpoints de webhook configurados, incluidos servicios externos. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Lista los resultados de destino de pruebas selectivas para una ejecución de prueba. | `test_run_id` |
| `get_coverage` | Obtiene la cobertura de código de un proyecto con sus destinos, en un commit o en el último commit completo de una rama. Sin `git_commit_sha` ni `branch`, lee la rama predeterminada. | `account_handle`, `project_handle` |
| `list_coverage_files` | Lista los archivos medidos por la cobertura de código de un commit, con su cobertura por línea, en un commit o en el último commit completo de una rama. Admite `search`, ordenación y paginación. | `account_handle`, `project_handle` |
| `get_coverage_file` | Obtiene la cobertura de código de un archivo y sus funciones en un commit o en el último commit completo de una rama. Establece `include_lines` para obtener el recuento de ejecución de cada línea. | `account_handle`, `project_handle`, `path` |

Las herramientas de cobertura de código están disponibles para cuentas con la cobertura de código habilitada.

#### Paquetes

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_bundles` | Lista los paquetes (binarios de app) de un proyecto. Opcionalmente filtra por `git_branch` y `tags` (todas las etiquetas deben coincidir exactamente). | `account_handle`, `project_handle` |
| `get_bundle` | Obtiene información detallada sobre un paquete específico, incluidas etiquetas personalizadas. | `bundle_id` |
| `get_bundle_artifact_tree` | Obtiene el árbol completo de artefactos para un paquete como una lista plana ordenada por ruta. | `bundle_id` |

`list_bundles` acepta `tags: ["paid", "production"]` para distinguir variantes de compilación o entornos. Las etiquetas son identificadores sensibles a mayúsculas y minúsculas que contienen letras, números, guiones o guiones bajos, con un máximo de 10 etiquetas y 50 caracteres por etiqueta. Los resultados de lista y detalle incluyen `custom_metadata.tags`. Los conteos de paginación y los filtros de rama se aplican a los resultados etiquetados; omitir `tags` conserva el comportamiento sin filtrar. Los filtros de etiquetas no válidos devuelven un error en lugar de ampliar la consulta.

#### Generaciones

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_generations` | Lista las ejecuciones de generación para un proyecto. | `account_handle`, `project_handle` |
| `get_generation` | Obtiene información detallada sobre una ejecución de generación específica. | `generation_id` |

#### Ejecuciones de caché

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_cache_runs` | Lista las ejecuciones de caché para un proyecto. | `account_handle`, `project_handle` |
| `get_cache_run` | Obtiene información detallada sobre una ejecución de caché específica. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Lista los destinos de caché de módulos para una generación o ejecución de caché, mostrando el estado de acierto/fallo de caché por destino y los hashes de componentes de diagnóstico, incluidas entradas de hash adicionales. | `run_id` |

#### Previews

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_previews` | Lista las previsualizaciones de app compartibles para un proyecto. | `account_handle`, `project_handle` |
| `get_preview` | Obtiene una previsualización y URL de descarga temporales para sus compilaciones. | `preview_id` |
| `get_latest_preview` | Encuentra la última previsualización para un binario de app en ejecución. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Automatizaciones

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_automation_alerts` | Lista las alertas de automatización para un proyecto. | `account_handle`, `project_handle` |
| `get_automation_alert` | Obtiene una alerta de automatización. | `alert_id` |
| `list_automation_alert_revisions` | Lista el historial de revisiones de una alerta de automatización. Las credenciales de acción están ocultas. | `alert_id` |
| `list_project_notification_alerts` | Lista las reglas de alerta de notificación del proyecto. Requiere el mismo permiso de administrador que la página de configuración del dashboard. Las direcciones de webhook están ocultas. | `account_handle`, `project_handle` |

### Eventos

Los clientes que usan el ciclo de vida sin estado del Protocolo de Contexto de Modelo `2026-07-28` pueden llamar a `events/list` para descubrir eventos y sus esquemas de carga útil:

| Evento | Cuándo se envía | Filtro de suscripción |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Un caso de test cambia de estable a inestable. | `account_handle`, `project_handle` |
| `build.failed` | Una compilación local o de integración continua de Xcode, Gradle o Bazel finaliza con un fallo. | `account_handle`, `project_handle` |
| `test_run.failed` | Una ejecución de prueba local o de integración continua finaliza con un fallo, incluida una ejecución fragmentada fusionada o una ejecución abandonada. | `account_handle`, `project_handle` |
| `ci_job.failed` | Un trabajo de runner de Tuist se completa con un fallo. | `account_handle` |

Para suscribirse, el cliente llama a `events/subscribe` con el nombre del evento, los identificadores listados arriba en `arguments`, y una entrega `webhook` que contiene una URL de callback `https://` y un secreto de firma `whsec_`. Los eventos de proyecto requieren membresía en la cuenta y acceso de lectura a los datos de test o compilación correspondientes; los eventos de trabajos de runner requieren membresía en la cuenta y acceso de lectura al runner. Los tokens de acceso reclamados [`auth.md`](https://workos.com/auth-md), los tokens de cuenta reclamados y las concesiones de autorización del navegador pueden crear suscripciones; la entrega se detiene cuando la credencial asociada ya no está activa. Cada usuario puede mantener hasta 25 suscripciones activas. Tuist envía un desafío de verificación al callback antes de guardar la suscripción. El callback debe devolver un objeto que contenga el mismo valor `challenge`. La suscripción dura siete días por defecto, puede renovarse volviendo a suscribirse y deja de entregar cuando se elimina el acceso o la credencial del usuario. El opcional `ttlMs` tiene un límite entre una hora y 30 días. Tuist reintenta un callback con tiempo agotado y lo cancela después de al menos tres tiempos de espera consecutivos que abarcan cinco minutos; vuelve a suscribirte después de restaurar el callback.

Cuando ocurre un evento, Tuist envía su identificador de recurso y la URL del dashboard al callback. Los fallos de compilación y de ejecución de tests también incluyen `is_ci` y `git_branch`, para que los clientes puedan ignorar los fallos locales o filtrar por rama. Los eventos de compilación incluyen `build_system`; los eventos de trabajos de runner incluyen tanto `workflow_job_id` como `workflow_run_id`. La solicitud incluye un identificador de suscripción y encabezados de firma de [Standard Webhooks](https://www.standardwebhooks.com/) para que el cliente pueda verificar su origen. Tuist reintenta las entregas fallidas, por lo que los clientes deben usar el `eventId` estable para descartar duplicados. La carga útil omite los nombres de los tests, los registros y los mensajes de error; el cliente puede obtener esos detalles a través de las herramientas anteriores y decidir si notificar a un equipo o comenzar la depuración. Los clientes pueden detener la entrega con `events/unsubscribe`.

### Prompts

| Prompt | Descripción |
|--------|-------------|
| `fix_flaky_test` | Te guía en la corrección de un test inestable analizando patrones de fallo, identificando la causa raíz y aplicando una corrección específica. |
| `compare_builds` | Te guía en la comparación de dos ejecuciones de compilación para identificar regresiones de rendimiento, cambios en la caché y problemas de compilación. Funciona con proyectos Xcode y Gradle. |
| `compare_test_runs` | Te guía en la comparación de dos ejecuciones de tests para identificar regresiones, nuevos fallos y tests inestables. |
| `compare_bundles` | Te guía en la comparación de dos bundles para identificar cambios de tamaño en todo el árbol de artefactos. |
| `compare_test_case` | Te guía en la comparación del comportamiento de un caso de test entre dos ramas o periodos de tiempo. |
| `compare_generations` | Te guía en la comparación de dos ejecuciones de generación para identificar regresiones de rendimiento y cambios en la caché de módulos. |
| `compare_cache_runs` | Te guía en la comparación de dos ejecuciones de caché para identificar cambios en la eficacia de la caché y regresiones a nivel de destino. |
| `integrate_gradle_project` | Te guía en la integración de Tuist en un proyecto Gradle existente. Incluye autenticación separada para la herramienta y Gradle, descubrimiento de cuentas, creación de proyectos, política de caché remota, análisis de compilaciones y verificación de lectura. |
| `integrate_bazel_project` | Te guía en la creación o selección de un proyecto Bazel, la autenticación de la línea de comandos, la configuración de la caché remota y los análisis de compilación, y la verificación de la integración a través de los datos de compilación de Tuist. |
| `integrate_xcode_project` | Te guía en la integración de Tuist en un proyecto Xcode existente. Admite caché de Xcode, análisis de compilaciones, análisis de tests y fragmentación de tests. |
| `ask_tuist` | Responde a una pregunta sobre Tuist utilizando material público como contexto y evidencia focalizada de implementación y tests como fuente de verdad para el comportamiento actual. Requiere una `question` y cita evidencia fijada a una revisión. |

Los prompts de datos de proyecto aceptan `account_handle` y `project_handle` para delimitar la investigación a un proyecto específico. Los prompts de comparación también aceptan los argumentos `base` y `head` para especificar los dos elementos a comparar (por ID, URL del dashboard o nombre de rama). `ask_tuist` acepta una `question` en lugar de parámetros de proyecto. `integrate_gradle_project` también acepta `features`, una lista separada por comas de integraciones de Gradle a aplicar: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` y `test_sharding`. `integrate_bazel_project` acepta un `server_url` opcional para instalaciones autoalojadas o locales. `integrate_xcode_project` acepta `features` con `xcode_cache`, `build_insights`, `test_insights` y `test_sharding`.

#### Funcionalidades del prompt de integración de Gradle

El prompt `integrate_gradle_project` y la herramienta `get_gradle_integration_guide` documentan el flujo de trabajo completo de configuración. La herramienta también es referenciada por las instrucciones de inicialización del servidor, lo que la hace detectable por agentes que no enumeran prompts.

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `remote_cache` | Habilita la caché de compilación de Gradle, configura la política de subida de caché remota de Tuist y recomienda subir solo desde runners de integración continua con uso local de solo lectura. |
| `build_insights` | Aplica el plugin de Tuist para Gradle y configura el comportamiento de subida de análisis de compilación cuando sea necesario. |
| `test_insights` | Aplica el plugin de Tuist para Gradle para que los resultados de la tarea `Test` de Gradle se suban automáticamente. |
| `flaky_tests` | Guía la configuración para la detección de tests inestables, el uso opcional del plugin Gradle Test Retry y la configuración de cuarentena de tests. |
| `test_sharding` | Añade el flujo de trabajo de integración continua para `tuistPrepareTestShards`, la generación de la matriz de fragmentos y la ejecución de tests basada en `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones quiere el usuario o que infiera el conjunto útil más pequeño de la solicitud antes de editar el proyecto Gradle.

#### Funcionalidades del prompt de integración de Xcode

El prompt `integrate_xcode_project` documenta cada integración de Xcode que admite Tuist:

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `xcode_cache` | Configura `tuist setup cache`, la configuración de caché de proyectos generados, la configuración manual de compilación de la caché de Xcode y una política de subida limitada a runners de integración continua. |
| `build_insights` | Configura `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` y métricas opcionales de la máquina a través de `tuist setup insights`. |
| `test_insights` | Configura `tuist inspect test`, las post-acciones de test del esquema y la generación de bundles de resultados para ejecuciones de tests de integración continua. |
| `test_sharding` | Añade la planificación de fragmentos para Xcode o proyectos generados y el flujo de trabajo de ejecución de fragmentos con `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones quiere el usuario o que infiera el conjunto útil más pequeño de la solicitud antes de editar el proyecto Xcode.
