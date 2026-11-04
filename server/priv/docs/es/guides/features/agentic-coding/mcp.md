---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Codificación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Proporciona a los agentes de IA acceso a análisis de tests y más a través del endpoint MCP de Tuist."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) es un estándar abierto que permite a los agentes de inteligencia artificial interactuar con servicios externos y fuentes de datos. Hace que aplicaciones como [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) y editores como [Zed](https://zed.dev), [Cursor](https://www.cursor.com) o [Visual Studio Code](https://code.visualstudio.com) sean interoperables con Tuist.

Tuist aloja un extremo de Model Context Protocol en el servidor en `https://tuist.dev/mcp`. Al conectar tu cliente a él, los agentes pueden acceder a los datos de tu proyecto de Tuist, incluidos análisis de tests, análisis de tests inestables y más. La mayoría de las herramientas son de solo lectura y están limitadas a los datos autenticados del proyecto de Tuist. Las herramientas de configuración de cuentas pueden listar cuentas, crear organizaciones, crear proyectos y añadir usuarios existentes a organizaciones cuando el usuario autenticado tiene los permisos necesarios. Cada herramienta anuncia anotaciones que indican si es de solo lectura, si puede provocar un cambio difícil de revertir y si puede cambiar el estado público de Internet. Las herramientas de configuración de cuentas requieren autenticación de usuario. No están disponibles para tokens de proyecto ni para tokens de cuenta ordinarios. Cuando un usuario autoriza un cliente en el navegador o reclama un registro de `auth.md`, Tuist asocia esa credencial con el usuario únicamente en el extremo de Model Context Protocol, para que las herramientas de configuración puedan completar el flujo solicitado.

Tuist implementa el [protocolo 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http). Las solicitudes no tienen estado: los clientes envían sus metadatos de protocolo con cada solicitud y pueden llamar a las herramientas directamente sin inicialización. `server/discover` devuelve la identidad del servidor, las capacidades, las versiones admitidas y las instrucciones. No hay identificadores de sesión ni flujos de eventos independientes. Los clientes que usan el flujo de inicialización 2025-06-18 o 2025-03-26 siguen siendo compatibles; también operan sin sesiones de servidor.

## Model Context Protocol frente a skills

Las herramientas de Model Context Protocol y las <.localized_link href="/guides/features/agentic-coding/skills">skills</.localized_link> pueden solaparse en lo que hacen. Dada la superposición actual entre ambas, elige un enfoque por flujo de trabajo y úsalo de forma consistente en lugar de mezclar ambos en el mismo flujo.

Para clientes que admiten la instalación de plugins, usa los <.localized_link href="/guides/features/agentic-coding/plugins">plugins de Tuist</.localized_link> para instalar ambos juntos.

## Configuración

Añade `https://tuist.dev/mcp` como un servidor remoto de Model Context Protocol en tu cliente. Las instrucciones de inicialización del servidor y la tarjeta pública del servidor describen OAuth 2.0 con registro dinámico de clientes y el flujo estándar de autorización en el navegador de forma integrada, sin pedir a los agentes que obtengan o sigan documentos de autenticación externos. Estas instrucciones generales del servidor mantienen la guía del flujo de trabajo genérica: la autenticación de herramientas no autentica herramientas locales de línea de comandos ni integraciones del sistema de compilación, y los agentes deben verificar los cambios solicitados a través de las herramientas relevantes de Tuist. La configuración específica del sistema de compilación y las comprobaciones de autenticación están documentadas en las guías de integración y en los prompts. Tuist sigue anunciando tanto los metadatos de descubrimiento de [Open Authorization](https://oauth.net/2/) como el actual [protocolo auth.md](https://workos.com/auth-md) en `https://tuist.dev/auth.md` por separado.

Si una de tus organizaciones exige inicio de sesión único, autorizar un cliente en el navegador requiere una sesión iniciada a través de esa organización, y Tuist te redirige al proveedor primero cuando sea necesario. Consulta <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">inicio de sesión único</.localized_link>.

El extremo acepta el ciclo de vida de solicitudes de Model Context Protocol sin estado `2026-07-28`, incluido `server/discover`, junto con el ciclo de vida basado en sesiones anterior. Los clientes existentes pueden seguir usando su método de conexión actual.

Los clientes que admiten eventos de Model Context Protocol pueden suscribirse a eventos del proyecto. Consulta [Eventos](#events) para conocer los requisitos de eventos disponibles y de entrega.

Los clientes que ya admiten autenticación remota en el navegador pueden seguir autenticándose en el navegador. Los clientes y agentes que admiten `auth.md` pueden registrarse de forma anónima, presentar una aserción de identidad de proveedor de confianza o iniciar una reclamación de correo electrónico autenticada por servicio. El registro devuelve una aserción de identidad firmada por Tuist, que el agente intercambia en el extremo estándar de tokens por un token de acceso de una hora. Tuist publica su clave pública de firma y admite la revocación estándar de tokens y la entrega de eventos de seguridad del proveedor.

Un agente no autenticado debe leer la cabecera `WWW-Authenticate` devuelta por el extremo de Model Context Protocol, obtener los metadatos del recurso protegido, obtener los metadatos del servidor de autorización y seguir su URL `agent_auth.skill`. Tuist también devuelve la misma URL local `auth_md` en el cuerpo de la respuesta no autorizada para que los clientes impulsados por modelos de lenguaje puedan descubrir el flujo sin depender de una integración nativa del cliente. El documento local del despliegue es la fuente de verdad para los nombres de los extremos, los cuerpos de las solicitudes, el sondeo de reclamaciones y el intercambio de aserciones.

Antes de que un agente inicie una reclamación de correo electrónico, debe pedir al usuario que confirme la dirección de correo electrónico de su cuenta de Tuist. No debe inferir esa dirección a partir de un perfil de proveedor, configuración de Git, variable de entorno o metadatos de sesión.

El extremo utiliza el grupo de ámbitos `mcp`. Una credencial anónima previa a la reclamación puede descubrir capacidades y leer la guía de integración pública, pero no se trata como un usuario conectado. Tras la autorización en el navegador o la reclamación, la credencial tiene ámbito de usuario y cada herramienta aplica las mismas comprobaciones de autorización que el panel de control. Consulta la <.localized_link href="/guides/server/authentication#scope-groups">documentación de grupos de ámbitos</.localized_link> para más detalles.

Las herramientas se resuelven a los proyectos que el usuario autenticado ya puede leer. Las herramientas de compilación de Xcode y Gradle aceptan un UUID de compilación o una URL del panel de control. El UUID debe identificar exactamente un proyecto; si aparece en varios proyectos, la herramienta devuelve "no encontrado" en lugar de seleccionar el informe de otro proyecto. Las lecturas del panel de control y de la API con ámbito de proyecto siguen estando disponibles. Los identificadores de actor reportados son etiquetas no verificadas, no credenciales ni derechos de acceso adicionales.

Las herramientas de lista y detalle de compilaciones exponen metadatos opcionales `tuist_version`: la CLI de Tuist que informa para Xcode y Cargo, el plugin de Tuist Gradle para Gradle y la biblioteca `tuist_ex` para Mix. Xcode también expone `tuist_generation_version` a partir de su evento vinculado de generación de proyecto, que puede diferir de la CLI que realiza la carga. Las observaciones faltantes son nulas, no se infieren del servidor ni de otro informe. Bazel utiliza su `bazel_version` existente; los detalles de ejecución de Once exponen `once_version`. Estos campos describen las versiones reportadas, no la identidad verificada ni las versiones del contrato de red. Los extremos REST de compilación exponen los mismos metadatos. Las habilidades existentes de integración y de tests inestables no dependen de los campos de versión y no requieren cambios en el flujo de trabajo.

Los operadores de Tuist que investigan la cuenta de un cliente lo hacen a través de las herramientas internas de operaciones de Tuist, que registran cada llamada; una conexión directa a este extremo no obtiene acceso más allá de las propias membresías del usuario.

<details>
<summary>Claude Code</summary>

Ejecuta:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Cuando un cliente headless de Claude Code no expone al modelo una conexión fallida con el servidor nativo, exige al agente que inspeccione la respuesta no autenticada de [Protocolo de transferencia de hipertexto](https://developer.mozilla.org/en-US/docs/Web/HTTP) del extremo configurado antes de buscar documentación alojada o editar el proyecto. La respuesta indica al modelo el documento `auth.md` local del despliegue incluso cuando la autenticación en el navegador no está disponible.

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

Establecer `auth` como `false` evita que el manejador de autenticación del navegador del adaptador oculte la respuesta no autorizada de Tuist. Un agente headless puede entonces leer la URL `auth_md` devuelta y seguir el flujo de registro, intercambio de aserciones de identidad y sondeo de reclamaciones de Tuist. Configura el token de acceso intercambiado como un token bearer o permite que el agente realice llamadas autenticadas de Model Context Protocol directamente.

Si prefieres la autenticación en el navegador, establece `auth` como `"oauth"`. Para ese flujo, mantén un proceso activo con el [modo de llamada a procedimiento remoto](https://pi.dev/docs/latest/rpc) de Pi mientras se completa la autenticación:

```bash
pi --mode rpc
```

No dividas una autenticación pendiente en el navegador entre varias invocaciones de `pi --print` porque el proceso que posee el estado de la devolución de llamada ya ha finalizado.

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

Usa **Command Palette → MCP: Add Server** y configura un servidor de [Protocolo de transferencia de hipertexto](https://developer.mozilla.org/en-US/docs/Web/HTTP) con:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

Abre **Agent panel → Settings → Add Custom Server** y configura:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Si tu agente admite `auth.md`, puede iniciar sesión de forma anónima sin abrir un navegador. Una identidad de proveedor de confianza también puede completarse sin navegador cuando la identidad del proveedor ya está vinculada. Para correo electrónico autenticado por servicio, reclamación anónima o un primer vínculo de proveedor, el agente te muestra un enlace de verificación de Tuist y un código de seis dígitos. Abre el enlace, inicia sesión e introduce el código del agente en la página de Tuist. Nunca envíes el código de vuelta al agente. Los metadatos del servidor de autorización de Tuist apuntan directamente al `/auth.md` propio del despliegue, que contiene las estructuras exactas de solicitud y sondeo.

## WebMCP

En los navegadores que admiten [WebMCP](https://webmachinelearning.github.io/webmcp), las páginas de Tuist registran herramientas con `document.modelContext`, por lo que los agentes integrados en el navegador pueden llamarlas sin configuración adicional. Las llamadas se ejecutan en el servidor de Tuist.

- **Las páginas del sitio web y de documentación** registran las herramientas de documentación y de código fuente (`search_tuist`, `search_tuist_code`, `list_tuist_files` y `read_tuist_file`). No necesitas iniciar sesión.
- **Las páginas del panel de control de una cuenta**, cuando has iniciado sesión, registran las herramientas de solo lectura de Tuist para esa cuenta. Cada página registra únicamente las herramientas correspondientes a lo que muestra, según el sistema de compilación del proyecto: la página de compilaciones de un proyecto de Gradle recibe las herramientas de compilación de Gradle, sus páginas de tests reciben las herramientas de tests y cobertura, y las páginas de runners reciben las herramientas de runners. Cada página también recibe las herramientas de documentación, `list_projects` y `get_project`. Las herramientas se ejecutan como el usuario conectado, por lo que solo acceden a los datos que puedes leer en el panel de control y únicamente a la cuenta que estás consultando. Cuando te desplazas a otra página o cuenta, las herramientas se reemplazan por las de esa página.

Las herramientas que crean, modifican o eliminan datos no están disponibles a través de WebMCP, porque un agente del navegador recibe las herramientas sin que tú las añadas y lee contenido generado por compilaciones y tests. Conecta un cliente MCP al extremo `/mcp` para usar esas herramientas.

Si la organización exige inicio de sesión único, inicia sesión en el panel de control con su proveedor para usar sus herramientas.

## Las integraciones del sistema de compilación usan dos credenciales

La credencial usada para las herramientas del Model Context Protocol no autentica el plugin de Gradle ni los servicios remotos de Bazel. Antes de que un agente edite o verifique una integración de Gradle o Bazel, debe ejecutar:

```bash
tuist auth whoami --url https://tuist.dev
```

Si ese comando no está autenticado, el agente debe detenerse y pedir al usuario que ejecute:

```bash
tuist auth login --url https://tuist.dev
```

Para un despliegue local o autoalojado, reemplaza la URL en ambos comandos y en `tuist.toml`. Mantén la escritura del nombre de host idéntica en todas partes. Por ejemplo, `localhost` y `127.0.0.1` usan credenciales almacenadas separadas.


## Capacidades

### Herramientas

Las siguientes herramientas están disponibles a través del servidor de Tuist Model Context Protocol:

Cada herramienta publica una descripción legible junto con esquemas explícitos de entrada y salida. Las llamadas exitosas devuelven contenido estructurado que cumple con el esquema de salida anunciado, además del mismo resultado serializado como texto para clientes que aún no consumen contenido estructurado.

Las herramientas que aceptan el identificador de un único registro, como `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` o `cache_run_id`, también aceptan la URL del panel de control de Tuist de ese registro. Pega la URL directamente desde el navegador en lugar de extraer el identificador de ella.

#### Búsqueda en documentación y comunidad

Esta herramienta de solo lectura busca en la documentación de Tuist, la referencia de la [interfaz de programación de aplicaciones](https://en.wikipedia.org/wiki/API), las versiones de GitHub, el foro de la comunidad y los issues de GitHub a través del mismo motor de búsqueda que impulsa el sitio de documentación. Los resultados de las versiones incluyen el producto, la versión, la fecha de publicación y el estado de prelanzamiento. Las versiones estables se buscan por defecto, y los prelanzamientos pueden incluirse con `include_prereleases`. La herramienta solo está disponible en el servidor alojado por Tuist en `https://tuist.dev/mcp`.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `search_tuist` | Busca en la documentación pública de Tuist, la referencia de la interfaz de programación de aplicaciones, las versiones de GitHub, las discusiones de la comunidad y los issues de GitHub. Opcionalmente, restringe a una `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Comentarios

Los agentes pueden informar al equipo de Tuist cuando una herramienta o prompt de Tuist no funcionó como esperaban, como un resultado confuso, un error, datos faltantes o una capacidad ausente. Se pide a los agentes que sugieran un informe y lo envíen solo una vez que tú aceptes. Cada informe abre una conversación con el soporte de Tuist, que puede responderte por correo electrónico. Un informe incluye lo que el agente esperaba, lo que ocurrió, una sugerencia opcional, tu ID de usuario de Tuist, tu handle y correo electrónico, y las organizaciones a las que perteneces. Los agentes también pueden nombrar la cuenta y el proyecto donde ocurrió el problema, para que el equipo sepa con qué organización hacer seguimiento; solo se aceptan cuentas a las que pertenezcas. Solo los agentes iniciados sesión como usuario de Tuist pueden enviar informes, y cada usuario puede abrir hasta 10 informes por hora. La herramienta solo está disponible en el servidor alojado por Tuist en `https://tuist.dev/mcp`.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `report_feedback` | Informa de un problema con una herramienta o prompt de Tuist. Opcionalmente, nombra la `tool_name`, la `account_handle` y el `project_handle` donde ocurrió, y añade una `suggestion`. | `category`, `expected`, `actual` |

#### Respuestas respaldadas por código fuente

Estas herramientas de solo lectura permiten a los agentes usar la revisión exacta del código fuente público de Tuist desplegada junto con el servidor alojado como fuente de verdad para respuestas que dependen del comportamiento actual. Solo están disponibles en `https://tuist.dev/mcp`.

Los clientes compatibles reciben descripciones factuales de la revisión del código fuente de las herramientas, enlaces y límites de resultados durante la inicialización, junto con información de autenticación OAuth integrada. Estas descripciones no prescriben el estilo de respuesta ni un flujo de trabajo de verificación. Los usuarios pueden hacer una pregunta directamente sin invocar primero el prompt `ask_tuist`; el prompt sigue disponible para un flujo de trabajo explícito respaldado por código fuente.

Cada operación tiene límites fijos para concurrencia, duración, recorrido, bytes leídos y tamaño de respuesta. Los resultados de búsqueda y listado incluyen los campos `truncated` y `truncation_reason`. Cuando un resultado está truncado, reduce la ruta, el patrón de archivo o el término de búsqueda en lugar de tratar el resultado como exhaustivo.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `search_tuist_code` | Responde preguntas sobre el comportamiento actual, valores predeterminados, configuración, puertas de características, manejo de errores o detalles no documentados buscando en archivos de código fuente. Los resultados incluyen líneas circundantes, enlaces al código fuente fijados a la revisión y estadísticas de escaneo. | `pattern` |
| `list_tuist_files` | Descubre un subsistema de código fuente o tests cercanos cuando la ruta relevante es desconocida. Los listados tienen profundidad y conteos de resultados acotados. | Ninguno |
| `read_tuist_file` | Inspecciona un rango de líneas enfocado en un archivo de implementación, sitio de llamada o test después de encontrar la ruta relevante. Las respuestas truncadas proporcionan `next_start_line` para continuar. | `path` |

#### Proyectos

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_accounts` | Lista los handles de cuentas personales y de organización disponibles para el usuario autenticado, incluyendo si cada cuenta puede crear proyectos. | Ninguno |
| `get_organization` | Obtén el directorio de miembros de una organización. Las invitaciones pendientes requieren el mismo permiso de administrador que el panel de control; los tokens de aceptación de invitación nunca se devuelven. | `account_handle` |
| `create_organization` | Crea una organización de Tuist para el usuario autenticado. | `handle` |
| `create_project` | Crea un proyecto de Tuist bajo una cuenta a la que el usuario autenticado pueda acceder. | `account_handle`, `project_handle` |
| `add_organization_member` | Añade un usuario existente de Tuist a una organización o actualiza el rol de un miembro existente. Acepta `user` (por defecto), `admin` o `viewer`, donde un viewer puede leer paneles y ejecuciones pero no puede cambiar nada. | `organization_handle`, `email` |
| `invite_organization_member` | Invita una dirección de correo electrónico a una organización, pertenezca o no a un usuario existente de Tuist. Tuist envía por correo un enlace de aceptación que expira después de 14 días; cuando el servidor no puede enviar el correo, `email_sent` es `false` y el enlace debe copiarse desde el panel de control. Acepta `user` (por defecto), `admin` o `viewer`. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Cancela una invitación pendiente a una organización para que su enlace ya no pueda ser aceptado. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `list_projects` | Lista todos los proyectos accesibles para el usuario autenticado. | Ninguno |
| `get_project` | Obtén la configuración de un proyecto y la URL del repositorio conectado. | `account_handle`, `project_handle` |
| `connect_project_repository` | Vincula un proyecto a un repositorio de GitHub al que la instalación de GitHub App de la cuenta pueda acceder. El proyecto adopta la rama predeterminada del repositorio. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Elimina el vínculo de un proyecto con su repositorio de GitHub. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle` |

#### Tokens de cuenta

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_account_tokens` | Lista los metadatos de los tokens de cuenta sin exponer sus valores. | `account_handle` |
| `get_account_token` | Obtén los metadatos de un token de cuenta sin exponer su valor. | `account_handle`, `token_id` |
| `list_project_tokens` | Lista los metadatos de los tokens de proyecto sin exponer sus valores. | `account_handle`, `project_handle` |

#### Runners de integración continua

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_runner_jobs` | Lista los trabajos de runner de integración continua para una cuenta. | `account_handle` |
| `get_runner_job` | Obtén un trabajo de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Lista los pasos registrados para un trabajo de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Lista las métricas de máquina registradas para un trabajo de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Lista hasta 500 líneas de log capturadas para un trabajo de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Lista los resúmenes de flujos de trabajo de integración continua para una cuenta. | `account_handle` |
| `list_runner_profiles` | Lista los perfiles de runner de integración continua para una cuenta, con la etiqueta `runs-on` de cada uno. | `account_handle` |
| `get_runner_catalog` | Lista las formas de máquina y versiones de Xcode que un perfil de runner puede usar. | `account_handle` |
| `create_runner_profile` | Crea un perfil de runner con una plataforma, una forma de máquina y, en macOS, una versión de Xcode. Opcionalmente establece qué ramas guardan sus volúmenes de caché. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Cambia la forma de máquina, la versión de Xcode o qué ramas guardan los cambios de su volumen de caché personalizado de un perfil de runner. Los campos omitidos conservan su valor. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Elimina un perfil de runner tras la confirmación del usuario. Los perfiles predeterminados no se pueden eliminar. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |

Las herramientas de volumen de runner exponen los mismos datos que el panel de Volúmenes. Las herramientas de lectura requieren acceso al runner; el borrado requiere administración de cuenta o el ámbito `account:runners:write`, y confirmación del usuario.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_runner_volumes` | Filtra por nombre y repositorio, ordena y paginación de volúmenes. | `account_handle` |
| `get_runner_volume` | Repositorio, plataforma, capacidad, espacio usado y último uso. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Referencias paginadas de trabajos y flujos de trabajo, estado de caché, resultado de acierto y tiempo de montaje. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Volúmenes montados por un trabajo. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Series de almacenamiento, ejecuciones de trabajos, tasa de aciertos y tendencias. Opcionales `volume_id`, `start` y `end` (ISO 8601); por defecto siete días, máximo 90. | `account_handle` |
| `clear_runner_volume` | Borra el contenido guardado. Los trabajos en ejecución conservan sus copias privadas pero no pueden guardarlas; los trabajos posteriores comienzan vacíos. | `account_handle`, `volume_id` |

Las listas aceptan `page` y `page_size` (hasta 100). El inventario de volúmenes también acepta `name` y `repository` (coincidencias exactas, combinadas con AND), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) y `sort_order` (`asc`, `desc`). Las mediciones desconocidas y los resultados de acierto permanecen como `null`. El estado de caché describe si se guardaron los cambios del volumen, no el éxito del trabajo.

#### Webhooks

Las herramientas de webhook usan el mismo permiso exclusivo para administradores que el panel. Los intentos de entrega contienen los datos de solicitud y respuesta registrados para el endpoint, pero nunca el secreto de firma del endpoint.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Lista los endpoints de webhook para una cuenta. | `account_handle` |
| `get_webhook_endpoint` | Obtén un endpoint de webhook. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Lista los intentos de entrega para un endpoint. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Obtén un intento de entrega. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Compilaciones de Xcode

Las herramientas de detalle de compilación para Xcode, Gradle, Bazel, Mix y Cargo exponen la estructura existente `custom_metadata: {tags, values}`, incluidas las observaciones de infraestructura cuando se reportan. Los valores siguen siendo cadenas y las claves desconocidas se preservan. Por ejemplo, `tuist.cpu.available_processors` describe los procesadores lógicos disponibles en tiempo de ejecución, mientras que `tuist.gradle.max_workers` es un límite de workers de Gradle y `tuist.jvm.max_heap_bytes` es un límite de heap de JVM, no de memoria del host. Estas son observaciones de cliente no confiables, no identidades de runner verificadas. Las observaciones ausentes permanecen ausentes; los logs importados y los clientes antiguos pueden no tener metadatos de infraestructura. La metadata única espera una actualización coordinada del cliente/protocolo.

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_xcode_builds` | Lista las ejecuciones de compilación de Xcode para un proyecto. | `account_handle`, `project_handle` |
| `get_xcode_build` | Obtén información detallada sobre una ejecución de compilación de Xcode específica, incluida una URL de descarga temporal para el archivo que contiene el `.xcactivitylog` raw. | `build_run_id` |
| `list_xcode_build_targets` | Lista los targets de compilación para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_files` | Lista los archivos compilados para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_steps` | Lista los pasos de compilación registrados con tiempos y resultados, sin texto de log. | `build_run_id` |
| `get_xcode_build_step` | Obtén un paso de compilación registrado, incluido su log y la bandera de truncamiento. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Lista los problemas de compilación (advertencias y errores) para una ejecución de compilación específica. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Lista las tareas cacheables (aciertos/fallos de caché) para una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Lista las salidas de [almacenamiento direccionable por contenido](https://en.wikipedia.org/wiki/Content-addressable_storage) para una ejecución de compilación de Xcode específica. | `build_run_id` |

`list_xcode_build_steps` devuelve páginas de 20 pasos por defecto (máximo 100 mediante `page_size`), con `page` y `pagination_metadata` para la navegación. Usa `search` para coincidir con títulos, proyectos o targets, o filtra por `project`, `target`, `category` exactos (por ejemplo, `swiftCompilation`) y `status` (`success` o `failure`). Ordena por `duration_ms` para los más lentos primero (el valor predeterminado) o por `start_ms` para orden cronológico. Los IDs de paso desempatan y se devuelven como cadenas decimales para preservar su precisión completa de 64 bits. Los IDs están limitados a una compilación y no deben coincidir entre compilaciones.

Los opcionales `start_ms` y `end_ms` seleccionan pasos que se solapan con un rango de tiempo en milisegundos desde el inicio de la compilación; el final es exclusivo. Ambas herramientas aceptan un UUID de compilación o una URL del panel como `build_run_id`. Pasa el `id` de paso devuelto sin cambios como `step_id` para recuperar su log. Los logs retienen hasta 64 KiB por paso, con `log_truncated` indicando la salida omitida.

Los pasos se recopilan por defecto cuando se procesan las compilaciones de Xcode. Los datos de pasos registrados se conservan durante 90 días. La respuesta de la lista incluye `availability`: `available` cuando existen pasos registrados, aunque ningún filtro coincida; `processing` cuando la compilación aún se está procesando y no tiene pasos todavía; o `unavailable` cuando los pasos no se registraron o han caducado.

Las mismas operaciones están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` y `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`, con los mismos filtros y paginación. Ambas requieren acceso de lectura al proyecto de la compilación.

#### Compilaciones de Gradle

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Devuelve la autenticación completa, la configuración del proyecto, el plugin de Gradle, la política de caché y el flujo de verificación de dos compilaciones. Los agentes deben llamarla antes de editar un proyecto Android o Gradle existente. | Ninguno |
| `list_gradle_builds` | Lista las ejecuciones de compilación de Gradle para un proyecto, incluidos metadatos personalizados. Filtra por una etiqueta personalizada con el parámetro opcional `tag`. | `account_handle`, `project_handle` |
| `get_gradle_build` | Obtén los metadatos de la compilación y los conteos de tareas/caché. | `build_run_id` |
| `list_gradle_build_tasks` | Lista los resultados de las tareas, la identidad de compilación compuesta, la capacidad de caché y el estado incremental. | `build_run_id` |
| `list_gradle_build_steps` | Lista las tareas cronometradas, la configuración y las transformaciones, con búsqueda, metadatos y filtros de tiempo superpuestos. | `build_run_id` |
| `get_gradle_build_step` | Inspecciona los metadatos de un paso registrado mediante su ID opaco; los logs por paso no están disponibles. | `build_run_id`, `step_id` |

Las listas de pasos de Gradle y Bazel devuelven por defecto 20 resultados (máximo 100), admiten `search`, coincidencias exactas de `project`, `target`, `category` y `status`, filtros superpuestos de `start_ms` / `end_ms` (fin exclusivo) y ordenación por `duration_ms` o `start_ms`. Pasa los IDs devueltos sin cambios; están asociados a su compilación. Las listas exponen `time_origin` y `coverage`. Los informes antiguos de Gradle usan `first_recorded_timestamp` porque no se subió el inicio de la compilación. Los perfiles de Bazel exponen todos los intervalos registrados con cobertura `trace_profile` y `profile_start` como origen temporal. Las compilaciones antiguas recurren a resúmenes BEP conservados. Los registros fuente caducan tras 90 días. Los detalles de Bazel incluyen logs de acciones sanitizados cuando se publican; el detalle `log` de Gradle es null. El prompt `compare_builds` usa esta cobertura para distinguir trazas completas de Bazel de resúmenes conservados y dirige a los agentes a los detalles de los pasos para obtener resultados de acciones y logs antes de revisar la salida más amplia de la invocación.

Los IDs de pasos de Bazel devueltos desde resúmenes conservados siguen siendo legibles si llega un perfil completo entre el listado y la obtención de un paso. Un perfil indexado cuyos datos de paso han caducado informa como no disponible. Las listas de pasos de Gradle incluyen operaciones en caché y omitidas de duración cero.

#### Invocaciones de Bazel

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Devuelve la autenticación, la configuración del proyecto, la configuración de Bazel y el flujo de verificación. | Ninguno |
| `list_bazel_invocations` | Lista las invocaciones completadas del [Protocolo de Eventos de Compilación de Bazel](https://bazel.build/remote/bep) con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales correlacionados de caché remota para un proyecto. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Obtén una invocación de Bazel completada con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales correlacionados de caché remota. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Lista los intervalos registrados del perfil de Bazel, con filtros y cobertura explícita. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Inspecciona un paso de Bazel registrado y su resultado de acción publicado y log sanitizado. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_invocation_logs` | Lista los logs de pruebas sanitizados capturados para una invocación de Bazel en orden de ejecución. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Obtén un log de prueba sanitizado capturado para una invocación de Bazel. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | Lista las observaciones brutas de caché remota de Bazel con su operación, endpoint y hora de observación, opcionalmente filtradas por invocación, resultado u operación. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Obtén una observación bruta de caché remota de Bazel. | `account_handle`, `project_handle`, `cache_event_id` |

#### Compilaciones de Cargo

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_cargo_builds` | Lista las compilaciones de Cargo para un proyecto, mostrando primero las más recientes. Filtra por `git_branch`, `status`, `is_ci` o `command`. Los resultados de ejecución de pruebas de Cargo están disponibles a través de las herramientas de pruebas, no en este listado de compilaciones. | `account_handle`, `project_handle` |
| `get_cargo_build` | Obtén los metadatos de la compilación, los contadores agregados de caché y hasta 500 trabajos de compilador registrados con diagnósticos. `compilations_truncated` indica los trabajos omitidos; los diagnósticos cubren solo los trabajos devueltos. | `account_handle`, `project_handle`, `build_id` |

Establece `include_cache_inspection: true` en `get_cargo_build` para recuperar decisiones de tareas validadas y operaciones CAS, limitado a 4 MB. Por defecto, y cuando los registros faltan o son inválidos, `cache_inspection` es null. Respeta su indicador `truncated` de captura parcial; las transferencias no establecen el origen local/remoto de cada acierto de tarea. El endpoint de detalle HTTP acepta el mismo parámetro de consulta.

#### Compilaciones de Mix

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_mix_builds` | Lista las compilaciones de compilación de Mix (Elixir) para un proyecto, mostrando primero las más recientes, incluidos metadatos personalizados. Filtra por `git_branch`, `status`, `is_ci` o `mix_env`. | `account_handle`, `project_handle` |
| `get_mix_build` | Obtén los metadatos de la compilación, los conteos de diagnósticos y el resumen de la caché de dependencias. | `account_handle`, `project_handle`, `build_id` |

#### Trazas de compilación

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `get_build_trace` | Obtén un enlace de descarga para la línea de tiempo de una compilación de Xcode, Gradle, Bazel o Mix como un archivo de traza que puedes abrir en [Perfetto](https://ui.perfetto.dev). | `account_handle`, `project_handle`, `build_id` |

`build_id` es el ID de ejecución de la compilación (el ID de invocación para Bazel) o la URL del panel de la compilación. El `trace_url` devuelto sirve un archivo JSON de [Evento de Traza de Chrome](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU). Cualquier persona que tenga el enlace puede descargar la traza de esa compilación sin otras credenciales hasta `expires_at`, una hora después de la llamada. Los agentes pueden descargarla con `curl`, entregártela para abrirla en Perfetto o consultarla con `trace_processor` de Perfetto. La traza contiene los pasos registrados empaquetados en carriles según el paralelismo, una pista que abarca toda la compilación y contadores de CPU y memoria cuando la compilación registró métricas de la máquina. Contiene los mismos datos que las herramientas de pasos anteriores, sin logs. El panel ofrece el mismo archivo desde la pestaña Línea de tiempo de cada compilación.

#### Ejecuciones de Once

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_once_runs` | Lista las ejecuciones de Once para un proyecto, mostrando primero las más recientes. Filtra por `kind` (`build`, `test` o `generic`), `status`, `is_ci` o `git_branch`. Las ejecuciones que no han finalizado tienen el estado `in_progress`. | `account_handle`, `project_handle` |
| `get_once_run` | Obtén una ejecución con sus totales de acciones, resumen de caché y, en el caso de ejecuciones de tests, los totales de tests. | `account_handle`, `project_handle`, `run_id` |

Los IDs de compilación de Cargo, compilación de Mix y ejecución de Once son únicos dentro de un proyecto. Las mismas lecturas están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` y `.../once/runs`, cada una con un endpoint de detalle para un ID.

#### Tareas, acciones, módulos y archivos

Estas herramientas con alcance de proyecto inspeccionan identidades de compilación persistentes entre ejecuciones. Comienza con `list_build_entities`, luego pasa un `id` estable devuelto con el mismo `kind` a `get_build_entity` o `list_build_entity_history`, junto con `account_handle` y `project_handle`. No se requiere ningún identificador de compilación o invocación.

| Herramienta | Descripción | Parámetros requeridos |
| --- | --- | --- |
| `list_build_entities` | Lista las tareas, módulos, acciones o archivos de un tipo vistos en las compilaciones de un proyecto. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Obtén una entidad de compilación con su identidad nativa y analíticas para el período elegido. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Lista las ejecuciones, compilaciones o eventos de caché registrados de una entidad de compilación, mostrando primero los más recientes. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Cadena de herramientas | Listas de historial |
| --- | --- | --- |
| `bazel_actions` | Acciones de Bazel | Ejecuciones de acciones reportadas por BEP |
| `gradle_tasks` | Tareas de Gradle | Ejecuciones de tareas |
| `xcode_modules` | Módulos de Xcode | Compilaciones y eventos de caché de módulos |
| `once_actions` | Acciones de Once | Ejecuciones |
| `mix_files` | Archivos compilados de Mix | Compilaciones |
| `mix_modules` | Módulos compilados de Mix | Compilaciones |
| `cargo_crates` | Crates de Cargo | Invocaciones de rustc registradas |

Estas herramientas se están implementando gradualmente y solo devuelven datos para proyectos donde están habilitadas; para otros proyectos devuelven un error en lugar de un resultado vacío. Un tipo solo está disponible para proyectos que usan su cadena de herramientas de compilación. Las herramientas aceptan filtros acotados `start_at`/`end_at`, `environment` (`any`, `ci` o `local`) y una `branch` exacta. `list_build_entities` acepta `q`; `list_build_entity_history` soporta cursores opacos `after`/`before`. Las observaciones de temporización o caché desconocidas permanecen no disponibles en lugar de convertirse en cero o fallos. El historial hace referencia al padre registrado y a la ejecución nativa para profundizar utilizando las herramientas de ejecución existentes.

Las métricas de `get_build_entity` incluyen `duration_samples`, el número de observaciones con temporización registrada: las duraciones cero genuinas cuentan, la temporización faltante no. Este recuento puede ser menor que el recuento de observaciones; las estadísticas de duración no disponibles permanecen como null.

Las duraciones de los módulos de Xcode provienen de compilaciones de objetivos medidas en los logs de compilación. Las resoluciones de caché de módulos y los objetivos sin trabajo de compilación no contribuyen a las muestras de duración. Las observaciones de compilación hacen referencia a la compilación de Xcode; los eventos de caché hacen referencia al comando de generación o caché.

Las acciones de Bazel se identifican por la etiqueta del objetivo, el mnemónico y la salida principal configurada, manteniendo distintas las acciones y configuraciones separadas sin depender de resúmenes de caché dependientes de la entrada. El historial registra ejecuciones reportadas por BEP, no búsquedas de caché ni fases de perfil de traza. La cobertura completa de ejecución requiere `--build_event_publish_all_actions`; la entrega de artefactos es de mejor esfuerzo, por lo que las observaciones faltantes no son evidencia de que no se haya realizado ningún trabajo. Las cargas útiles antiguas de Kura sin identidad estable o inicio de ejecución siguen siendo aceptadas pero no indexadas. Las mediciones de tiempo de finalización ausentes permanecen no disponibles y las duraciones cero genuinas cuentan.

Las duraciones de los módulos de Mix miden la compilación del archivo contenedor, no el trabajo del módulo medido independientemente. Las acciones de Once usan ranuras declaradas de objetivo/capacidad/índice cuando el cliente reportó los mapeos de objetivos; las etiquetas de diagnóstico por sí solas no son identidades estables. Los clientes existentes y las herramientas a nivel de ejecución siguen siendo compatibles sin cambios.

Los crates de Cargo se agrupan por raíz de crate, nombre y tipo registrados exactamente. Los cambios en la ruta de checkout pueden dividir los historiales, y los perfiles de compilación, características y triples de objetivo no se distinguen. El historial mide invocaciones de rustc, no trabajo por archivo ni aciertos de caché; los trabajos ausentes no establecen eliminaciones ni un inventario completo del espacio de trabajo.

Las lecturas de analíticas tienen memoria y tiempo de ejecución acotados. Si una consulta excede esos límites, la herramienta devuelve un error en lugar de inventar un resultado vacío.

Las nuevas observaciones se indexan después del despliegue; esta función no rellena retroactivamente la telemetría de ejecución existente. Los metadatos de identidad sobreviven a las observaciones individuales bajo la <.localized_link href="/guides/server/data-retention">política de retención de datos</.localized_link>.

#### Tests

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_test_runs` | Lista las ejecuciones de tests para un proyecto. Los campos de `query` son `git_branch`, `scheme` y `status`: `field:"value"` coincide exactamente, `field~"value"` coincide con una subcadena que no distingue entre mayúsculas y minúsculas, y un `-` inicial niega cualquiera de los operadores. Por ejemplo, `-git_branch~"gh-readonly-queue"` excluye las ramas de la cola de fusión. Los filtros de consulta separados por espacios en blanco y los argumentos explícitos se combinan con semántica AND. | `account_handle`, `project_handle` |
| `get_test_run` | Obtén métricas detalladas de una ejecución de tests, incluidas las URL de descarga temporales para su paquete de resultados (`.xcresult`) y el archivo de sesión. | `test_run_id` |
| `list_test_module_runs` | Lista las ejecuciones de módulos de test para una ejecución de tests específica. | `test_run_id` |
| `list_test_suite_runs` | Lista las ejecuciones de suites de tests para una ejecución de tests específica, con filtro opcional por módulo. | `test_run_id` |
| `list_test_cases` | Lista los casos de test de un proyecto (admite filtros como `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Obtén métricas detalladas de un caso de test, incluida la tasa de fiabilidad, la tasa de inestabilidad y los recuentos de ejecuciones. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Lista las ejecuciones de casos de test, con filtro opcional por caso de test o ejecución de tests. | `account_handle`, `project_handle` |
| `get_test_case_run` | Obtén los detalles de fallos y repeticiones de una ejecución de caso de test específica. | `test_case_run_id` |
| `list_test_case_run_attachments` | Lista los archivos adjuntos de una ejecución de caso de test. Cada adjunto incluye una URL de descarga temporal. | `test_case_run_id` |
| `list_test_case_events` | Lista los cambios de estado de un caso de test, como silenciarlo u omitirlo. | `test_case_id` |
| `update_test_case` | Actualiza el estado o la clasificación de inestabilidad de un caso de test. Un cambio puede enviar un evento a los puntos finales de webhook configurados, incluidos servicios externos. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Lista los resultados de objetivos de testing selectivo para una ejecución de tests. | `test_run_id` |
| `get_coverage` | Obtén la cobertura de código de un proyecto con sus objetivos, en un commit o en el último commit completo de una rama. Sin `git_commit_sha` ni `branch`, lee la rama predeterminada. | `account_handle`, `project_handle` |
| `list_coverage_files` | Lista los archivos medidos por la cobertura de código de un commit, con su cobertura por línea, en un commit o en el último commit completo de una rama. Admite `search`, ordenación y paginación. | `account_handle`, `project_handle` |
| `get_coverage_file` | Obtén la cobertura de código de un archivo y sus funciones en un commit o en el último commit completo de una rama. Establece `include_lines` para obtener el recuento de ejecuciones de cada línea. | `account_handle`, `project_handle`, `path` |

Las herramientas de cobertura de código están disponibles para las cuentas con la cobertura de código habilitada.

#### Bundles

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_bundles` | Lista los bundles (binarios de app) de un proyecto. Filtra opcionalmente por `git_branch` y `tags` (todas las etiquetas deben coincidir exactamente). | `account_handle`, `project_handle` |
| `get_bundle` | Obtén información detallada sobre un bundle específico, incluidas las etiquetas personalizadas. | `bundle_id` |
| `get_bundle_artifact_tree` | Obtén el árbol completo de artefactos de un bundle como una lista plana ordenada por ruta. | `bundle_id` |

`list_bundles` acepta `tags: ["paid", "production"]` para distinguir variantes de compilación o entornos. Las etiquetas son identificadores sensibles a mayúsculas y minúsculas que contienen letras, números, guiones o guiones bajos, con un máximo de 10 etiquetas y 50 caracteres por etiqueta. Los resultados de lista y detalle incluyen `custom_metadata.tags`. Los recuentos de paginación y los filtros de rama se aplican a los resultados etiquetados; omitir `tags` conserva el comportamiento sin filtrar. Los filtros de etiquetas no válidos devuelven un error en lugar de ampliar la consulta.

#### Generations

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_generations` | Lista las ejecuciones de generación para un proyecto. | `account_handle`, `project_handle` |
| `get_generation` | Obtén información detallada sobre una ejecución de generación específica. | `generation_id` |

#### Cache runs

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_cache_runs` | Lista las ejecuciones de caché para un proyecto. | `account_handle`, `project_handle` |
| `get_cache_run` | Obtén información detallada sobre una ejecución de caché específica. | `cache_run_id` |
| `list_xcode_module_cache_targets` | Lista los objetivos de caché de módulos para una ejecución de generación o caché, mostrando el estado de acierto/fallo de caché por objetivo y los hashes de componentes de diagnóstico, incluidas entradas de hash adicionales. | `run_id` |

#### Previews

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_previews` | Lista las vistas previas de app compartibles para un proyecto. | `account_handle`, `project_handle` |
| `get_preview` | Obtén una vista previa y las URLs de descarga temporales de sus builds. | `preview_id` |
| `get_latest_preview` | Encuentra la última vista previa para un binario de app en ejecución. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Automatizaciones

| Herramienta | Descripción | Parámetros requeridos |
|------|-------------|---------------------|
| `list_automation_alerts` | Lista las alertas de automatización para un proyecto. | `account_handle`, `project_handle` |
| `get_automation_alert` | Obtén una alerta de automatización. | `alert_id` |
| `list_automation_alert_revisions` | Lista el historial de revisiones de una alerta de automatización. Las credenciales de acción están ocultas. | `alert_id` |
| `list_project_notification_alerts` | Lista las reglas de alertas de notificación del proyecto. Requiere el mismo permiso de administrador que la página de configuración del dashboard. Las direcciones de webhook están ocultas. | `account_handle`, `project_handle` |

### Eventos

Los clientes que usan el ciclo de vida sin estado del `2026-07-28` Model Context Protocol pueden llamar a `events/list` para descubrir eventos y sus esquemas de carga útil:

| Evento | Cuándo se envía | Filtro de suscripción |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Un caso de test cambia de no inestable a inestable. | `account_handle`, `project_handle` |
| `build.failed` | Una compilación local o de integración continua de Xcode, Gradle o Bazel termina con un fallo. | `account_handle`, `project_handle` |
| `test_run.failed` | Una ejecución de tests local o de integración continua termina con un fallo, incluida una ejecución fragmentada fusionada o una ejecución abandonada. | `account_handle`, `project_handle` |
| `ci_job.failed` | Un trabajo de runner de Tuist termina con un fallo. | `account_handle` |

Para suscribirse, el cliente llama a `events/subscribe` con el nombre del evento, los identificadores listados arriba en `arguments` y una entrega `webhook` que contiene una URL de callback `https://` y un secreto de firma `whsec_`. Los eventos de proyecto requieren membresía en la cuenta y acceso de lectura a los datos de tests o compilaciones correspondientes; los eventos de trabajos de runner requieren membresía en la cuenta y acceso de lectura al runner. Los tokens de acceso reclamados [`auth.md`](https://workos.com/auth-md), los tokens de cuenta reclamados y las autorizaciones del navegador pueden crear suscripciones; la entrega se detiene cuando la credencial asociada ya no está activa. Cada usuario puede mantener hasta 25 suscripciones activas. Tuist envía un desafío de verificación al callback antes de guardar la suscripción. El callback debe devolver un objeto que contenga el mismo valor de `challenge`. La suscripción dura siete días por defecto, puede actualizarse volviendo a suscribirse y deja de entregar cuando se elimina el acceso o la credencial del usuario. El opcional `ttlMs` tiene un límite entre una hora y 30 días. Tuist reintenta un callback con tiempo agotado y lo cancela después de al menos tres tiempos de espera consecutivos que abarcan cinco minutos; vuelve a suscribirte después de restaurar el callback.

Cuando ocurre un evento, Tuist envía su identificador de recurso y la URL del dashboard al callback. Los fallos de compilación y de ejecución de tests también incluyen `is_ci` y `git_branch`, por lo que los clientes pueden ignorar los fallos locales o filtrar por rama. Los eventos de compilación incluyen `build_system`; los eventos de trabajos de runner incluyen tanto `workflow_job_id` como `workflow_run_id`. La solicitud incluye un identificador de suscripción y encabezados de firma de [Standard Webhooks](https://www.standardwebhooks.com/) para que el cliente pueda verificar su origen. Tuist reintenta las entregas fallidas, por lo que los clientes deben usar el `eventId` estable para descartar duplicados. La carga útil omite los nombres de los tests, los registros y los mensajes de error; el cliente puede obtener esos detalles a través de las herramientas anteriores y decidir si notifica a un equipo o inicia la depuración. Los clientes pueden detener la entrega con `events/unsubscribe`.

### Prompts

| Prompt | Descripción |
|--------|-------------|
| `fix_flaky_test` | Te guía para corregir un test inestable analizando patrones de fallo, identificando la causa raíz y aplicando una corrección específica. |
| `compare_builds` | Te guía para comparar compilaciones e identificar regresiones de rendimiento, cambios en la caché y problemas de compilación. Usa herramientas nativas para proyectos de Xcode, Gradle, Bazel y Cargo. Las comparaciones de Cargo conservan la cobertura parcial del compilador y distinguen el trabajo estimado del compilador del ahorro de tiempo transcurrido. |
| `compare_test_runs` | Te guía para comparar dos ejecuciones de tests e identificar regresiones, nuevos fallos y tests inestables. |
| `compare_bundles` | Te guía para comparar dos bundles e identificar cambios de tamaño en todo el árbol de artefactos. |
| `compare_test_case` | Te guía para comparar el comportamiento de un caso de test entre dos ramas o períodos de tiempo. |
| `compare_generations` | Te guía para comparar dos ejecuciones de generación e identificar regresiones de rendimiento y cambios en la caché de módulos. |
| `compare_cache_runs` | Te guía para comparar dos ejecuciones de caché e identificar cambios en la eficacia de la caché y regresiones a nivel de objetivo. |
| `integrate_gradle_project` | Te guía para integrar Tuist en un proyecto Gradle existente. Incluye autenticación separada de la herramienta y de Gradle, descubrimiento de cuenta, creación de proyecto, política de caché remota, análisis de compilaciones y verificación de lectura. |
| `integrate_bazel_project` | Te guía para crear o seleccionar un proyecto Bazel, autenticar la línea de comandos, configurar la caché remota y los análisis de compilaciones, y verificar la integración a través de los datos de compilación de Tuist. |
| `integrate_xcode_project` | Te guía para integrar Tuist en un proyecto Xcode existente. Admite caché de Xcode, análisis de compilaciones, análisis de tests y fragmentación de tests. |
| `ask_tuist` | Responde a una pregunta sobre Tuist usando material público como contexto y evidencia focalizada de implementación y tests como fuente de verdad para el comportamiento actual. Requiere una `question` y cita evidencia anclada a una revisión. |

Los prompts de datos de proyecto aceptan `account_handle` y `project_handle` para limitar la investigación a un proyecto específico. Los prompts de comparación también aceptan los argumentos `base` y `head` para especificar los dos elementos a comparar (por ID, URL del dashboard o nombre de rama). `ask_tuist` acepta una `question` en lugar de parámetros de proyecto. `integrate_gradle_project` también acepta `features`, una lista separada por comas de integraciones de Gradle para aplicar: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` y `test_sharding`. `integrate_bazel_project` acepta un `server_url` opcional para instalaciones autoalojadas o locales. `integrate_xcode_project` acepta `features` con `xcode_cache`, `build_insights`, `test_insights` y `test_sharding`.

#### Funcionalidades del prompt de integración de Gradle

El prompt `integrate_gradle_project` y la herramienta `get_gradle_integration_guide` documentan el flujo de trabajo completo de configuración. La herramienta también es referenciada por las instrucciones de inicialización del servidor, lo que permite que sea descubierta por agentes que no enumeran prompts.

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `remote_cache` | Habilita la caché de compilación de Gradle, configura la política de subida a la caché remota de Tuist y recomienda subir solo desde runners de integración continua con uso local de solo lectura. |
| `build_insights` | Aplica el plugin de Gradle de Tuist y configura el comportamiento de subida de análisis de compilaciones cuando sea necesario. |
| `test_insights` | Aplica el plugin de Gradle de Tuist para que los resultados de la tarea `Test` de Gradle se suban automáticamente. |
| `flaky_tests` | Guía la configuración para la detección de tests inestables, el uso opcional del plugin Gradle Test Retry y la configuración de cuarentena de tests. |
| `test_sharding` | Añade el flujo de trabajo de integración continua para `tuistPrepareTestShards`, la generación de la matriz de shards y la ejecución de tests basada en `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones quiere el usuario o que infiera el conjunto útil más pequeño a partir de la solicitud antes de editar el proyecto Gradle.

#### Funcionalidades del prompt de integración de Xcode

El prompt `integrate_xcode_project` documenta todas las integraciones de Xcode que admite Tuist:

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `xcode_cache` | Configura `tuist setup cache`, los ajustes de caché de proyectos generados, los ajustes manuales de compilación de la caché de Xcode y una política de subida limitada a runners de integración continua. |
| `build_insights` | Configura `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` y métricas opcionales de la máquina a través de `tuist setup insights`. |
| `test_insights` | Configura `tuist inspect test`, las post-acciones de test del esquema y la generación de bundles de resultados para ejecuciones de tests de integración continua. |
| `test_sharding` | Añade la planificación de shards para Xcode o proyectos generados y el flujo de trabajo de ejecución de shards con `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones quiere el usuario o que infiera el conjunto útil más pequeño a partir de la solicitud antes de editar el proyecto Xcode.
