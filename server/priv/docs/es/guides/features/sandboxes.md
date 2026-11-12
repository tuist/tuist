---
{
  "title": "Sandboxes",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Sandboxes de Tuist son máquinas virtuales persistentes en Linux y macOS para agentes de programación como Amp y Claude. Cada sesión del agente obtiene su propia máquina, que se pausa cuando el agente está inactivo y se reanuda con sus archivos intactos."
}
---
# Sandboxes {#sandboxes}

> [!IMPORTANT]
> **Solo por invitación**
>
> Las sandboxes de Tuist, tanto en Linux como en macOS, están disponibles solo por invitación mientras escalamos la capacidad. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta. Los precios se anunciarán cuando las sandboxes estén disponibles de forma general.

Una sandbox es una máquina virtual donde un agente de programación ejecuta sus comandos y edita sus archivos. Cada sesión de agente obtiene su propia sandbox, que conserva su checkout, los artefactos de compilación y las herramientas instaladas durante toda la sesión. Cuando el agente queda inactivo, la sandbox se pausa; el siguiente mensaje la reanuda desde donde se quedó.

Las sandboxes se ejecutan en la misma flota que los <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, junto a la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu equipo, de modo que las compilaciones de un agente pueden usar los mismos artefactos en caché que tus entornos de CI y tus máquinas locales.

Puedes usar sandboxes desde:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: ejecuta los orbs de tu workspace de Amp en Tuist.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y `claude --cloud`) en Tuist.
- **[La CLI de Tuist](#cli)**: crea sandboxes y ejecuta comandos en ellas desde tu terminal, o desde tus propias herramientas a través de la API.

## Comienza con la CLI {#cli}

Crea una sandbox y ejecuta comandos en ella desde tu terminal con `tuist sandbox`.

### 1. Inicia sesión {#cli-log-in}

Para gestionar sandboxes necesitas ser administrador de la cuenta:

```bash
tuist auth login
```

### 2. Crea una sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omite `--platform` para Linux. Pasa `--vcpus` junto con `--memory-gb` para elegir una [forma](#platforms) más grande, y `--workspace-gb` para un disco más grande. El comando devuelve el control cuando la sandbox está en ejecución e imprime sus detalles, incluido su ID. Usa la cuenta del proyecto de Tuist en el directorio actual; pasa `--account` para elegir otra.

### 3. Ejecuta comandos {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

El comando se ejecuta con `bash -lc` en la sandbox, que se reanuda primero si estaba pausada, y `tuist` finaliza con el estado del comando.

### Tareas habituales {#cli-tasks}

| Tarea | Comando |
| --- | --- |
| Listar sandboxes | `tuist sandbox list` |
| Mostrar una | `tuist sandbox show <id>` |
| Pausar o reanudar | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Eliminar | `tuist sandbox delete <id> --yes` |
| Ver uso | `tuist sandbox analytics` |

Añade `--json` para obtener salida legible por máquina. Consulta la <.localized_link href="/cli/sandbox">referencia de la CLI</.localized_link> para ver todas las opciones. Para controlar las sandboxes desde código, usa las mismas operaciones a través de la [API de Tuist](https://tuist.dev/api/docs) en `/api/accounts/{account_handle}/sandboxes`, o permite que un agente las use a través de <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

## Linux y macOS {#platforms}

Las sandboxes de **Linux** ejecutan Ubuntu 24.04:

- 2 vCPU, 4 GiB de RAM (predeterminado)
- 4 vCPU, 8 GiB de RAM
- 8 vCPU, 16 GiB de RAM

Las sandboxes de **macOS** se ejecutan en Apple silicon con Xcode:

- 8 vCPU, 8 GiB de RAM (predeterminado)
- 8 vCPU, 16 GiB de RAM
- 8 vCPU, 24 GiB de RAM

## Seguridad {#security}

- Cada sandbox es su propia máquina virtual. Las sandboxes no comparten sistema de archivos, memoria ni procesos entre sí ni con trabajos de CI.
- Las sandboxes pertenecen a una cuenta y solo sus administradores pueden gestionarlas. Las sesiones de una integración solo acceden a las sandboxes de la cuenta a la que está conectada la integración.
- Las credenciales que proporcionas a Tuist para conectar una integración, como un token de proveedor de Amp o una clave de entorno de Claude, se almacenan cifradas y nunca se vuelven a mostrar.
- Una sandbox puede acceder a Internet. Trata lo que un agente pueda acceder desde ella como tratarías un trabajo de CI.
