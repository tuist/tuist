---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y claude --cloud) en los Sandboxes de Tuist, en Linux o macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Solo por invitación**
>
> Los Sandboxes de Tuist, tanto en Linux como en macOS, están disponibles actualmente solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

Anthropic ejecuta el bucle del agente de Claude, y un *entorno autoalojado* decide dónde se ejecutan las herramientas de Claude. Conecta uno a Tuist y cada sesión en él obtendrá su propio <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> de Tuist, en Linux o macOS. Tuist ejecuta los workers y runners que esos entornos necesitan, por lo que no tienes que alojar nada.

Hay dos tipos de entornos, uno por producto de Claude:

- **[Agentes gestionados de Claude](#managed-agents)**: sesiones que inicias con la API de Claude o la API de agent-sessions de Tuist. Creas el entorno (`env_…`) en la [Consola de Claude](https://platform.claude.com/environments), y cada sesión puede elegir Linux o macOS.
- **[Claude Code](#claude-code)**: sesiones en la nube que los desarrolladores inician desde claude.ai, las aplicaciones de escritorio y móviles de Claude, y `claude --cloud`. Un propietario de Claude Team o Enterprise crea los entornos (`ccpool_…`) en la configuración de administración de claude.ai, uno para cada plataforma, y los desarrolladores eligen Linux o macOS seleccionando el entorno.

Ambos se conectan a través de la API de Tuist mediante un administrador de la cuenta. Autentícate con `tuist auth login`, luego:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Agentes gestionados de Claude {#managed-agents}

### Conectar un entorno {#managed-agents-connect}

Conéctate desde **Configuración → Integraciones → Claude** de tu cuenta. El formulario solicita un entorno autoalojado y la credencial con la que Tuist inicia sus sesiones:

1. **Crea el entorno.** En la Consola de Claude, crea un entorno autoalojado en la página [Environments](https://platform.claude.com/environments), ábrelo y haz clic en **Generate environment key**. Anthropic solo genera claves de entorno en la Consola.
2. **Selecciona una credencial** con el selector en la parte superior del formulario (ver más abajo).
3. **Pega el ID y la clave del entorno** y elige la plataforma y la forma de los sandboxes del entorno.

Tuist recupera el entorno con la credencial antes de guardar nada, por lo que una credencial, ID o espacio de trabajo incorrectos fallarán en el formulario. Almacena las claves cifradas y nunca las vuelve a mostrar. En menos de un minuto, Tuist comienza a servir las sesiones del entorno. Consulta <.localized_link href="/guides/features/sandboxes#platforms">Linux y macOS</.localized_link> para ver las formas.

#### Con una clave de API {#managed-agents-connect-api-key}

La opción predeterminada y la forma más rápida de probar los sandboxes. Pega una clave de API con el rol de desarrollador en el espacio de trabajo del entorno. La integración marca los entornos que usan una clave de API; antes de depender de uno, conéctalo con una identidad federada en su lugar, para que Tuist no mantenga ninguna clave de larga duración.

#### Con una identidad federada {#managed-agents-connect-federated}

Tuist se autentica con la [Federación de identidades de carga de trabajo](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation) de Anthropic, por lo que nunca le das una clave de API de Anthropic. Necesitas el rol de administrador en tu organización de Anthropic.

1. **Confía en Tuist.** El formulario muestra la URL del emisor y el prefijo del subject de tu cuenta. En la Consola de Claude, abre [Workload identity](https://platform.claude.com/settings/workload-identity-federation), haz clic en **Connect workload**, elige **Custom OIDC** e introdúcelos con el ámbito `workspace:developer`. Añade la cuenta de servicio que crea el asistente al espacio de trabajo del entorno.
2. **Introduce los IDs.** El ID de la organización está en **Settings → Organization** y el ID del espacio de trabajo en **Settings → Workspaces**. Connect workload muestra los IDs de la cuenta de servicio y de la regla de federación cuando finaliza, y la página de la regla en Workload identity los muestra de nuevo. Ninguno de ellos es secreto. Si Anthropic rechaza el token de Tuist, el [historial de autenticación](https://platform.claude.com/settings/workload-identity-federation?tab=history) de la Consola muestra el motivo.

#### Con la API {#managed-agents-connect-api}

Para conectar desde la automatización, crea un entorno autoalojado en la [Consola de Claude](https://platform.claude.com/environments), genera su clave y envía ambos a Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

Para iniciar sesiones a través de la API de Tuist, envía también los cuatro IDs de federación (consulta [Conectar sin una clave de API](#managed-agents-federation)) o una `anthropic_api_key`. El entorno se ejecuta en Linux a menos que pases `"platform": "darwin"`; `vcpus`, `memory_mb` y `workspace_gb` cambian la forma de sus sandboxes.

### Iniciar una sesión {#managed-agents-sessions}

Cada sesión se ejecuta en la plataforma del entorno a menos que la sesión solicite otra.

**Con la API de Claude**, crea la sesión como de costumbre con el ID del entorno y establece `tuist_platform` en los metadatos de la sesión a `macos` o `linux`:

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url` y, opcionalmente, `repository_ref` (una rama o commit) hacen que Tuist clone un repositorio público en el sandbox antes del primer turno del agente.

**Con la API de agent-sessions de Tuist**, Tuist crea el agente y la sesión por ti, y clona repositorios privados de GitHub que están conectados a tu cuenta de Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

Cuando la cuenta tiene más de un entorno, pasa `agent_environment_id`. Puedes seguir la sesión con `GET /agent-sessions/{id}/events`, responder con `POST /agent-sessions/{id}/messages` y finalizarla con `POST /agent-sessions/{id}/archive`.

El repositorio se extrae en `/workspace` en Linux y en `/Users/runner/work` en macOS. El sandbox de una sesión se pausa después de que el agente termina un turno y se reanuda con el siguiente mensaje.

> [!WARNING]
> Cualquier persona que pueda crear sesiones en el espacio de trabajo de Claude que posee el entorno puede ejecutar sesiones en tu cuenta de Tuist y puede solicitar macOS con los metadatos de la sesión. Limita el acceso a ese espacio de trabajo en consecuencia.

### Conectar sin una clave de API {#managed-agents-federation}

El panel de control configura esto por ti. A través de la API, Tuist funciona de la misma manera: cada cuenta tiene su propio emisor de OpenID Connect en Tuist, `https://tuist.dev/oidc/accounts/<account id>`, y firma un token de corta duración para cada llamada a Anthropic, que intercambia por un token de acceso de Anthropic que dura unos minutos. Una regla de federación que confía en tu emisor nunca acepta tokens que Tuist firme para otras cuentas.

- Cada respuesta del entorno del agente incluye `federation_issuer_url` y `federation_subject` (`account:123:agent-environment:456`). En el asistente de Custom OIDC de la Consola, usa la URL del emisor y ya sea ese subject exacto, para admitir solo este entorno, o `account:123:*` para admitir todos los entornos de la cuenta. Las comprobaciones de configuración del panel de control usan el subject `account:123:setup`, que solo admite el prefijo. Usa el ámbito `workspace:developer`.
- Envía los IDs de la organización, el espacio de trabajo, la cuenta de servicio y la regla como `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` y `anthropic_federation_rule_id`, al crear o con `PATCH /agent-environments/{id}`. Cuando un entorno tiene tanto los IDs como una clave de API, Tuist usa la federación.

> [!NOTE]
> Anthropic obtiene las claves del emisor a través de HTTPS en el puerto 443 desde un nombre de host público. Si tu servidor Tuist autoalojado no es accesible desde internet, elige la fuente JWKS **inline** en la Consola y pega el conjunto de claves que tu servidor sirve en `<issuer>/jwks.json`. Vuelve a pegarlo cada vez que cambie la clave de firma de Tuist, lo cual ocurre cuando cambia `TUIST_SECRET_KEY_TOKENS` del servidor (o, si no está configurado, `TUIST_SECRET_KEY_BASE`).

## Claude Code {#claude-code}

Las sesiones en la nube de Claude Code son las que los desarrolladores inician desde [claude.ai/code](https://claude.ai/code), las aplicaciones de escritorio y móviles de Claude, y `claude --cloud`. Eligen dónde se ejecuta una sesión mediante su entorno, por lo que debes conectar un entorno para cada plataforma que quieras ofrecer.

### Conectar entornos {#claude-code-connect}

1. Un propietario de la organización de Claude activa **Allow self-hosted environments** en la página de administración de [Cloud environments](https://claude.ai/admin-settings/cloud-environments). Esto requiere un plan Team o Enterprise; consulta la guía de [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) de Anthropic.
2. En la misma página, crea un entorno autoalojado para cada plataforma, con el nombre que verán los desarrolladores, por ejemplo **Tuist Linux** y **Tuist macOS**. Copia el ID `ccpool_…` de cada entorno y su clave de entorno, que se muestra solo una vez.
3. Conecta cada entorno a tu cuenta de Tuist con `kind` establecido en `claude_code` y su plataforma:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   Repite con `"platform": "linux"` y el ID y la clave del otro entorno.

En menos de un minuto, los entornos están listos para aceptar sesiones. Una sesión inactiva mantiene su sandbox en ejecución durante 30 minutos y luego lo pausa; el siguiente mensaje de la sesión reanuda el mismo sandbox. Cambia el tiempo de espera con `max_idle_seconds` (hasta 3600).

### Elegir Linux o macOS {#claude-code-choose}

Los desarrolladores eligen el entorno, y con él la plataforma, cuando inician una sesión en la nube:

- **claude.ai, aplicaciones de escritorio y móviles:** elige **Tuist Linux** o **Tuist macOS** en el selector de entorno de una nueva sesión.
- **Claude Code CLI:** ejecuta `/remote-env` en `claude` y elige el entorno por nombre. `claude --cloud "<task>"` se ejecuta entonces en él. Para elegir uno para una sola sesión, pasa su ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Todo un equipo o repositorio:** establece el ID del entorno predeterminado en la [configuración](https://code.claude.com/docs/en/settings) de Claude Code, por ejemplo en el `.claude/settings.json` del repositorio:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Las sesiones en estos entornos utilizan el uso de Claude Code de tu organización como de costumbre, y sus sandboxes cuentan para tu cuenta de Tuist.

### Inicios de sesión y compilaciones más rápidos {#claude-code-caching}

- **Caché de Tuist:** las sesiones reciben `TUIST_URL` y, cuando tu cuenta tiene una caché en el mismo rack, `TUIST_CACHE_ENDPOINT`. La CLI de Tuist y las tareas Mix de `tuist_ex` en una sesión inician sesión por sí mismas con el token de identidad de la sesión. Consulta <.localized_link href="/guides/server/authentication#claude-code-sessions">Sesiones de Claude Code</.localized_link> en la guía de autenticación.
- **Checkouts en caché:** cuando la aplicación de GitHub de Tuist de tu cuenta puede leer el repositorio de una sesión, una nueva sesión comienza desde el mismo checkout en caché que usan tus runners de Tuist, por lo que solo obtiene los commits que le faltan en lugar de clonar. Cuando la sesión termina, devuelve los objetos del último commit de la rama predeterminada, lo que mantiene actualizado el checkout en caché incluso para repositorios que no ejecutan CI en Tuist. Solo el commit que GitHub reporta para la rama predeterminada lo actualiza; las ramas propias de una sesión nunca lo hacen. Desactiva los sandboxes o desinstala la aplicación para detener esto.
- **macOS:** el Mac comparte las sesiones de compilación de Claude Code que se ejecutan con cada VM, por lo que una nueva sesión no lo descarga.

## Usar un Mac desde cualquier sesión de Claude Code {#remote-mac}

Las sesiones de Claude Code que se ejecutan en Linux, como las sesiones en la nube en un entorno alojado por Anthropic, aún pueden compilar y probar código para plataformas de Apple en un sandbox macOS de Tuist, como se describe en <.localized_link href="/guides/features/sandboxes#coding-agents">Compilar en un Mac desde un agente de codificación</.localized_link>. A diferencia de un entorno **Tuist macOS**, la sesión mantiene su propio entorno.

En un entorno **Tuist Linux** no hay nada que configurar: la CLI de Tuist y el servidor MCP de Tuist ya están instalados e inician sesión con la identidad de la sesión.

Para sesiones en la nube en un entorno alojado por Anthropic:

1. Haz que el <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> de Tuist esté disponible para las sesiones: añade `https://tuist.dev/mcp` como conector en claude.ai y actívalo para la sesión, o decláralo en el `.mcp.json` confirmado del repositorio.
2. Instala la CLI de Tuist en el [script de configuración](https://code.claude.com/docs/en/cloud-environments#setup-scripts) del entorno, por ejemplo con `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. Crea un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write`, y añádelo a las [variables de entorno](https://code.claude.com/docs/en/cloud-environments#set-environment-variables) del entorno como `TUIST_TOKEN`. Todos los que usen el entorno pueden leerlo, así que no le asignes ningún otro ámbito.
4. Permite que el entorno alcance Tuist. El acceso de red **Trusted** predeterminado de Anthropic no incluye `tuist.dev`, así que elige **Custom**, mantén los dominios predeterminados y añade `tuist.dev` a **Dominios permitidos**. La CLI sube los archivos de la sesión al Mac a través de `tuist.dev`, por lo que no necesita ningún otro dominio.

Claude elimina el Mac cuando la tarea está completa. Un Mac que queda atrás se pausa cuando está inactivo y se elimina después de 14 días pausado. Los Mac creados de esta manera cuentan para tu cuenta de Tuist como cualquier otro sandbox.
