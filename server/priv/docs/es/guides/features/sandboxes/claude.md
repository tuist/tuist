---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y claude --cloud) en los Sandboxes de Tuist, en Linux o macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Solo con invitación**
>
> Los sandboxes de Tuist, tanto en Linux como en macOS, están disponibles actualmente solo con invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

Anthropic ejecuta el bucle del agente de Claude, y un *entorno autoalojado* decide dónde se ejecutan las herramientas de Claude. Conéctalo a Tuist y cada sesión en él obtendrá su propio <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> de Tuist, en Linux o macOS. Tuist ejecuta los workers y runners que esos entornos necesitan, por lo que no tienes que alojar nada.

Hay dos tipos de entornos, uno por producto de Claude:

- **[Claude Managed Agents](#managed-agents)**: sesiones que inicias con la API de Claude o la API de agent-sessions de Tuist. Creas el entorno (`env_…`) en la [Consola de Claude](https://platform.claude.com/environments), y cada sesión puede elegir Linux o macOS.
- **[Claude Code](#claude-code)**: sesiones en la nube que los desarrolladores inician desde claude.ai, las aplicaciones de escritorio y móviles de Claude, y `claude --cloud`. Un propietario de Claude Team o Enterprise crea los entornos (`ccpool_…`) en la configuración de administración de claude.ai, uno para cada plataforma, y los desarrolladores eligen Linux o macOS seleccionando el entorno.

Ambos se conectan a través de la API de Tuist mediante un administrador de cuenta. Autentícate con `tuist auth login`, luego:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Conectar un entorno {#managed-agents-connect}

1. En la [Consola de Claude](https://platform.claude.com/environments), haz clic en **Crear entorno** y, bajo **Alojamiento**, selecciona **Autoalojado**. Abre el entorno, haz clic en **Generar clave de entorno** y copia el ID del entorno `env_…` y la clave. Consulta la guía de Anthropic sobre [sandboxes autoalojados](https://platform.claude.com/docs/en/managed-agents/self-hosted-sandboxes) para más detalles.
2. Conéctalo a tu cuenta de Tuist:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "anthropic_environment_id": "env_...",
       "environment_key": "<environment key>",
       "anthropic_api_key": "<Anthropic API key>"
     }'
   ```

   `anthropic_api_key` es opcional. Te permite iniciar sesiones a través de la API de Tuist, como se describe a continuación. Tuist almacena ambas claves cifradas y nunca las devuelve.

En menos de un minuto, Tuist comienza a atender las sesiones del entorno. El entorno se ejecuta en Linux a menos que pases `"platform": "darwin"`. También puedes pasar `vcpus`, `memory_mb` y `workspace_gb` para cambiar la configuración de sus sandboxes; consulta <.localized_link href="/guides/features/sandboxes#platforms">Linux y macOS</.localized_link>.

### Iniciar una sesión {#managed-agents-sessions}

Cada sesión se ejecuta en la plataforma del entorno a menos que la sesión solicite otra.

**Con la API de Claude**, crea la sesión como de costumbre con el ID del entorno y establece `tuist_platform` en los metadatos de la sesión como `macos` o `linux`:

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

El repositorio se descarga en `/workspace` en Linux y en `/Users/runner/work` en macOS. El sandbox de una sesión se pausa después de que el agente termina un turno y se reanuda con el siguiente mensaje.

> [!WARNING]
> Cualquier persona que pueda crear sesiones en el espacio de trabajo de Claude que posee el entorno puede ejecutar sesiones en tu cuenta de Tuist y puede solicitar macOS mediante los metadatos de la sesión. Limita el acceso a ese espacio de trabajo en consecuencia.

## Claude Code {#claude-code}

Las sesiones en la nube de Claude Code son aquellas que los desarrolladores inician desde [claude.ai/code](https://claude.ai/code), las aplicaciones de escritorio y móviles de Claude, y `claude --cloud`. Eligen dónde se ejecuta una sesión según su entorno, por lo que debes conectar un entorno para cada plataforma que quieras ofrecer.

### Conectar entornos {#claude-code-connect}

1. Un propietario de la organización de Claude activa **Permitir entornos autoalojados** en la página de administración de [Entornos en la nube](https://claude.ai/admin-settings/cloud-environments). Esto requiere un plan Team o Enterprise; consulta la guía de Anthropic sobre [entornos autoalojados](https://code.claude.com/docs/en/self-hosted-environments).
2. En la misma página, crea un entorno autoalojado para cada plataforma, con el nombre que verán los desarrolladores, por ejemplo **Tuist Linux** y **Tuist macOS**. Copia el ID `ccpool_…` de cada entorno y su clave de entorno, que se muestra solo una vez.
3. Conecta cada entorno a tu cuenta de Tuist con `kind` establecido como `claude_code` y su plataforma:

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

En menos de un minuto, los entornos estarán listos para aceptar sesiones. Una sesión inactiva mantiene su sandbox en ejecución durante 30 minutos y luego lo pausa; el siguiente mensaje de la sesión reanuda el mismo sandbox. Cambia el tiempo de espera con `max_idle_seconds` (hasta 3600).

### Elegir Linux o macOS {#claude-code-choose}

Los desarrolladores eligen el entorno, y con él la plataforma, cuando inician una sesión en la nube:

- **claude.ai, aplicaciones de escritorio y móviles:** elige **Tuist Linux** o **Tuist macOS** en el selector de entorno de una nueva sesión.
- **CLI de Claude Code:** ejecuta `/remote-env` en `claude` y elige el entorno por nombre. `claude --cloud "<task>"` se ejecutará entonces en él. Para elegir uno para una sola sesión, pasa su ID: `claude --cloud "<task>" --environment ccpool_...`.
- **Todo un equipo o repositorio:** establece el ID del entorno predeterminado en la [configuración](https://code.claude.com/docs/en/settings) de Claude Code, por ejemplo en el `.claude/settings.json` de un repositorio:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Las sesiones en estos entornos utilizan el uso de Claude Code de tu organización como de costumbre, y sus sandboxes cuentan para tu cuenta de Tuist.
