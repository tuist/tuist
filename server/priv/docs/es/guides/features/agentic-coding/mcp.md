---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Programación con agentes · Funcionalidades · Guías · Tuist",
  "description": "Proporciona a los agentes de IA acceso al análisis de tests y más a través del endpoint MCP de Tuist."
}
---
# Model Context Protocol

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/docs/getting-started/intro) es un estándar abierto que permite a los agentes de inteligencia artificial interactuar con servicios externos y fuentes de datos. Hace que aplicaciones como [Claude](https://claude.ai/), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://developers.openai.com/codex/) y editores como [Zed](https://zed.dev), [Cursor](https://www.cursor.com) o [Visual Studio Code](https://code.visualstudio.com) sean interoperables con Tuist.

Tuist aloja un punto de conexión de Model Context Protocol en el servidor en `https://tuist.dev/mcp`. Al conectar tu cliente a él, los agentes pueden acceder a los datos de tu proyecto de Tuist, incluidos análisis de tests, análisis de tests inestables y más. La mayoría de las herramientas leen datos de Tuist que el usuario autenticado ya puede ver en el panel. Cada herramienta anuncia anotaciones que indican si es de solo lectura, si puede provocar un cambio difícil de revertir (`destructiveHint`) y si puede acceder a recursos fuera de Tuist (`openWorldHint`). Las herramientas que modifican el estado, cada una limitada por los permisos del usuario en la cuenta o el proyecto, son:

- **Organizaciones y miembros**: `create_organization`, `add_organization_member` (añade un usuario existente o cambia el rol de un miembro), `invite_organization_member` (envía una invitación por correo a cualquier dirección) y `cancel_organization_invitation`.
- **Proyectos**: `create_project`, `start_project_logo_upload` y `complete_project_logo_upload` (reemplaza el logotipo), `connect_project_repository` y `disconnect_project_repository` (enlaces a repositorios de GitHub).
- **Tests**: `update_test_case` (silencia, omite, vuelve a habilitar o marca un caso de test como inestable; el cambio puede llegar a los puntos de conexión webhook de la cuenta).
- **Reglas de notificación**: `create_notification_rule`, `update_notification_rule` y `delete_notification_rule`.
- **Ejecutores de integración continua**: `create_runner_profile`, `update_runner_profile` (al restringir qué trabajos guardan volúmenes de caché se descartan los guardados pendientes), `delete_runner_profile` y `delete_runner_volume` (elimina el contenido guardado del volumen).
- **Entornos aislados**: `create_sandbox`, `pause_sandbox`, `resume_sandbox`, `extend_sandbox`, `archive_sandbox`, `delete_sandbox` (elimina sus discos) y, en los dispositivos de un entorno aislado (hoy los simuladores de iOS de un entorno aislado de macOS), `boot_sandbox_device`, `launch_sandbox_app` y `open_sandbox_url`.
- **Comentarios**: `report_feedback` (envía un informe sobre una herramienta o indicación al equipo de Tuist; solo en tuist.dev).
- **IA de la organización**: `save_organization_ai_model`, `remove_organization_ai_model`, `set_organization_ai_default_model`, `save_organization_ai_task_route`, `remove_organization_ai_task_route` y `remove_organization_ai_provider` (elimina la clave y los modelos del proveedor y desvincula una organización de Claude vinculada en Anthropic).
- **Integraciones de agentes**: `connect_amp_workspace` (otorga a los orbs del espacio de trabajo acceso de CI a la cuenta), `disconnect_amp_workspace` y `connect_claude_environment` (permite que un entorno de Claude Managed Agents ejecute sesiones en entornos aislados de Tuist).

`add_organization_member`, `cancel_organization_invitation`, `complete_project_logo_upload`, `disconnect_project_repository`, `update_test_case`, `update_notification_rule`, `delete_notification_rule`, `update_runner_profile`, `delete_runner_profile`, `delete_runner_volume`, `delete_sandbox`, `disconnect_amp_workspace`, `remove_organization_ai_provider`, `remove_organization_ai_model` y `remove_organization_ai_task_route` anuncian `destructiveHint: true` porque reemplazan o eliminan el estado existente. `invite_organization_member`, `update_test_case`, `connect_claude_environment`, `remove_organization_ai_provider` y `report_feedback` anuncian `openWorldHint: true` porque envían correos electrónicos, notifican puntos de conexión webhook externos, llaman a Anthropic o envían un informe al equipo de Tuist.

Las suscripciones personales de Claude y ChatGPT se conectan solo en la configuración de IA del panel, por lo que los tokens de suscripción y los inicios de sesión nunca pasan por un cliente de Model Context Protocol. Las herramientas de configuración de la cuenta requieren autenticación de usuario. No están disponibles para tokens de proyecto ni para tokens de cuenta ordinarios. Cuando un usuario autoriza un cliente en el navegador o reclama un registro de `auth.md`, Tuist asocia esa credencial con el usuario solo en el punto de conexión de Model Context Protocol, de modo que las herramientas de configuración puedan completar el flujo solicitado. Dado que cualquiera puede registrar un cliente, al autorizar uno en el navegador se muestra una página de consentimiento que nombra al cliente y al host al que se envía su acceso, y Tuist emite la credencial solo después de que la apruebes allí. Un cliente que no solicita ningún ámbito recibe el grupo de ámbitos `mcp`. Los clientes deben usar PKCE con `S256` y sus URI de redirección deben usar HTTPS, HTTP en una dirección de bucle invertido o el esquema propio de la aplicación.

Tuist implementa el [protocolo 2026-07-28](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http). Las solicitudes son sin estado: los clientes envían sus metadatos de protocolo con cada solicitud y pueden llamar a las herramientas directamente sin inicialización. `server/discover` devuelve la identidad, las capacidades, las versiones admitidas y las instrucciones del servidor. No hay identificadores de sesión ni flujos de eventos independientes. Los clientes que usan el flujo de inicialización 2025-06-18 o 2025-03-26 siguen siendo compatibles; también operan sin sesiones del servidor.

## Model Context Protocol frente a habilidades

Las herramientas de Model Context Protocol y las <.localized_link href="/guides/features/agentic-coding/skills">habilidades</.localized_link> pueden solaparse en lo que hacen. Dado el solapamiento actual entre ambas, elige un enfoque por flujo de trabajo y úsalo de forma consistente en lugar de mezclar ambos en el mismo flujo.

Para los clientes que admiten la instalación de complementos, usa los <.localized_link href="/guides/features/agentic-coding/plugins">complementos de Tuist</.localized_link> para instalar ambos juntos.

## Configuración

Añade `https://tuist.dev/mcp` como un servidor remoto de Model Context Protocol en tu cliente. Las instrucciones de inicialización del servidor y la tarjeta pública del servidor describen OAuth 2.0 con registro dinámico de clientes y el flujo estándar de autorización en el navegador de forma integrada, sin pedir a los agentes que obtengan o sigan documentos de autenticación externos. Estas instrucciones generales del servidor mantienen la guía del flujo de trabajo genérica: la autenticación de herramientas no autentica herramientas locales de línea de comandos ni integraciones del sistema de compilación, y los agentes deben verificar los cambios solicitados a través de las herramientas relevantes de Tuist. La configuración específica del sistema de compilación y las comprobaciones de autenticación están documentadas en las guías de integración y las indicaciones. Tuist sigue anunciando por separado tanto los metadatos de descubrimiento de [Open Authorization](https://oauth.net/2/) como el actual [protocolo auth.md](https://workos.com/auth-md) en `https://tuist.dev/auth.md`.

Si una de tus organizaciones exige inicio de sesión único, autorizar un cliente en el navegador requiere una sesión iniciada a través de esa organización y Tuist te redirige primero al proveedor cuando sea necesario. Consulta <.localized_link href="/guides/integrations/authentication/sso#choose-an-enrollment-policy">inicio de sesión único</.localized_link>.

El punto de conexión acepta el ciclo de vida de solicitudes de Model Context Protocol sin estado `2026-07-28`, incluido `server/discover`, junto con el ciclo de vida basado en sesiones anterior. Los clientes existentes pueden seguir usando su método de conexión actual.

Los clientes que admiten eventos de Model Context Protocol pueden suscribirse a eventos del proyecto. Consulta [Eventos](#events) para conocer los requisitos de eventos disponibles y de entrega.

Los clientes que ya admiten la autenticación remota en el navegador pueden seguir autenticándose en el navegador. Los clientes y agentes que admiten `auth.md` pueden registrarse de forma anónima, presentar una aserción de identidad de proveedor de confianza o iniciar una reclamación de correo electrónico autenticada por el servicio. El registro devuelve una aserción de identidad firmada por Tuist, que el agente intercambia en el punto de conexión estándar de tokens por un token de acceso de una hora de duración. Tuist publica su clave pública de firma y admite la revocación estándar de tokens y la entrega de eventos de seguridad del proveedor.

Un agente no autenticado debe leer la cabecera `WWW-Authenticate` devuelta por el punto de conexión de Model Context Protocol, obtener los metadatos del recurso protegido, obtener los metadatos del servidor de autorización y seguir su URL `agent_auth.skill`. Tuist también devuelve la misma URL local `auth_md` en el cuerpo de la respuesta no autorizada para que los clientes impulsados por modelos de lenguaje puedan descubrir el flujo sin depender de una integración nativa del cliente. El documento local al despliegue es la fuente de verdad para los nombres de los puntos de conexión, los cuerpos de las solicitudes, el sondeo de reclamaciones y el intercambio de aserciones.

Antes de que un agente inicie una reclamación de correo electrónico, debe pedir al usuario que confirme la dirección de correo electrónico de su cuenta de Tuist. No debe inferir esa dirección a partir de un perfil de proveedor, la configuración de Git, una variable de entorno o los metadatos de la sesión.

El punto de conexión utiliza el grupo de ámbitos `mcp`. Una credencial anónima previa a la reclamación puede descubrir capacidades y leer la guía de integración pública, pero no se trata como un usuario con sesión iniciada. Tras la autorización en el navegador o la reclamación, la credencial tiene ámbito de usuario y cada herramienta aplica las mismas comprobaciones de autorización que el panel. Consulta la <.localized_link href="/guides/server/authentication#scope-groups">documentación sobre grupos de ámbitos</.localized_link> para más detalles.

Las herramientas se resuelven a los proyectos que el usuario autenticado ya puede leer. Las herramientas de compilación de Xcode y Gradle aceptan un UUID de compilación o una URL del panel. El UUID debe identificar exactamente un proyecto; si aparece en varios proyectos, la herramienta devuelve "no encontrado" en lugar de seleccionar el informe de otro proyecto. Las lecturas del panel y de la API con ámbito de proyecto siguen estando disponibles. Los identificadores de actor reportados son etiquetas no verificadas, no credenciales ni derechos de acceso adicionales.

Las herramientas de lista y detalle de compilaciones exponen metadatos opcionales de `tuist_version`: la CLI de Tuist que informa para Xcode y Cargo, el complemento de Tuist Gradle para Gradle y la biblioteca `tuist_ex` para Mix. Xcode también expone `tuist_generation_version` a partir de su evento vinculado de generación de proyecto, que puede diferir de la CLI que realiza la carga. Las observaciones faltantes son nulas, no inferidas del servidor o de otro informe. Bazel utiliza su `bazel_version` existente; los detalles de ejecución de Struo exponen `once_version`. Estos campos describen versiones reportadas, no identidades verificadas ni versiones de contrato de cable. Los puntos de conexión REST de compilación exponen los mismos metadatos. Las habilidades de integración existentes y de tests intermitentes no dependen de los campos de versión y no requieren cambios en el flujo de trabajo.

Los operadores de Tuist que investigan la cuenta de un cliente lo hacen a través de las herramientas operativas internas de Tuist, que registran cada llamada; una conexión directa a este punto de conexión no obtiene acceso más allá de las propias membresías del usuario.

### Pulse

Pulse expone herramientas de solo lectura para las métricas operativas, registros, trazas y errores de la cuenta, todas dirigidas por `account_handle`. Las tres primeras reflejan las páginas de Pulse y su API REST; las otras cinco permiten a un agente explorar la telemetría directamente y no tienen equivalente REST:

| Herramienta | Propósito | Equivalente REST bajo `/api/accounts/:account_handle/pulse` |
| --- | --- | --- |
| `query_pulse` | Tablas de la página de Pulse | `GET /:signal` |
| `get_pulse_analytics` | Widgets de la página de Pulse | `GET /:signal/analytics` |
| `get_pulse_error_issue` | Un problema de error y sus eventos | `GET /errors/issues/:fingerprint` |
| `query_pulse_metrics` | PromQL instantáneo o de rango | Ninguno |
| `list_pulse_labels` | Nombres de etiquetas o valores de una etiqueta | Ninguno |
| `search_pulse_logs` | Entradas de registro filtradas | Ninguno |
| `search_pulse_traces` | Segmentos filtrados | Ninguno |
| `get_pulse_trace` | Cada segmento de una traza | Ninguno |

Pulse está restringido a los miembros actuales de la organización configurada en el servidor, incluso cuando una cuenta o proyecto es público. Requiere autenticación de usuario o una credencial `mcp` asociada a un usuario y autorización de lectura de la cuenta. Los tokens de proyecto, los tokens de cuenta ordinarios, los registros anónimos y el acceso de operador sin membresía en la organización no conceden acceso a Pulse. Las credenciales no pueden seleccionar otro backend o inquilino de telemetría, y solo la cuenta configurada en el servidor tiene telemetría de Pulse, por lo que ninguna herramienta puede leer los datos de otra cuenta. Los agentes del navegador reciben estas herramientas solo en las páginas de Pulse, dentro del ámbito de cuenta de esa página.

REST requiere una credencial de usuario. Las asociaciones de usuario de OAuth y `auth.md` están disponibles solo en el punto de conexión `/mcp`; se deniega una credencial de cuenta sin un usuario actual, independientemente de la membresía o visibilidad de la cuenta asociada.

`query_pulse` toma `signal` (`metrics`, `logs`, `traces` o `errors`), un `query` opcional y `range` (`15m`, `1h`, `6h` o `24h`, por defecto `1h`). Las métricas aceptan expresiones PromQL. Los registros, trazas y errores aceptan texto literal, sin distinción entre mayúsculas y minúsculas, que se compara con los cuerpos de los registros, los nombres de los segmentos y los títulos de los problemas de error; `*`, el valor por defecto, selecciona todo. Las filas de trazas son segmentos individuales. Las filas de errores son problemas: eventos agrupados por servicio y huella digital, con su recuento de eventos, cuentas afectadas, primera y última aparición en la ventana, y el título, responsable, nivel y plataforma de su último evento. Las tablas aceptan `search`, `page` (por defecto `1`), `page_size` (`1`–`100`, por defecto `20`), `sort_by` y `sort_order` (`asc` o `desc`). Las columnas de ordenación dependen de la señal y se enumeran en el esquema de la herramienta. Los filtros incluyen `service` y `level` para registros y errores. Los operadores de filtro utilizan el argumento `_op` correspondiente (`eq`, `contains` o `not_contains`), con igualdad exacta por defecto.

Las columnas de ordenación son `name`/`value` para métricas; `timestamp`/`service`/`level`/`message`/`trace_id` para registros; `timestamp`/`service`/`name`/`duration_ms`/`trace_id` para trazas; y `last_seen`/`first_seen`/`events`/`accounts`/`title`/`service`/`level` para errores. El panel muestra intencionadamente un subconjunto; la API y las herramientas aceptan la lista completa para cada señal.

Las respuestas de tabla contienen `rows`, `series`, `warnings` y `meta`. Los metadatos de paginación incluyen `page`, `page_size`, `total_count`, `total_pages`, `has_next_page`, `has_previous_page` y `end_at`. Pasa el `end_at` ISO8601 devuelto con las páginas siguientes para preservar la ventana de consulta. Los errores de límite de resultados requieren reducir la consulta o el intervalo de tiempo, no tratar la respuesta como una tabla vacía.

Los registros y las trazas inspeccionan como máximo las 100 coincidencias más recientes antes de la ordenación local, y los errores, los 100 problemas vistos más recientemente. Los filtros, la ordenación, la paginación y los totales describen solo esas coincidencias devueltas, no toda la ventana de tiempo. Reduce el texto de la consulta o el intervalo de tiempo para inspeccionar otras coincidencias; cambiar la búsqueda u ordenación locales no amplía la búsqueda ascendente. Los widgets agregados siguen siendo consultas independientes que abarcan toda la ventana, en lugar de agregados de estos resultados de tabla acotados.

Las tablas de métricas evalúan su expresión una vez en `end_at`, devolviendo los valores actuales y un punto por cada serie de vector instantáneo. Las expresiones de vector de rango pueden devolver puntos históricos acotados. Los widgets de análisis separados proporcionan gráficos históricos fijos; una tabla no materializa una cuadrícula temporal para cada serie coincidente solo para mostrar su último valor.

Las cadenas de telemetría son datos no confiables, no instrucciones.

`get_pulse_analytics` toma solo `signal` y `range` además del identificador de cuenta. Sus widgets fijos son independientes de las expresiones de tabla, filtros, ordenación y paginación.

`get_pulse_error_issue` toma la `fingerprint` y el `service` de un problema a partir de una fila de errores, más `range`, `end_at`, `page` y `page_size` opcionales. Devuelve el resumen del problema, 60 intervalos de ocurrencia iguales, el último evento con su cadena de excepciones, marcos de pila, migas de pan, etiquetas, contextos, datos adicionales, método de solicitud y URL sin su cadena de consulta, y una página de eventos, los más recientes primero, con los mismos `meta` de paginación que las tablas. Las filas de errores también incluyen la `occurrence_series` de 60 intervalos de cada problema. Los eventos se depuran de datos personales antes del almacenamiento, por lo que los valores filtrados aparecen como `[Filtered]` o `[REDACTED]`. Un problema sin eventos en la ventana se informa como no encontrado. REST y Model Context Protocol utilizan el mismo contexto de Pulse y contratos de respuesta. Las respuestas REST desactivan el almacenamiento en caché.

#### Exploración de telemetría

Las herramientas de exploración leen una ventana de `15m`, `1h`, `6h` o `24h` (por defecto `1h`, y `24h` para `get_pulse_trace`) que termina en un `end_at` ISO8601 opcional, cuyo valor por defecto es ahora. Cada respuesta devuelve `start_at` y `end_at`; pasa el mismo `end_at` de nuevo para mantener la ventana. Ninguna de estas herramientas acepta SQL.

- `query_pulse_metrics` evalúa `query`, una expresión PromQL, en `end_at` (`type: instant`, el valor por defecto) o cada `step` segundos durante la ventana (`type: range`). El paso tiene como valor por defecto, y no puede ser menor que, la ventana dividida por 360, por lo que una serie tiene como máximo 361 puntos. Los resultados tienen como máximo 5.000 series. Los puntos son `[unix_seconds, value]`, y los valores `NaN` e infinitos son cadenas. Las consultas instantáneas rechazan `range` y `step`.
- `list_pulse_labels` toma un `signal`. Sin `label`, enumera los nombres de las etiquetas; con `label`, enumera los valores de esa etiqueta. Para las métricas, `__name__` enumera los nombres de las métricas, y los valores de cualquier otra etiqueta requieren `match`, un selector de series como `up`. Los valores de las etiquetas de registros y trazas aceptan `filters`; los nombres de las etiquetas de traza provienen del esquema de traza y no lo hacen. Los valores de registros y trazas incluyen su recuento de entradas en la ventana, los más frecuentes primero, por lo que también sirven como desgloses, como errores por servicio. `search` mantiene solo los nombres o valores que contienen un texto literal, y `limit` acepta `1`–`1000` (por defecto `100`). La detección de nombres de etiquetas de registro inspecciona como máximo 1.000 conjuntos de atributos distintos de cada tipo y lista solo las claves que los filtros aceptan.
- `search_pulse_logs` devuelve hasta `limit` entradas (`1`–`100`, por defecto `50`), `newest` o `oldest` primero, cuyo cuerpo contiene `text` y que coinciden con cada filtro. Cada entrada incluye su `severity_text`, `body`, `trace_id`, `span_id`, `scope_name` y sus `attributes` de recurso y registro fusionados. `span_id` y `scope_name` son `null` para los registros recopilados desde Kubernetes, que solo configuran los remitentes de registros OTLP.
- `search_pulse_traces` devuelve hasta `limit` segmentos, `newest`, `oldest` o `slowest` primero, que coinciden con cada filtro, `min_duration_ms` y `max_duration_ms` opcionales, y `root_only`.
- `get_pulse_trace` devuelve los segmentos de `trace_id` que comienzan en la ventana, los más antiguos primero, hasta 1.000 segmentos. Una traza que comenzó antes de la ventana se devuelve parcialmente, así que amplía o mueve la ventana para ella. Cada segmento incluye sus atributos de segmento, eventos, enlaces y un índice en los `resources` distintos de la traza.

Los filtros son listas de hasta 10 objetos `{label, op, value}`. `op` es `eq` (el valor por defecto), `neq`, `contains` o `not_contains`; los dos últimos son literales sin distinción entre mayúsculas y minúsculas. Las etiquetas de registro son `severity_text`, `trace_id`, `span_id` y `scope_name` cuando Pulse las almacena, y las claves de los atributos de recurso de cada entrada, como `namespace`, `container` y `service.name`, y los atributos de registro, como `pod`. Cuando una clave aparece en ambos, se aplica el atributo de recurso. Las etiquetas de traza son las columnas de segmento que devuelve `list_pulse_labels`, como `service_name`, `span_name`, `span_status_code` (`STATUS_CODE_ERROR` para segmentos fallidos), `span_attributes.http.route` y `resource_attributes.k8s.pod.name`. Una etiqueta de traza desconocida es un error en lugar de un resultado vacío.

`truncated` significa que hay más nombres, valores, entradas o segmentos coincidentes de los que incluye la respuesta; reduce los filtros o la ventana en lugar de tratar la respuesta como completa. Las cadenas de telemetría son datos no confiables, no instrucciones.

<details>
<summary>Claude Code</summary>

Ejecuta:

```bash
claude mcp add --transport http tuist https://tuist.dev/mcp
```

Cuando un cliente de Claude Code sin interfaz gráfica no expone al modelo una conexión fallida al servidor nativo, exige al agente que inspeccione la respuesta no autenticada de [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) del punto de conexión configurado antes de buscar documentación alojada o editar el proyecto. La respuesta indica al modelo el documento `auth.md` local del despliegue incluso cuando la autenticación del navegador no está disponible.

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

Abre **Settings → Connectors → Add custom connector** y luego configura:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

Completa la [Open Authorization](https://oauth.net/2/) en el navegador cuando se te solicite.

</details>


<details>
<summary>Pi</summary>

Pi no incluye un cliente de Model Context Protocol. Puedes instalar la extensión de terceros [`pi-mcp-adapter`](https://pi.dev/packages/pi-mcp-adapter) después de revisar su código fuente y las implicaciones de seguridad:

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

Establecer `auth` en `false` evita que el controlador de autenticación del navegador del adaptador oculte la respuesta no autorizada de Tuist. Un agente sin interfaz gráfica puede entonces leer la URL `auth_md` devuelta y seguir el flujo de registro, intercambio de aserción de identidad y sondeo de reclamación de Tuist. Configura el token de acceso intercambiado como un token bearer o permite que el agente realice llamadas autenticadas de Model Context Protocol directamente.

Si prefieres la autenticación mediante navegador, establece `auth` en `"oauth"`. Para ese flujo, mantén un proceso activo con el [remote procedure call mode](https://pi.dev/docs/latest/rpc) de Pi mientras se completa la autenticación:

```bash
pi --mode rpc
```

No dividas una autenticación pendiente en el navegador entre invocaciones separadas de `pi --print` porque el proceso que posee el estado de la devolución de llamada ya ha finalizado.

</details>


<details>
<summary>OpenCode</summary>

Añade el servidor de Tuist Model Context Protocol a `opencode.json`:

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

Usa **Command Palette → MCP: Add Server** y luego configura un servidor de [Hypertext Transfer Protocol](https://developer.mozilla.org/en-US/docs/Web/HTTP) con:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>


<details>
<summary>Zed</summary>

Abre **Agent panel → Settings → Add Custom Server** y luego configura:

- **Name:** `tuist`
- **URL:** `https://tuist.dev/mcp`

</details>

Si tu agente admite `auth.md`, puede iniciar sesión de forma anónima sin abrir un navegador. Una identidad de proveedor de confianza también puede completarse sin un navegador cuando la identidad del proveedor ya está vinculada. Para el correo electrónico autenticado por servicio, la reclamación anónima o el primer enlace de proveedor, el agente te muestra un enlace de verificación de Tuist y un código de seis dígitos. Abre el enlace, inicia sesión e introduce el código del agente en la página de Tuist. Nunca envíes el código de vuelta al agente. Los metadatos del servidor de autorización de Tuist apuntan directamente al `/auth.md` propio del despliegue, que contiene las formas exactas de solicitud y sondeo.

## Agentes en orbs de Amp y sesiones en la nube de Claude Code

Los agentes de programación que se ejecutan en entornos aislados conectados a una cuenta de Tuist pueden autenticarse en el punto de conexión con su propio token de identidad, sin necesidad de un navegador ni de credenciales de Tuist almacenadas:

- Los **Amp orbs** de un espacio de trabajo o proyecto de Amp, al que la cuenta se conectó bajo **Settings → Integrations → Amp**, envían el token de ID del orb. En Amp, establece la cabecera `Authorization` del servidor a `Bearer ${amp:id-token}`. Amp emite el token para el origen de la URL del servidor, por lo que la URL debe ser la dirección propia de esta instancia de Tuist, y lo actualiza antes de que caduque. Los tokens emitidos para otro origen son rechazados.
- Las **Claude Code cloud sessions** de un entorno de Claude Code conectado envían el token de sesión que Tuist les pasa como `TUIST_OIDC_TOKEN`. Establece la cabecera a `Bearer ${TUIST_OIDC_TOKEN}`.

Los entornos aislados de Linux de Tuist no añaden el servidor por ti: incluyen la CLI de Tuist, que inicia sesión con la misma identidad, y una habilidad que indica al agente cuándo comprobar sus resultados frente al historial del proyecto. Para dar a los agentes también las herramientas de MCP, añade el servidor a tu configuración de Amp o Claude Code, o al `.mcp.json` del proyecto, con la cabecera anterior.

Estos tokens otorgan acceso de solo lectura a todos los proyectos de la cuenta conectada: llevan los ámbitos de lectura del grupo `mcp` y ninguno que cree, cambie o elimine datos, como silenciar u omitir tests. Desconectar el espacio de trabajo o el entorno detiene el acceso en la siguiente solicitud, y el acceso nunca sobrevive al propio token. Se rechaza un espacio de trabajo de Amp conectado a varias cuentas de Tuist, porque su token no nombra a ninguna. Cuando falta una conexión, el `error_description` de la respuesta no autorizada lo indica.

Este acceso de solo lectura se aplica únicamente al punto de conexión de Model Context Protocol. La herramienta de línea de comandos y las integraciones del sistema de compilación en el mismo entorno aislado siguen intercambiando el token por el acceso de CI de la conexión.

## WebMCP

En los navegadores que admiten [WebMCP](https://webmachinelearning.github.io/webmcp), las páginas de Tuist registran herramientas con `document.modelContext`, por lo que los agentes integrados en el navegador pueden llamarlas sin ninguna configuración adicional. Las llamadas se ejecutan en el servidor de Tuist.

- Las **páginas web y de documentación** registran las herramientas de documentación y de código fuente (`search_tuist`, `search_tuist_code`, `list_tuist_files` y `read_tuist_file`). No necesitas iniciar sesión.
- Las **páginas del panel de control de una cuenta**, cuando has iniciado sesión, registran las herramientas de solo lectura de Tuist para esa cuenta. Cada página registra solo las herramientas para lo que muestra, para el sistema de compilación del proyecto: la página de compilaciones de un proyecto de Gradle obtiene las herramientas de compilación de Gradle, sus páginas de tests obtienen las herramientas de tests y cobertura, las páginas de runners obtienen las herramientas de runner y las páginas de entornos aislados obtienen las herramientas de entorno aislado. Cada página también obtiene las herramientas de documentación, `list_projects` y `get_project`. Las herramientas se ejecutan como el usuario que ha iniciado sesión, por lo que solo acceden a los datos que puedes leer en el panel de control y solo a la cuenta que estás consultando. Cuando te desplazas a otra página o cuenta, las herramientas se sustituyen por las de esa página.

Las herramientas que crean, cambian o eliminan datos no están disponibles a través de WebMCP, porque un agente del navegador recibe las herramientas sin que tú las añadas y lee el contenido que producen las compilaciones y los tests. Conecta un cliente de MCP al punto de conexión `/mcp` para usar esas herramientas.

Si la organización exige el inicio de sesión único, inicia sesión en el panel de control con su proveedor para usar sus herramientas.

## Las integraciones del sistema de compilación usan dos credenciales

La credencial utilizada para las herramientas de Model Context Protocol no autentica el plugin de Gradle ni los servicios remotos de Bazel. Antes de que un agente edite o verifique una integración de Gradle o Bazel, debe ejecutar:

```bash
tuist auth whoami --url https://tuist.dev
```

Si ese comando no está autenticado, el agente debe detenerse y pedir al usuario que ejecute:

```bash
tuist auth login --url https://tuist.dev
```

Para un despliegue local o autoalojado, reemplaza la URL en ambos comandos y en `tuist.toml`. Mantén la ortografía del nombre de host idéntica en todas partes. Por ejemplo, `localhost` y `127.0.0.1` utilizan credenciales almacenadas separadas.


## Capacidades

### Herramientas

Las siguientes herramientas están disponibles a través del servidor de Tuist Model Context Protocol:

Cada herramienta publica una descripción legible junto con esquemas de entrada y salida explícitos. Las llamadas exitosas devuelven contenido estructurado que se ajusta al esquema de salida anunciado, además del mismo resultado serializado como texto para clientes que aún no consumen contenido estructurado.

Las herramientas que toman el identificador de un único registro, como `build_run_id`, `test_run_id`, `test_case_id`, `bundle_id`, `run_id`, `generation_id` o `cache_run_id`, también aceptan la URL del panel de control de Tuist de ese registro. Pega la URL directamente desde el navegador en lugar de extraer el identificador de ella.

`get_xcode_build`, `get_test_run`, `get_gradle_build` y `get_project` pueden incluir `side_quests`: capacidades de Tuist que el proyecto no está usando pero que el registro muestra que serían útiles. Cada una tiene un `id`, un `tip` que indica la evidencia en la que se basa y un enlace de `docs`. Se pide a los agentes que finalicen primero la solicitud del usuario, mencionen las misiones secundarias aplicables y actúen sobre una solo cuando el usuario esté de acuerdo. Solo se devuelven a los miembros de la cuenta del proyecto, ya sea que se conecten con una sesión de usuario, un token de MCP o una identidad de agente:

| ID | Herramienta | Sugerido cuando |
|----|------|----------------|
| `xcode_compilation_cache` | `get_xcode_build` | Una compilación limpia procesada con Xcode 26 o posterior no ejecutó tareas de compilación almacenables en caché. |
| `gradle_build_cache` | `get_gradle_build` | Una compilación ejecutó tareas almacenables en caché sin que la caché de compilación de Gradle calculara una clave para ninguna de ellas, lo que significa que la caché de compilación estaba desactivada. |
| `flaky_test_quarantine` | `get_test_run` | Una ejecución tuvo tests inestables y ninguna automatización habilitada en el proyecto los silencia u omite. No se sugiere para proyectos de Struo. |
| `test_sharding` | `get_test_run` | Una ejecución de CI sin fragmentación tardó 10 minutos o más, en un sistema de compilación que Tuist puede fragmentar. La sugerencia indica cuántos tests omitieron ya los tests selectivos, cuando ocurrió. |
| `tuist_runners` | `get_xcode_build`, `get_test_run` | Una ejecución de CI utilizó máquinas de GitHub Actions, Bitrise, GitLab CI o Buildkite y la cuenta nunca ha ejecutado un trabajo en Tuist Runners. Solo en tuist.dev. |
| `pull_request_comments` | `get_xcode_build`, `get_test_run` | Una ejecución de GitHub Actions pertenece a un proyecto que no está conectado a su repositorio de GitHub. |
| `other_build_systems` | `get_project` | La cuenta no usa Tuist con todos los sistemas de compilación compatibles. La sugerencia enumera los archivos que identifican los demás, para que el agente pueda comprobar el repositorio. |

#### Búsqueda en documentación y comunidad

Esta herramienta de solo lectura busca en la documentación de Tuist, la referencia de la [interfaz de programación de aplicaciones](https://en.wikipedia.org/wiki/API), las versiones de GitHub, el foro de la comunidad y los issues de GitHub a través del mismo motor de búsqueda que impulsa el sitio web de documentación. Los resultados de las versiones incluyen el producto, la versión, la fecha de publicación y el estado de prelanzamiento. Las versiones estables se buscan por defecto y los prelanzamientos se pueden incluir con `include_prereleases`. La herramienta solo está disponible en el servidor alojado por Tuist en `https://tuist.dev/mcp`.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `search_tuist` | Busca en la documentación pública de Tuist, la referencia de la interfaz de programación de aplicaciones, las versiones de GitHub, las discusiones de la comunidad y los issues de GitHub. Opcionalmente, restringe a una `source` (`docs`, `api_reference`, `releases`, `forum`, `issues`). | `query` |

#### Feedback

Los agentes pueden informar al equipo de Tuist cuando una herramienta o prompt de Tuist no funcionó como esperaban, como un resultado confuso, un error, datos faltantes o una capacidad ausente. Se pide a los agentes que sugieran un informe y lo envíen solo una vez que tú estés de acuerdo. Cada informe abre una conversación con el soporte de Tuist, que puede responderte por correo electrónico. Un informe incluye lo que el agente esperaba, lo que ocurrió, una sugerencia opcional, tu ID de usuario de Tuist, tu handle y correo electrónico, y las organizaciones a las que perteneces. Los agentes también pueden nombrar la cuenta y el proyecto donde ocurrió el problema, para que el equipo sepa con qué organización hacer seguimiento; solo se aceptan cuentas a las que pertenezcas. Solo los agentes que hayan iniciado sesión como usuario de Tuist pueden enviar informes, y cada usuario puede abrir hasta 10 informes por hora. La herramienta solo está disponible en el servidor alojado por Tuist en `https://tuist.dev/mcp`.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `report_feedback` | Informa de un problema con una herramienta o prompt de Tuist. Opcionalmente, nombra la `tool_name`, la `account_handle` y el `project_handle` donde ocurrió, y añade una `suggestion`. | `category`, `expected`, `actual` |

#### Respuestas respaldadas por el código fuente

Estas herramientas de solo lectura permiten a los agentes usar la revisión exacta del código fuente público de Tuist desplegada junto con el servidor alojado como fuente de verdad para respuestas que dependen del comportamiento actual. Solo están disponibles en `https://tuist.dev/mcp`.

Los clientes compatibles reciben descripciones fácticas de la revisión del código fuente de las herramientas, enlaces y límites de resultados durante la inicialización, junto con información de autenticación OAuth integrada. Estas descripciones no prescriben el estilo de respuesta ni un flujo de trabajo de verificación. Los usuarios pueden hacer una pregunta directamente sin invocar primero el prompt `ask_tuist`; el prompt sigue disponible para un flujo de trabajo explícito respaldado por el código fuente.

Cada operación tiene límites fijos de concurrencia, duración, recorrido, bytes leídos y tamaño de respuesta. Los resultados de búsqueda y listado incluyen los campos `truncated` y `truncation_reason`. Cuando un resultado está truncado, reduce la ruta, el patrón de archivo o el término de búsqueda en lugar de tratar el resultado como exhaustivo.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `search_tuist_code` | Responde preguntas sobre el comportamiento actual, valores predeterminados, configuración, puertas de funcionalidad, manejo de errores o detalles no documentados buscando en los archivos de código fuente. Los resultados incluyen líneas circundantes, enlaces al código fuente fijados a la revisión y estadísticas de escaneo. | `pattern` |
| `list_tuist_files` | Descubre un subsistema de código fuente o tests cercanos cuando la ruta relevante es desconocida. Los listados tienen profundidad y recuentos de resultados limitados. | Ninguno |
| `read_tuist_file` | Inspecciona un rango de líneas específico en un archivo de implementación, sitio de llamada o test después de encontrar la ruta relevante. Las respuestas truncadas proporcionan `next_start_line` para continuar. | `path` |

#### Proyectos

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_accounts` | Enumera los handles de cuentas personales y de organización disponibles para el usuario autenticado, incluyendo si cada cuenta puede crear proyectos. | Ninguno |
| `get_organization` | Obtén el directorio de miembros de una organización. Las invitaciones pendientes requieren el mismo permiso de administrador que el dashboard; los tokens de aceptación de invitación nunca se devuelven. | `account_handle` |
| `create_organization` | Crea una organización de Tuist para el usuario autenticado. | `handle` |
| `create_project` | Crea un proyecto de Tuist bajo una cuenta a la que el usuario autenticado pueda acceder. | `account_handle`, `project_handle` |
| `add_organization_member` | Añade un usuario existente de Tuist a una organización o actualiza el rol de un miembro existente. Acepta `user` (el predeterminado), `admin` o `viewer`, donde un viewer puede leer dashboards y ejecuciones pero no puede cambiar nada. | `organization_handle`, `email` |
| `invite_organization_member` | Invita una dirección de correo electrónico a una organización, pertenezca o no a un usuario existente de Tuist. Tuist envía por correo un enlace de aceptación que caduca después de 14 días; cuando el servidor no puede enviar correos, `email_sent` es `false` y el enlace debe copiarse desde el dashboard. Acepta `user` (el predeterminado), `admin` o `viewer`. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `cancel_organization_invitation` | Cancela una invitación pendiente a una organización para que su enlace ya no pueda ser aceptado. Requiere permiso de administrador de la organización. | `organization_handle`, `email` |
| `list_projects` | Enumera todos los proyectos accesibles para el usuario autenticado. | Ninguno |
| `get_project` | Obtén la configuración de un proyecto y la URL del repositorio conectado. | `account_handle`, `project_handle` |
| `connect_project_repository` | Vincula un proyecto a un repositorio de GitHub al que la instalación de la GitHub App de la cuenta pueda acceder. El proyecto adopta la rama predeterminada del repositorio. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle`, `repository_full_handle` |
| `disconnect_project_repository` | Elimina el vínculo de un proyecto con su repositorio de GitHub. Requiere permiso de administrador del proyecto. | `account_handle`, `project_handle` |

#### Tokens de cuenta

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_account_tokens` | Enumera los metadatos de los tokens de cuenta sin exponer sus valores. | `account_handle` |
| `get_account_token` | Obtén los metadatos de un token de cuenta sin exponer su valor. | `account_handle`, `token_id` |
| `list_project_tokens` | Enumera los metadatos de los tokens de proyecto sin exponer sus valores. | `account_handle`, `project_handle` |

#### Reglas de notificación

Estas herramientas gestionan las propias reglas de notificación del usuario autenticado: cuando ocurre un evento, como una nueva preview, en los proyectos de la regla (o en cualquier proyecto sobre el que puedas recibir notificaciones, si no se lista ninguno) y cumple sus condiciones, ejecuta sus acciones, como una notificación push a tus dispositivos con la app de Tuist. Sin reglas no recibes notificaciones. Requieren autenticación de usuario, actúan solo sobre tus propias reglas y solo aceptan proyectos de cuentas a las que pertenezcas. No se ofrecen en las páginas del dashboard, porque las reglas abarcan todas tus cuentas.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_notification_events` | Enumera los tipos de eventos a los que las reglas pueden suscribirse, cada uno con un JSON Schema para sus condiciones. | Ninguno |
| `list_notification_condition_options` | Sugiere valores de condición para un evento en un proyecto, como los tracks y ramas de sus previews recientes. | `event`, `account_handle`, `project_handle` |
| `list_notification_rules` | Enumera tus reglas. | Ninguno |
| `create_notification_rule` | Crea una regla a partir de un evento, proyectos y condiciones opcionales, y al menos una acción. | `event`, `actions` |
| `update_notification_rule` | Cambia el estado habilitado, los proyectos, las condiciones o las acciones de una regla. | `rule_id` |
| `delete_notification_rule` | Elimina una regla. | `rule_id` |

#### Runners de integración continua

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_runner_jobs` | Enumera los jobs de runner de integración continua para una cuenta. | `account_handle` |
| `get_runner_job` | Obtén un job de runner de integración continua, incluyendo si su máquina se quedó sin memoria, qué detuvo y qué cambiar. | `account_handle`, `workflow_job_id` |
| `list_runner_job_steps` | Enumera los pasos registrados para un job de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_metrics` | Enumera las métricas de máquina registradas para un job de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_job_logs` | Enumera hasta 500 líneas de log capturadas para un job de runner de integración continua. | `account_handle`, `workflow_job_id` |
| `list_runner_workflows` | Enumera los resúmenes de workflows de integración continua para una cuenta. | `account_handle` |
| `list_runner_profiles` | Enumera los perfiles de runner de integración continua para una cuenta, con la etiqueta `runs-on` de cada uno. | `account_handle` |
| `get_runner_catalog` | Enumera las formas de máquina y versiones de Xcode que un perfil de runner puede usar. | `account_handle` |
| `create_runner_profile` | Crea un perfil de runner con una plataforma, una forma de máquina y, en macOS, una versión de Xcode. Opcionalmente indica qué ramas guardan sus volúmenes de caché. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `name`, `platform`, `vcpus`, `memory_gb` |
| `update_runner_profile` | Cambia la forma de máquina, la versión de Xcode o qué ramas guardan los cambios de su volumen de caché personalizado de un perfil de runner. Los campos omitidos conservan su valor. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |
| `delete_runner_profile` | Elimina un perfil de runner tras la confirmación del usuario. Los perfiles predeterminados no se pueden eliminar. Requiere administración de cuenta o el ámbito `account:runners:write`. | `account_handle`, `profile_name` |

Las herramientas de volumen de runner exponen los mismos datos que el dashboard de Volumes. Las herramientas de lectura requieren acceso a runners; borrar requiere administración de cuenta o el ámbito `account:runners:write`, y confirmación del usuario.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_runner_volumes` | Filtra por nombre y repositorio, ordena y paginación de volúmenes. | `account_handle` |
| `get_runner_volume` | Repositorio, plataforma, capacidad, espacio usado y último uso. | `account_handle`, `volume_id` |
| `list_runner_volume_jobs` | Referencias paginadas de jobs y workflows, estado de caché, resultado de acierto y tiempo de montaje. | `account_handle`, `volume_id` |
| `list_runner_job_volumes` | Volúmenes montados por un job. | `account_handle`, `workflow_job_id` |
| `get_runner_volume_analytics` | Series de almacenamiento, ejecuciones de jobs, tasa de aciertos y tendencias. Opcional `volume_id`, `start` y `end` (ISO 8601); por defecto siete días, máximo 90. | `account_handle` |
| `delete_runner_volume` | Elimina un volumen y su contenido guardado. Los jobs en ejecución mantienen sus copias privadas pero no pueden guardarlas; los jobs posteriores con la misma clave comienzan vacíos. | `account_handle`, `volume_id` |

Las listas aceptan `page` y `page_size` (hasta 100). El inventario de volúmenes también acepta `name` y `repository` (coincidencias exactas, combinadas con AND), `sort_by` (`volume`, `repository`, `used_space`, `capacity`, `last_used`) y `sort_order` (`asc`, `desc`). Las mediciones desconocidas y los resultados de acierto permanecen como `null`. El estado de caché describe si se guardaron los cambios del volumen, no el éxito del job.

#### Sandboxes

Las herramientas de sandbox exponen los mismos datos y acciones que el dashboard de Sandboxes, con el mismo acceso que la [API](https://tuist.dev/api/docs): los miembros de la cuenta pueden usar todas las herramientas en todos los sandboxes de la cuenta. Los visores de solo lectura no pueden usarlas. La cuenta necesita tener los sandboxes habilitados. Las páginas de sandbox del dashboard registran las herramientas de solo lectura.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_sandboxes` | Pagina sandboxes con su estado, forma y marcas de tiempo. Opcional `search` (texto en el sandbox, ID de sesión de Amp Orb o Anthropic), `status`, `vcpus`, `sort_by` (`created`, `last_active`, `identifier`) y `sort_order`. | `account_handle` |
| `get_sandbox` | Estado, forma, nodo, archivo y marcas de tiempo de un sandbox. | `account_handle`, `sandbox_id` |
| `get_sandbox_analytics` | Horas de vCPU, sandboxes creados, duraciones de sesión, configuración y tiempo de inicio, y picos de vCPUs, memoria y disco frente a los límites de la cuenta, con tendencias. Opcional `start` y `end` (ISO 8601); por defecto 30 días, máximo 90. | `account_handle` |
| `create_sandbox` | Arranca un sandbox vacío y devuélvelo una vez que esté en ejecución. Opcional `platform` (`linux` o `darwin`), `xcode_version` (la versión exacta de Xcode de un sandbox macOS, de entre las que lista la descripción de la herramienta; implica `darwin`), `repository` (el `owner/name` de github.com de un sandbox macOS, conectado a uno de los proyectos de la cuenta: el Mac arranca desde su <.localized_link href="/guides/features/sandboxes/claude#remote-mac-snapshots">snapshot listo</.localized_link> cuando un entorno Linux de Claude Code tiene un script de configuración de macOS), `template`, `vcpus` con `memory_mb` (Linux: 2x4096, 4x8192 u 8x16384, por defecto 2x4096; macOS: 8x8192, 8x16384 u 8x24576, por defecto 8x8192) `workspace_gb` y `lifetime_seconds` (cuánto tiempo puede ejecutarse antes de que se cancelen sus comandos en ejecución y se pause y archive, conservando sus archivos: dos horas por defecto, como máximo un día). Su descripción indica al agente que busque la versión de Xcode con la que compila el repositorio (`.xcode-version`, mise, configuración de CI o documentación) y la pase, ya que otra versión de Xcode no aprovechará las cachés y el snapshot del repositorio, que lea la guía que el Mac incluye en `/opt/tuist/agent-guide.md`, y que muestre la app ejecutándose en el Simulador de iOS con las herramientas de simulador siguientes. El Tuist del Mac, la versión fijada del repositorio cuando fija una, <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">usa la caché de la cuenta</.localized_link> por su cuenta. | `account_handle` |
| `pause_sandbox` | Crea una instantánea de un sandbox en ejecución en el disco de su nodo. | `account_handle`, `sandbox_id` |
| `resume_sandbox` | Reanuda un sandbox pausado o archivado. | `account_handle`, `sandbox_id` |
| `extend_sandbox` | Reinicia la vida útil de un sandbox desde ahora, con un `lifetime_seconds` opcional (como máximo un día). Los sandboxes propiedad de una integración no tienen vida útil. | `account_handle`, `sandbox_id` |
| `archive_sandbox` | Pone en cola el movimiento de los discos de un sandbox pausado al almacenamiento de objetos. | `account_handle`, `sandbox_id` |
| `delete_sandbox` | Elimina un sandbox y sus discos, tras la confirmación del usuario. | `account_handle`, `sandbox_id` |
| `list_sandbox_devices` | Dispositivos de un sandbox con su `id`, `name`, `platform`, `runtime` y `state` (`Booted`, `Shutdown`). Hoy estos son los simuladores de un sandbox macOS, como iOS; los emuladores de Android aún no son compatibles. | `account_handle`, `sandbox_id` |
| `boot_sandbox_device` | Arranca un dispositivo por nombre o ID y espera hasta 40 segundos; un simulador aparece en la app Simulator. Arrancar un dispositivo ya arrancado tiene éxito. | `account_handle`, `sandbox_id`, `device` |
| `launch_sandbox_app` | Lanza una app en el dispositivo arrancado, reiniciándola si ya está en ejecución. Pasa `app_path`, un .app compilado en el sandbox, para instalarla primero, o `app_id` (en iOS, el bundle ID) para una app instalada. Opcional `device` cuando hay varios dispositivos arrancados. | `account_handle`, `sandbox_id` |
| `open_sandbox_url` | Abre una página web en el navegador (Safari en iOS) o un deep link de una app en el dispositivo arrancado. Opcional `device`. | `account_handle`, `sandbox_id`, `url` |
| `get_sandbox_screenshot` | Devuelve el dispositivo arrancado, o con `target: screen` toda la pantalla del sandbox, como imagen: un JPEG de como máximo 1600 píxeles en su lado más largo, para que quepa en el contexto del agente. Opcional `device`. Para el PNG a tamaño completo en disco, usa `tuist sandbox screenshot`. | `account_handle`, `sandbox_id` |

Las herramientas de dispositivo ejecutan comandos fijos en el sandbox; no ejecutan comandos que pases, lo cual solo hace `tuist sandbox exec` del CLI. Responden `devices_unsupported` en un sandbox Linux, `device_not_booted` hasta que se arranque un dispositivo, `device_not_found` para un nombre o ID que el sandbox no tiene, y `app_not_found` para un `app_path` faltante o una app que no está instalada.

El error de una herramienta de sandbox comienza con un código estable en su propia línea, como `code: fleet_busy`, seguido de qué hacer; los códigos que implican una espera añaden una línea `retry_after_seconds:`. La API envía el mismo `code` en el cuerpo de su error. Cuando todos los hosts están ocupados, `create_sandbox` espera hasta 25 segundos por uno antes de responder `fleet_busy`.

#### Espacios de trabajo de Amp

Estas herramientas gestionan las <.localized_link href="/guides/server/authentication#amp-orbs">conexiones de espacios de trabajo de Amp</.localized_link> que permiten a los orbs iniciar sesión en Tuist sin un token. Utilizan el mismo permiso exclusivo para administradores que la página de Integraciones del panel. Un agente en un orb puede leer sus propios IDs desde `$AMP_WORKSPACE_ID` y `$AMP_PROJECT_ID`. Cada orb admitido por una conexión obtiene acceso de CI a todos los proyectos de la cuenta, por lo que los agentes deben confirmar con el usuario antes de conectar.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_amp_workspace_connections` | Enumera los espacios de trabajo de Amp conectados a la cuenta y el proyecto al que está limitado cada uno, si corresponde. | `account_handle` |
| `connect_amp_workspace` | Conecta un espacio de trabajo de Amp. El `project_id` opcional limita el inicio de sesión a los orbs de un único proyecto de Amp. | `account_handle`, `workspace_id` |
| `disconnect_amp_workspace` | Desconecta un espacio de trabajo. Las sesiones que sus orbs ya tienen permanecen válidas hasta que caduquen. | `account_handle`, `connection_id` |

#### Entornos de Claude

Estas herramientas conectan entornos autoalojados de Claude Managed Agents, de modo que sus sesiones se ejecutan en sandboxes de Tuist, como hace Configuración → Integraciones → Claude. Requieren administración de cuenta y sandboxes habilitados. Un agente puede crear el entorno con la API de Anthropic, pero solo la Consola de Claude genera su clave de entorno, por lo que el agente se la solicita al usuario. Tuist inicia sesiones con una clave de API de Anthropic o con federación de identidad de carga de trabajo, y recupera el entorno con esa credencial antes de guardarlo. La configuración del lado de Anthropic utiliza las propias credenciales de Anthropic del usuario; Tuist nunca las recibe. Las claves pasan a través del cliente y del modelo, así que proporciónalas solo de forma explícita.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_claude_environments` | Enumera los entornos conectados y la credencial que usa cada uno, además de la URL del emisor y el prefijo de sujeto en los que debe confiar una regla de federación. | `account_handle` |
| `connect_claude_environment` | Conecta un entorno con `api_key`, o con `organization_id`, `workspace_id`, `service_account_id` y `federation_rule_id`. Los opcionales `platform`, `vcpus` y `memory_mb` definen la configuración del sandbox. | `account_handle`, `environment_id`, `environment_key` |

#### IA de la organización

Estas herramientas gestionan los modelos que usan las tareas de IA del lado del servidor de una organización, como hace Configuración → IA, y comparten sus reglas: solo para administradores de la organización y solo para organizaciones con configuración de IA. Cada tarea, como `pulse_grouping` o `pulse_explanation`, usa su ruta de tarea cuando tiene una y, en caso contrario, el modelo predeterminado; sin ninguna de las dos, no envía solicitudes. Cada herramienta devuelve toda la configuración, incluido el modelo actual de cada tarea y si proviene de su ruta, del predeterminado o de ninguno. Añadir o editar un proveedor requiere una clave de API, por lo que se hace en el panel o en la API REST (`/api/accounts/{handle}/ai`), no a través de estas herramientas.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_organization_ai_configuration` | Lee los proveedores (sin claves), los modelos, el modelo predeterminado, las rutas de tareas y el modelo actual de cada tarea. | `account_handle` |
| `save_organization_ai_model` | Añade un modelo (`name`, `provider_id`, `upstream_model_id`), o actualiza uno por `id`. | `account_handle` |
| `remove_organization_ai_model` | Elimina un modelo y sus rutas de tareas. | `account_handle`, `model_id` |
| `set_organization_ai_default_model` | Selecciona el modelo predeterminado, o límpialo con null. | `account_handle`, `model_id` |
| `save_organization_ai_task_route` | Enruta una `task` a un `model_id` configurado, o actualiza una ruta por `id`. Una tarea tiene como máximo una ruta. | `account_handle` |
| `remove_organization_ai_task_route` | Elimina una ruta, para que la tarea vuelva a usar el modelo predeterminado. | `account_handle`, `route_id` |
| `remove_organization_ai_provider` | Elimina un proveedor con su clave, sus modelos y sus rutas; desvincula una organización de Claude vinculada. | `account_handle`, `provider_id` |

#### Webhooks

Las herramientas de webhook utilizan el mismo permiso exclusivo para administradores que el panel. Los intentos de entrega contienen los datos de solicitud y respuesta registrados para el endpoint, pero nunca el secreto de firma del endpoint.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_webhook_endpoints` | Enumera los endpoints de webhook de una cuenta. | `account_handle` |
| `get_webhook_endpoint` | Obtiene un endpoint de webhook. | `account_handle`, `webhook_endpoint_id` |
| `list_webhook_delivery_attempts` | Enumera los intentos de entrega de un endpoint. | `account_handle`, `webhook_endpoint_id` |
| `get_webhook_delivery_attempt` | Obtiene un intento de entrega. | `account_handle`, `webhook_endpoint_id`, `delivery_attempt_id` |

#### Compilaciones de Xcode

Las herramientas de detalle de compilación para Xcode, Gradle, Bazel, Mix y Cargo exponen la estructura existente de `custom_metadata: {tags, values}`, incluidas las observaciones de infraestructura cuando se informan. Los valores siguen siendo cadenas y se conservan las claves desconocidas. Por ejemplo, `tuist.cpu.available_processors` describe los procesadores lógicos disponibles en tiempo de ejecución, mientras que `tuist.gradle.max_workers` es un límite de workers de Gradle y `tuist.jvm.max_heap_bytes` es un límite de heap de JVM, no de memoria del host. Estas son observaciones de cliente no confiables, no identidades de runner verificadas. Las observaciones ausentes permanecen ausentes; los logs importados y los clientes antiguos pueden no tener metadatos de infraestructura. Los metadatos de Struo esperan una actualización coordinada del cliente/protocolo.

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_xcode_builds` | Enumera las ejecuciones de compilación de Xcode de un proyecto. | `account_handle`, `project_handle` |
| `get_xcode_build` | Obtén información detallada sobre una ejecución de compilación de Xcode específica, incluida una URL de descarga temporal para el archivo que contiene el `.xcactivitylog` sin procesar. | `build_run_id` |
| `list_xcode_build_targets` | Enumera los targets de compilación de una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_files` | Enumera los archivos compilados de una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_steps` | Enumera los pasos de compilación registrados con sus tiempos y resultados, sin el texto del log. | `build_run_id` |
| `get_xcode_build_step` | Obtén un paso de compilación registrado, incluido su log y su indicador de truncamiento. | `build_run_id`, `step_id` |
| `list_xcode_build_issues` | Enumera los problemas de compilación (advertencias y errores) de una ejecución de compilación específica. | `build_run_id` |
| `list_xcode_build_cache_tasks` | Enumera las tareas almacenables en caché (aciertos/fallos de caché) de una ejecución de compilación de Xcode específica. | `build_run_id` |
| `list_xcode_build_cas_outputs` | Enumera las salidas del [almacenamiento direccionable por contenido](https://en.wikipedia.org/wiki/Content-addressable_storage) de una ejecución de compilación de Xcode específica. | `build_run_id` |

`list_xcode_build_steps` devuelve páginas de 20 pasos por defecto (máximo 100 mediante `page_size`), con `page` y `pagination_metadata` para la navegación. Usa `search` para coincidir con títulos, proyectos o targets, o filtra por `project`, `target`, `category` exactos (por ejemplo, `swiftCompilation`) y `status` (`success` o `failure`). Ordena por `duration_ms` para mostrar primero los más lentos (el valor predeterminado) o por `start_ms` para orden cronológico. Los IDs de paso desempatan y se devuelven como cadenas decimales para preservar su precisión completa de 64 bits. Los IDs están limitados a una compilación y no deben coincidir entre compilaciones.

Los parámetros opcionales `start_ms` y `end_ms` seleccionan los pasos que se superponen con un rango de tiempo en milisegundos desde el inicio de la compilación; el final es exclusivo. Ambas herramientas aceptan un UUID de compilación o una URL del panel como `build_run_id`. Pasa el `id` del paso devuelto sin cambios como `step_id` para recuperar su log. Los logs conservan hasta 64 KiB por paso, con `log_truncated` indicando la salida omitida.

Los pasos se recopilan de forma predeterminada cuando se procesan las compilaciones de Xcode. Los datos de los pasos registrados se conservan durante 90 días. La respuesta de la lista incluye `availability`: `available` cuando existen pasos registrados, incluso si los filtros no coinciden con ninguno; `processing` cuando la compilación aún se está procesando y aún no tiene pasos; o `unavailable` cuando los pasos no se registraron o han caducado.

Las mismas operaciones están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps` y `GET /api/projects/{account_handle}/{project_handle}/xcode/builds/{build_id}/steps/{step_id}`, con los mismos filtros y paginación. Ambas requieren acceso de lectura al proyecto de la compilación.

#### Compilaciones de Gradle

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_gradle_integration_guide` | Devuelve la autenticación completa, la configuración del proyecto, el plugin de Gradle, la política de caché y el flujo de verificación de dos compilaciones. Los agentes deben llamarla antes de editar un proyecto Android o Gradle existente. | Ninguno |
| `list_gradle_builds` | Enumera las ejecuciones de compilación de Gradle para un proyecto, incluidos los metadatos personalizados. Filtra por una etiqueta personalizada con el parámetro opcional `tag`. | `account_handle`, `project_handle` |
| `get_gradle_build` | Obtiene los metadatos de la compilación, los recuentos de tareas/caché y `failures`: el mensaje de fallo de cada tarea fallida y paso de configuración. | `build_run_id` |
| `list_gradle_build_tasks` | Enumera los resultados de las tareas, la identidad de compilación compuesta, la capacidad de caché, el estado incremental y los mensajes de fallo. | `build_run_id` |
| `list_gradle_build_steps` | Enumera las tareas cronometradas, la configuración y las transformaciones, con búsqueda, metadatos y filtros de tiempo superpuestos. | `build_run_id` |
| `get_gradle_build_step` | Inspecciona los metadatos del paso registrado por ID opaco; el `log` de una tarea fallida o de un paso de configuración es su mensaje de fallo. | `build_run_id`, `step_id` |

Las listas de pasos de Gradle y Bazel devuelven 20 resultados por defecto (máximo 100), admiten `search`, `project`, `target`, `category` y `status` exactos, filtros de superposición `start_ms` / `end_ms` (fin exclusivo) y ordenación por `duration_ms` o `start_ms`. Pasa los IDs devueltos sin cambios; están limitados a su compilación. Las listas exponen `time_origin` y `coverage`. Los informes antiguos de Gradle usan `first_recorded_timestamp` porque no se cargó ningún inicio de compilación. Los perfiles de Bazel exponen todos los intervalos registrados con cobertura `trace_profile` y `profile_start` como origen de tiempo. Las compilaciones antiguas recurren a resúmenes BEP retenidos. Los registros fuente caducan después de 90 días. Los detalles de Bazel incluyen logs de acciones sanitizados cuando se publican. Los detalles de Gradle de una tarea fallida o un paso de configuración incluyen el mensaje de fallo que el plugin de Gradle de Tuist reportó como `log`: el mensaje de excepción y su cadena de causas tal como la consola de Gradle los imprime, sin trazas de pila ni salida de la tarea, con las rutas dentro del proyecto convertidas a relativas y las credenciales y otras rutas locales ocultadas, como máximo 16 KiB por paso y 32 pasos fallidos por compilación. Otros pasos de Gradle, compilaciones reportadas por versiones antiguas del plugin e informes sin credenciales tienen un `log` nulo. Los pasos de configuración reportan `failure` cuando fallan y `unknown` en caso contrario. El prompt `compare_builds` usa esta cobertura para distinguir trazas completas de Bazel de resúmenes retenidos y dirige a los agentes a los detalles de los pasos para conocer los resultados de las acciones y los logs antes de comprobar la salida de invocación más amplia.

Las herramientas de paso único `get_gradle_build_step` y `get_bazel_build_step` recuperan un paso por ID y no aceptan filtros de tiempo; usa las herramientas de lista correspondientes para filtrar pasos por rango de tiempo.

Los IDs de paso de Bazel devueltos desde resúmenes retenidos siguen siendo legibles si llega un perfil completo entre la enumeración y la obtención de un paso. Un perfil indexado cuyos datos de paso han caducado reporta como no disponible. Las listas de pasos de Gradle incluyen operaciones en caché y omitidas de duración cero.

#### Invocaciones de Bazel

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_bazel_integration_guide` | Devuelve la autenticación, la configuración del proyecto, la configuración de Bazel y el flujo de trabajo de verificación. | Ninguno |
| `list_bazel_invocations` | Enumera las invocaciones completadas del [Protocolo de Eventos de Compilación de Bazel](https://bazel.build/remote/bep), de la más reciente a la más antigua, con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales correlacionados de caché remota para un proyecto. Filtra por `status`, `git_branch`, `git_commit_sha`, `is_ci` y `command`. | `account_handle`, `project_handle` |
| `get_bazel_invocation` | Obtén una invocación de Bazel completada con métricas de compilación, una línea de tiempo de ejecución acotada, diagnósticos de ruta crítica y totales correlacionados de caché remota. | `account_handle`, `project_handle`, `invocation_id` |
| `list_bazel_build_steps` | Enumera los intervalos del perfil de Bazel registrados, con filtros y cobertura explícita. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_build_step` | Inspecciona un paso de Bazel registrado y su resultado de acción publicado y log sanitizado. | `account_handle`, `project_handle`, `invocation_id`, `step_id` |
| `list_bazel_remote_actions` | Enumera las acciones que la ejecución remota de Tuist ejecutó para una invocación, con mnemotécnico, target, digest de acción, código de salida, ruta de ejecución y tiempos por fase. Filtros opcionales `sort_by` (`duration` o `queued_at`), `failed` y `mnemonic`. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_remote_action` | Obtén el argv de una acción remota, el entorno (valores con aspecto de secreto ocultos), la plataforma, el directorio de trabajo, las rutas de salida, el worker, el código de salida, los primeros 16 KiB de stdout y stderr, los `errors` del compilador reconocidos en stderr, los tiempos por fase y el digest de acción. | `account_handle`, `project_handle`, `invocation_id`, `action_id` |
| `get_bazel_remote_action_log` | Lee hasta 64 KiB del stdout o stderr de una acción remota por desplazamiento de bytes, el final del flujo por defecto. Los flujos largos se copian completos, o conservan sus primeros 16 KiB y últimos 16 MiB cuando son más largos; `recorded` enumera los rangos disponibles. | `account_handle`, `project_handle`, `invocation_id`, `action_id`, `stream` |
| `list_bazel_invocation_logs` | Enumera los logs sanitizados capturados para una invocación de Bazel en orden de ejecución: la cola acotada de la salida de progreso de Bazel y los artefactos `test.log`. Los filtros opcionales `stream` (`stdout` o `stderr`), `source` (`progress` o `test_log`), `target_label` y `errors` reducen los resultados. | `account_handle`, `project_handle`, `invocation_id` |
| `get_bazel_invocation_log` | Obtén un fragmento de log sanitizado capturado para una invocación de Bazel. | `account_handle`, `project_handle`, `invocation_id`, `invocation_log_id` |
| `list_bazel_cache_events` | Enumera las observaciones raw de caché remota de Bazel con su operación, endpoint y hora de observación, opcionalmente reducidas a una invocación, resultado u operación. | `account_handle`, `project_handle` |
| `get_bazel_cache_event` | Obtén una observación raw de caché remota de Bazel. | `account_handle`, `project_handle`, `cache_event_id` |

#### Ejecución remota

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_remote_execution_activity` | Enumera las invocaciones de Bazel en ejecución del proyecto y sus acciones remotas en ejecución y en cola ahora mismo, con la invocación, mnemotécnico, target, digest de acción, tamaño de máquina y cuándo entró en ese estado de cada acción. Las acciones que la puerta de enlace de ejecución ejecuta en una VM que preparó con antelación no se enumeran hasta que finalizan. | `account_handle`, `project_handle` |
| `get_remote_execution_usage` | Obtén las ejecuciones remotas del proyecto y el tiempo de ejecución medido durante `[from, to)`, en total, por tamaño de máquina, por modo de despacho y por hora, día o mes. El periodo por defecto son los últimos 30 días y abarca como máximo 366. | `account_handle`, `project_handle` |

Los filtros de `list_bazel_invocations` son coincidencias exactas, y las invocaciones que terminan en el mismo segundo se ordenan por ID de invocación. Para encontrar la última invocación fallida en una rama, llámala con `status: "failure"`, `git_branch` y `page_size: 1`. El endpoint REST `GET /api/projects/{account_handle}/{project_handle}/bazel/invocations` acepta los mismos filtros.

Establece `remote_execution: true` en `list_bazel_build_steps` para devolver solo acciones con tiempos de fase del servidor asociados de forma segura desde perfiles indexados. Las respuestas de lista y detalle exponen valores opcionales anulables `remote_queue_ms`, `remote_input_fetch_ms`, `remote_execution_ms` y `remote_output_upload_ms`. Los valores suman las fases registradas, incluidos los reintentos dentro de la acción; los valores ausentes o nulos significan no disponible, no cero. Son observaciones de perfil, no uso facturable ni prueba de ejecución nueva, ya que los resultados del servidor en caché pueden llevar metadatos de ejecución. Las subidas del cliente están excluidas. Los perfiles antiguos o ambiguos pueden no devolver acciones coincidentes incluso cuando hubo trabajo remoto. El endpoint REST de paso acepta el mismo filtro `remote_execution=true`. La pestaña Ejecución remota del dashboard usa la misma consulta y retención de 90 días.

Los logs de test llevan la `target_label` y el `status` del intento del resultado de test del que proceden, por lo que `target_label: "//foo:bar_test"` devuelve solo los logs de test de ese target. `errors: true` devuelve los logs de test de intentos fallidos y los fragmentos de progreso de stderr que contienen una línea que el reportero de Bazel inicia con `ERROR:`, `FAIL:` o `TIMEOUT:`. La salida de progreso no se atribuye a targets, y los logs escritos antes de que se registrara la atribución tienen campos vacíos. Las acciones fallidas y su propia salida están disponibles por target desde `list_bazel_build_steps`, y los fallos por caso de test desde las herramientas de ejecución de tests.

#### Compilaciones de Cargo

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_cargo_builds` | Enumera las compilaciones de Cargo para un proyecto, de la más reciente a la más antigua. Filtra por `git_branch`, `status`, `is_ci` o `command`. Los resultados de ejecución de tests de Cargo están disponibles a través de las herramientas de test, no en este listado de compilaciones. | `account_handle`, `project_handle` |
| `get_cargo_build` | Obtén los metadatos de la compilación, los contadores agregados de caché y hasta 500 trabajos de compilador registrados con diagnósticos. `compilations_truncated` indica los trabajos omitidos; los diagnósticos cubren solo los trabajos devueltos. | `account_handle`, `project_handle`, `build_id` |

Establece `include_cache_inspection: true` en `get_cargo_build` para recuperar decisiones de tareas validadas y operaciones CAS, limitado a 4 MB. Por defecto, y cuando los registros faltan o son inválidos, `cache_inspection` es null. Respeta su indicador de captura parcial `truncated`; las transferencias no establecen el origen local/remoto de cada acierto de tarea. El endpoint de detalle HTTP acepta el mismo parámetro de consulta.

#### Compilaciones de Mix

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_mix_builds` | Enumera las compilaciones de compilación de Mix (Elixir) para un proyecto, de la más reciente a la más antigua, incluyendo metadatos personalizados. Filtra por `git_branch`, `status`, `is_ci` o `mix_env`. | `account_handle`, `project_handle` |
| `get_mix_build` | Obtén los metadatos de la compilación, los recuentos de diagnósticos y el resumen de la caché de dependencias. | `account_handle`, `project_handle`, `build_id` |

#### Traces de compilación

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `get_build_trace` | Obtén un enlace de descarga para la línea de tiempo de una compilación de Xcode, Gradle, Bazel o Mix como un archivo de trace que puedes abrir en [Perfetto](https://ui.perfetto.dev). | `account_handle`, `project_handle`, `build_id` |

`build_id` es el ID de ejecución de la compilación (el ID de invocación para Bazel) o la URL del dashboard de la compilación. El `trace_url` devuelto sirve un archivo JSON de [Evento de Trace de Chrome](https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU). Cualquier persona que tenga el enlace puede descargar el trace de esa compilación sin otras credenciales hasta `expires_at`, una hora después de la llamada. Los agentes pueden descargarlo con `curl`, entregártelo para que lo abras en Perfetto o consultarlo con el `trace_processor` de Perfetto. El trace contiene los pasos registrados empaquetados en carriles por paralelismo, una pista que abarca toda la compilación y contadores de CPU y memoria cuando la compilación registró métricas de la máquina. Contiene los mismos datos que las herramientas de paso anteriores, sin logs. El dashboard ofrece el mismo archivo desde la pestaña Timeline de cada compilación.

#### Ejecuciones de Struo

<a id="once-runs"></a>

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_once_runs` | Enumera las ejecuciones de Struo para un proyecto, de la más reciente a la más antigua. Filtra por `kind` (`build`, `test` o `generic`), `status`, `is_ci` o `git_branch`. Las ejecuciones que no han finalizado tienen el estado `in_progress`. | `account_handle`, `project_handle` |
| `get_once_run` | Obtén una ejecución con sus totales de acciones, resumen de caché y, para ejecuciones de tests, totales de tests. | `account_handle`, `project_handle`, `run_id` |

Los IDs de compilación de Cargo, compilación de Mix y ejecución de Struo son únicos dentro de un proyecto. Las mismas lecturas están disponibles a través de la API HTTP en `GET /api/projects/{account_handle}/{project_handle}/cargo/builds`, `.../mix/builds` y `.../once/runs`, cada una con un endpoint de detalle para un ID.

#### Tareas, acciones, módulos y archivos

Estas herramientas con ámbito de proyecto inspeccionan identidades de compilación persistentes entre ejecuciones. Comienza con `list_build_entities`, luego pasa un `id` estable devuelto con el mismo `kind` a `get_build_entity` o `list_build_entity_history`, junto con `account_handle` y `project_handle`. No se requiere ningún identificador de compilación o invocación.

| Herramienta | Descripción | Parámetros obligatorios |
| --- | --- | --- |
| `list_build_entities` | Enumera las tareas, módulos, acciones o archivos de un tipo vistos en las compilaciones de un proyecto. | `account_handle`, `project_handle`, `kind` |
| `get_build_entity` | Obtén una entidad de compilación con su identidad nativa y análisis para el período elegido. | `account_handle`, `project_handle`, `kind`, `id` |
| `list_build_entity_history` | Enumera las ejecuciones, compilaciones o eventos de caché registrados de una entidad de compilación, de la más reciente a la más antigua. | `account_handle`, `project_handle`, `kind`, `id` |

| `kind` | Cadena de herramientas | Listados de historial |
| --- | --- | --- |
| `bazel_actions` | Acciones de Bazel | Ejecuciones de acciones reportadas por BEP |
| `gradle_tasks` | Tareas de Gradle | Ejecuciones de tareas |
| `xcode_modules` | Módulos de Xcode | Compilaciones y eventos de caché de módulos |
| `once_actions` | Acciones de Struo | Ejecuciones |
| `mix_files` | Archivos compilados de Mix | Compilaciones |
| `mix_modules` | Módulos compilados de Mix | Compilaciones |
| `cargo_crates` | Crates de Cargo | Invocaciones de rustc registradas |

Estas herramientas se están implementando gradualmente y solo devuelven datos para proyectos donde están habilitadas; para otros proyectos devuelven un error en lugar de un resultado vacío. Un tipo solo está disponible para proyectos que usan su cadena de herramientas de compilación. Las herramientas aceptan filtros acotados `start_at`/`end_at`, `environment` (`any`, `ci` o `local`) y una `branch` exacta. `list_build_entities` acepta `q`; `list_build_entity_history` admite cursores opacos `after`/`before`. Las observaciones de tiempo o caché desconocidas permanecen no disponibles en lugar de convertirse en cero o fallos. El historial hace referencia al padre registrado y a la ejecución nativa para profundizar usando las herramientas de ejecución existentes.

Las métricas de `get_build_entity` incluyen `duration_samples`, el número de observaciones con tiempo registrado: las duraciones cero genuinas cuentan, el tiempo faltante no. Este recuento puede ser menor que el recuento de observaciones; las estadísticas de duración no disponibles permanecen nulas.

Las duraciones de los módulos de Xcode provienen de compilaciones de objetivos medidas en los logs de compilación. Las resoluciones de caché de módulos y los objetivos sin trabajo de compilación no contribuyen muestras de duración. Las observaciones de compilación hacen referencia a la compilación de Xcode; los eventos de caché hacen referencia al comando de generación o caché.

Las acciones de Bazel se identifican por etiqueta de objetivo, mnemotécnico y salida principal configurada, manteniendo acciones y configuraciones separadas distintas sin depender de resúmenes de caché dependientes de la entrada. El historial registra ejecuciones reportadas por BEP, no búsquedas de caché ni fases de perfil de trace. La cobertura completa de ejecución requiere `--build_event_publish_all_actions`; la entrega de artefactos es de mejor esfuerzo, por lo que las observaciones faltantes no son evidencia de que no se haya ejecutado trabajo. Las cargas útiles antiguas de Kura sin identidad estable o inicio de ejecución siguen siendo aceptadas pero no indexadas. Las mediciones de tiempo de finalización ausentes permanecen no disponibles y las duraciones cero genuinas cuentan.

Las duraciones de los módulos de Mix miden la compilación del archivo contenedor, no el trabajo del módulo medido independientemente. Las acciones de Struo usan ranuras declaradas de objetivo/capacidad/índice cuando el cliente reportó los mapeos de objetivo; las etiquetas de diagnóstico por sí solas no son identidades estables. Los clientes existentes y las herramientas a nivel de ejecución siguen siendo compatibles sin cambios.

Los crates de Cargo se agrupan por raíz de crate registrada exacta, nombre y tipo. Los cambios en la ruta de checkout pueden dividir los historiales, y los perfiles de compilación, características y triples de objetivo no se distinguen. El historial mide invocaciones de rustc, no trabajo por archivo ni aciertos de caché; los trabajos ausentes no establecen eliminaciones ni un inventario completo del espacio de trabajo.

Las lecturas de análisis tienen memoria y tiempo de ejecución acotados. Si una consulta supera esos límites, la herramienta devuelve un error en lugar de inventar un resultado vacío.

Las nuevas observaciones se indexan después del despliegue; esta función no rellena la telemetría de ejecución existente. Los metadatos de identidad sobreviven a las observaciones individuales bajo la <.localized_link href="/guides/server/data-retention">política de retención de datos</.localized_link>.

#### Tests

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_test_runs` | Enumera las ejecuciones de tests para un proyecto, cada una con su `selective_testing_strategy`. Filtra por `selective_testing` (`coverage`, que incluye los fallbacks de la selección basada en cobertura, o `module_hash`). Los campos de `query` son `git_branch`, `scheme`, `status` y `selective_testing`: `field:"value"` coincide exactamente, `field~"value"` coincide con una subcadena que no distingue mayúsculas y minúsculas (no en `selective_testing`), y un `-` inicial niega cualquiera de los operadores. Por ejemplo, `-git_branch~"gh-readonly-queue"` excluye las ramas de cola de merge. Los filtros de consulta separados por espacios en blanco y los argumentos explícitos se combinan con semántica AND. | `account_handle`, `project_handle` |
| `get_test_run` | Obtén métricas detalladas para una ejecución de tests, incluyendo su propia cobertura de código (`coverage`: si midió alguna, sus líneas y cifra, y si fue parcial o se ejecutó desde un checkout sucio), su resumen de tests selectivos (`selective_testing`: estrategia, commit de referencia, y recuentos de tests solicitados, seleccionados, omitidos y estimados, de los cuales se calcula la efectividad de la selección de tests), y URLs de descarga temporales para su paquete de resultados (`.xcresult`) y para el archivo de sesión (logs de CLI) del comando que la ejecutó, o `null` cuando ningún comando está vinculado a la ejecución. El `result_bundle_url` de una ejecución fragmentada es el paquete del primer fragmento que reporta; `shard_result_bundles` lista un paquete para cada informe de fragmento, incluidos los reintentos de CI, con su índice de fragmento y estado, por lo que se puede inspeccionar un fragmento que falló sin un test fallido. | `test_run_id` |
| `list_test_module_runs` | Enumera las ejecuciones de módulos de tests para una ejecución de tests específica. | `test_run_id` |
| `list_test_suite_runs` | Enumera las ejecuciones de suites de tests para una ejecución de tests específica, opcionalmente filtradas por módulo. | `test_run_id` |
| `list_test_cases` | Enumera los casos de tests para un proyecto (admite filtros como `flaky`). | `account_handle`, `project_handle` |
| `get_test_case` | Obtén métricas detalladas para un caso de test, incluyendo la tasa de fiabilidad, la tasa de inestabilidad y los recuentos de ejecuciones. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_test_case_runs` | Enumera las ejecuciones de casos de tests, opcionalmente filtradas por caso de test o ejecución de tests. | `account_handle`, `project_handle` |
| `get_test_case_run` | Obtén detalles de fallos y repeticiones para una ejecución específica de un caso de test y, cuando la selección basada en cobertura de su ejecución mantuvo el test, el motivo (`selective_testing`: decisión, razón, el archivo modificado que coincidió y el fragmento). | `test_case_run_id` |
| `list_test_case_run_attachments` | Enumera los archivos adjuntos para una ejecución de un caso de test. Cada adjunto incluye una URL de descarga temporal. | `test_case_run_id` |
| `list_test_case_events` | Enumera los cambios de estado de un caso de test, como silenciarlo u omitirlo. | `test_case_id` |
| `update_test_case` | Actualiza el estado o la clasificación de inestabilidad de un caso de test. Un cambio puede enviar un evento a los endpoints de webhook configurados, incluidos servicios externos. | `test_case_id` o `identifier` + `account_handle` + `project_handle` |
| `list_xcode_test_targets` | Enumera los resultados de objetivos de tests selectivos para una ejecución de tests. | `test_run_id` |
| `list_selective_testing_tests` | Enumera los tests que la selección basada en cobertura de una ejecución de tests decidió, seleccionó y omitió, con la razón de cada decisión, el archivo modificado que lo seleccionó, su fragmento y su resultado en la ejecución. Filtra por `decision`, `reason` o `search`. | `test_run_id` |
| `list_selective_testing_changed_files` | Enumera los archivos que cambiaron desde la referencia de selección basada en cobertura de una ejecución de tests, con cuántos tests seleccionó cada uno y si es un archivo rastreado cuyo cambio hace que la selección recurra al fallback. | `test_run_id` |
| `get_coverage` | Obtén la cobertura de código de un proyecto con sus objetivos, en un commit o en el último commit completo de una rama. Sin `git_commit_sha` ni `branch`, lee la rama predeterminada. | `account_handle`, `project_handle` |
| `list_coverage_files` | Enumera los archivos que midió la cobertura de código de un commit, con su cobertura por línea, en un commit o en el último commit completo de una rama. Admite `search`, ordenación y paginación. | `account_handle`, `project_handle` |
| `get_coverage_file` | Obtén la cobertura de código de un archivo y sus funciones en un commit o en el último commit completo de una rama. Establece `include_lines` para obtener el recuento de ejecuciones de cada línea. | `account_handle`, `project_handle`, `path` |
| `list_coverage_branches` | Enumera las ramas con cobertura de código, mostrando primero la rama predeterminada. | `account_handle`, `project_handle` |
| `list_coverage_commits` | Enumera los commits de una rama con su estado de cobertura (`complete`, `incomplete`, `in_progress`, `not_measured`), cifra y cambio respecto al commit completo anterior, empezando por los más recientes. Paginación con cursores. | `account_handle`, `project_handle` |
| `list_coverage_runs` | Enumera las ejecuciones de tests con cobertura de código asociadas a un commit o una rama, cada una marcada como `full`, `partial` o `discarded` (un checkout sucio). Paginación con cursores. | `account_handle`, `project_handle` |
| `list_coverage_targets` | Enumera la cobertura de un commit por objetivo, seguida de los objetivos que sus ejecuciones obtuvieron de la caché binaria sin contadores de cobertura (`measured: false`). Admite `search`, ordenación y paginación. | `account_handle`, `project_handle` |

Las herramientas de cobertura de código están disponibles para las cuentas con cobertura de código habilitada.

#### Paquetes

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_bundles` | Enumera los paquetes (binarios de app) para un proyecto. Opcionalmente filtra por `git_branch` y `tags` (todas las etiquetas deben coincidir exactamente). | `account_handle`, `project_handle` |
| `get_bundle` | Obtén información detallada sobre un paquete específico, incluidas las etiquetas personalizadas. | `bundle_id` |
| `get_bundle_artifact_tree` | Obtén el árbol completo de artefactos para un paquete como una lista plana ordenada por ruta. | `bundle_id` |

`list_bundles` acepta `tags: ["paid", "production"]` para distinguir variantes de compilación o entornos. Las etiquetas son identificadores sensibles a mayúsculas y minúsculas que contienen letras, números, guiones o guiones bajos, con un máximo de 10 etiquetas y 50 caracteres por etiqueta. Los resultados de lista y detalle incluyen `custom_metadata.tags`. Los recuentos de paginación y los filtros de rama se aplican a los resultados etiquetados; omitir `tags` conserva el comportamiento sin filtrar. Los filtros de etiquetas no válidos devuelven un error en lugar de ampliar la consulta.

#### Generaciones

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_generations` | Enumera las ejecuciones de generación para un proyecto. | `account_handle`, `project_handle` |
| `get_generation` | Obtén información detallada sobre una ejecución de generación específica. | `generation_id` |

#### Ejecuciones de caché

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_cache_runs` | Enumera las ejecuciones de caché para un proyecto. | `account_handle`, `project_handle` |
| `get_cache_run` | Obtén información detallada sobre una ejecución de caché específica, incluida una URL de descarga temporal para su archivo de sesión (logs de CLI). | `cache_run_id` |
| `list_xcode_module_cache_targets` | Enumera los objetivos de caché de módulos para una generación o ejecución de caché, mostrando el estado de acierto/fallo de caché por objetivo y los hashes de componentes de diagnóstico, incluidas entradas de hash adicionales. | `run_id` |

#### Previews

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_previews` | Enumera las previsualizaciones de app compartibles para un proyecto. | `account_handle`, `project_handle` |
| `get_preview` | Obtén una previsualización y las URL de descarga temporales para sus compilaciones. | `preview_id` |
| `get_latest_preview` | Encuentra la última previsualización para un binario de app en ejecución. | `account_handle`, `project_handle`, `binary_id`, `build_version` |

#### Automatizaciones

| Herramienta | Descripción | Parámetros obligatorios |
|------|-------------|---------------------|
| `list_automation_alerts` | Enumera las alertas de automatización para un proyecto. | `account_handle`, `project_handle` |
| `get_automation_alert` | Obtén una alerta de automatización. | `alert_id` |
| `list_automation_alert_revisions` | Enumera el historial de revisiones de una alerta de automatización. Las credenciales de acción están ocultas. | `alert_id` |
| `list_project_notification_alerts` | Enumera las reglas de alerta de notificación del proyecto. Requiere el mismo permiso de administrador que la página de configuración del panel. Las direcciones de webhook están ocultas. | `account_handle`, `project_handle` |

### Eventos

Los clientes que usan el ciclo de vida sin estado del `2026-07-28` Model Context Protocol pueden llamar a `events/list` para descubrir eventos y sus esquemas de carga útil:

| Evento | Cuándo se envía | Filtro de suscripción |
|-------|-----------------|---------------------|
| `test_case.marked_flaky` | Un caso de test cambia de no inestable a inestable. | `account_handle`, `project_handle` |
| `build.failed` | Una compilación local o de integración continua de Xcode, Gradle o Bazel finaliza con un fallo. | `account_handle`, `project_handle` |
| `test_run.failed` | Una ejecución de tests local o de integración continua finaliza con un fallo, incluida una ejecución fragmentada fusionada o una ejecución abandonada. | `account_handle`, `project_handle` |
| `ci_job.failed` | Un trabajo de runner de Tuist se completa con un fallo. | `account_handle` |
| `pulse_symptom.opened` | Pulse abre o reabre un síntoma a nivel de tablero o página. No se envían los síntomas registrados solo a nivel de auditoría ni los cambios posteriores a un síntoma abierto. | `account_handle` |

Para suscribirse, el cliente llama a `events/subscribe` con el nombre del evento, los identificadores listados arriba en `arguments` y una entrega `webhook` que contiene una URL de callback `https://` y un secreto de firma `whsec_`. Los eventos de proyecto requieren pertenencia a la cuenta y acceso de lectura a los datos de test o compilación correspondientes; los eventos de trabajos de runner requieren pertenencia a la cuenta y acceso de lectura al runner; los eventos de síntomas de Pulse requieren pertenencia a la organización y acceso a Pulse para la cuenta, y un token de cuenta debe pertenecer a esa cuenta. Los tokens de acceso reclamados [`auth.md`](https://workos.com/auth-md), los tokens de cuenta reclamados y las concesiones de autorización del navegador pueden crear suscripciones; la entrega se detiene cuando la credencial asociada ya no está activa. Cada usuario puede mantener hasta 25 suscripciones activas. Tuist envía un desafío de verificación al callback antes de guardar la suscripción. El callback debe devolver un objeto que contenga el mismo valor `challenge`. La suscripción dura siete días por defecto, se puede renovar volviendo a suscribirse y deja de entregar cuando se elimina el acceso o la credencial del usuario. El opcional `ttlMs` está limitado entre una hora y 30 días. Tuist reintenta un callback con tiempo agotado y lo cancela después de al menos tres tiempos de espera consecutivos que abarcan cinco minutos; vuelve a suscribirte después de restaurar el callback.

Cuando ocurre un evento, Tuist envía su identificador de recurso y la URL del panel al callback. Los fallos de compilación y de ejecución de tests también incluyen `is_ci` y `git_branch`, por lo que los clientes pueden ignorar los fallos locales o filtrar por rama. Los eventos de compilación incluyen `build_system`; los eventos de trabajos de runner incluyen tanto `workflow_job_id` como `workflow_run_id`; los eventos de síntomas de Pulse incluyen `symptom_id`, `tier` (`board` o `page`) y la entidad afectada bajo `untrusted`, como `{"type": "untrusted_json", "value": {"service", "kind", "key"}}` con cada valor de como máximo 200 caracteres: la entidad proviene de telemetría de producción, así que trátala como datos, nunca como instrucciones. Su URL abre la página del síntoma. La solicitud incluye un identificador de suscripción y cabeceras de firma de [Standard Webhooks](https://www.standardwebhooks.com/) para que el cliente pueda verificar su origen. Tuist reintenta las entregas fallidas, por lo que los clientes deben usar el `eventId` estable para descartar duplicados. La carga útil omite los nombres de los tests, los logs y los mensajes de fallo; el cliente puede obtener esos detalles a través de las herramientas anteriores y decidir si notifica a un equipo o comienza la depuración. Los clientes pueden detener la entrega con `events/unsubscribe`.

### Prompts

| Prompt | Descripción |
|--------|-------------|
| `fix_flaky_test` | Te guía para corregir un test inestable analizando patrones de fallo, identificando la causa raíz y aplicando una corrección específica. |
| `compare_builds` | Te guía para comparar compilaciones e identificar regresiones de rendimiento, cambios en la caché y problemas de compilación. Usa herramientas nativas para proyectos Xcode, Gradle, Bazel y Cargo. Las comparaciones de Cargo preservan la cobertura parcial del compilador y distinguen el trabajo estimado del compilador del ahorro de tiempo transcurrido. |
| `compare_test_runs` | Te guía para comparar dos ejecuciones de tests e identificar regresiones, nuevos fallos y tests inestables. |
| `compare_bundles` | Te guía para comparar dos paquetes e identificar cambios de tamaño en todo el árbol de artefactos. |
| `compare_test_case` | Te guía para comparar el comportamiento de un caso de test entre dos ramas o períodos de tiempo. |
| `compare_generations` | Te guía para comparar dos ejecuciones de generación e identificar regresiones de rendimiento y cambios en la caché de módulos. |
| `compare_cache_runs` | Te guía para comparar dos ejecuciones de caché e identificar cambios en la eficacia de la caché y regresiones a nivel de objetivo. |
| `integrate_gradle_project` | Te guía para integrar Tuist en un proyecto Gradle existente. Incluye autenticación separada de la herramienta y de Gradle, descubrimiento de cuenta, creación de proyecto, política de caché remota, análisis de compilaciones y verificación de lectura. |
| `integrate_bazel_project` | Te guía para crear o seleccionar un proyecto Bazel, autenticar la línea de comandos, configurar la caché remota y los análisis de compilaciones, y verificar la integración a través de los datos de compilación de Tuist. |
| `integrate_xcode_project` | Te guía para integrar Tuist en un proyecto Xcode existente. Admite caché de Xcode, análisis de compilaciones, análisis de tests y fragmentación de tests. |
| `ask_tuist` | Responde a una pregunta sobre Tuist utilizando material público como contexto y evidencia específica de implementación y tests como fuente de verdad para el comportamiento actual. Requiere un `question` y cita evidencia vinculada a una revisión. |

Los prompts de datos de proyecto aceptan `account_handle` y `project_handle` para delimitar la investigación a un proyecto específico. Los prompts de comparación también aceptan los argumentos `base` y `head` para especificar los dos elementos a comparar (por ID, URL del panel o nombre de rama). `ask_tuist` acepta una `question` en lugar de parámetros de proyecto. `integrate_gradle_project` también acepta `features`, una lista separada por comas de integraciones de Gradle a aplicar: `remote_cache`, `build_insights`, `test_insights`, `flaky_tests` y `test_sharding`. `integrate_bazel_project` acepta un `server_url` opcional para instalaciones autoalojadas o locales. `integrate_xcode_project` acepta `features` con `xcode_cache`, `build_insights`, `test_insights` y `test_sharding`.

#### Funcionalidades del prompt de integración de Gradle

El prompt `integrate_gradle_project` y la herramienta `get_gradle_integration_guide` documentan el flujo completo de configuración. La herramienta también es referenciada por las instrucciones de inicialización del servidor, lo que la hace detectable por agentes que no enumeran prompts.

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `remote_cache` | Habilita la caché de compilación de Gradle, configura la política de subida de la caché remota de Tuist y recomienda subir solo desde ejecutores de integración continua con uso local de solo lectura. |
| `build_insights` | Aplica el plugin de Tuist para Gradle y configura el comportamiento de subida de análisis de compilaciones cuando sea necesario. |
| `test_insights` | Aplica el plugin de Tuist para Gradle para que los resultados de la tarea `Test` de Gradle se suban automáticamente. |
| `flaky_tests` | Guía la configuración para la detección de tests inestables, el uso opcional del plugin Gradle Test Retry y la configuración de cuarentena de tests. |
| `test_sharding` | Añade el flujo de trabajo de integración continua para `tuistPrepareTestShards`, la generación de la matriz de fragmentos y la ejecución de tests basada en `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones desea el usuario o que infiera el conjunto útil más pequeño a partir de la solicitud antes de editar el proyecto Gradle.

#### Funcionalidades del prompt de integración de Xcode

El prompt `integrate_xcode_project` documenta todas las integraciones de Xcode que admite Tuist:

| Funcionalidad | Qué configura el agente |
|---------|---------------------------|
| `xcode_cache` | Configura `tuist setup cache`, los ajustes de caché del proyecto generado, los ajustes manuales de compilación de la caché de Xcode y una política de subida limitada a ejecutores de integración continua. |
| `build_insights` | Configura `tuist inspect build`, `tuist xcodebuild`, `-resultBundlePath` y métricas opcionales de la máquina a través de `tuist setup insights`. |
| `test_insights` | Configura `tuist inspect test`, las post-acciones de test del esquema y la generación de paquetes de resultados para ejecuciones de tests de integración continua. |
| `test_sharding` | Añade la planificación de fragmentos para Xcode o el proyecto generado y el flujo de ejecución de fragmentos con `TUIST_SHARD_INDEX`. |

Cuando se omite `features`, el prompt pide al agente que aclare qué integraciones desea el usuario o que infiera el conjunto útil más pequeño a partir de la solicitud antes de editar el proyecto Xcode.
