---
{
  "title": "Sandboxes",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Sandboxes de Tuist son máquinas virtuales persistentes en Linux y macOS para agentes de programación como Amp y Claude. Cada sesión de agente obtiene su propia máquina, que se pausa cuando el agente está inactivo y se reanuda con sus archivos intactos."
}
---
# Sandboxes {#sandboxes}

> [!IMPORTANT]
> **Solo por invitación**
>
> Las Sandboxes de Tuist, tanto para Linux como para macOS, están actualmente disponibles solo por invitación mientras escalamos la capacidad. [Contáctanos](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta. Los precios se anunciarán cuando las Sandboxes estén disponibles de forma general.

Una sandbox es una máquina virtual donde un agente de programación ejecuta sus comandos y edita sus archivos. Cada sesión del agente obtiene su propia sandbox, que mantiene su checkout, los productos de compilación y las herramientas instaladas durante toda la vida de la sesión. Cuando el agente queda inactivo, la sandbox se pausa; el siguiente mensaje la reanuda donde lo dejó.

Las sandboxes se ejecutan en la misma flota que los <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, junto a la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu equipo, por lo que las compilaciones de un agente pueden usar los mismos artefactos en caché que tu CI y tus máquinas locales.

Puedes usar sandboxes desde:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: ejecuta los orbs de tu espacio de trabajo de Amp en Tuist, o proporciona un Mac para compilaciones de Xcode a cualquier hilo de Amp con el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin Tuist Mac</.localized_link>.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y `claude --cloud`) en Tuist.
- **[La CLI de Tuist](#cli)**: crea sandboxes y ejecuta comandos en ellas desde tu terminal, o desde tus propias herramientas a través de la API.

## Empieza con la CLI {#cli}

Crea una sandbox y ejecuta comandos en ella desde tu terminal con `tuist sandbox`.

### 1. Iniciar sesión {#cli-log-in}

Gestionar sandboxes requiere un administrador de la cuenta:

```bash
tuist auth login
```

### 2. Crear una sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omite `--platform` para Linux. Pasa `--vcpus` junto con `--memory-gb` para una [forma](#platforms) más grande, y `--workspace-gb` para un disco más grande. El comando devuelve el control una vez que la sandbox está en ejecución e imprime sus detalles, incluido su ID. Usa la cuenta del proyecto Tuist en el directorio actual; pasa `--account` para elegir otra.

### 3. Ejecutar comandos {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

El comando se ejecuta con `bash -l` en la sandbox, que primero se reanuda si estaba pausada. `tuist` transmite su salida durante todo el tiempo que dure la ejecución y finaliza con el estado del comando; Ctrl-C lo cancela en la sandbox. Pasa `--cwd`, `--env NAME=VALUE` y `--timeout` (hasta seis horas) según sea necesario.

### Tareas comunes {#cli-tasks}

| Tarea | Comando |
| --- | --- |
| Listar sandboxes | `tuist sandbox list` |
| Mostrar una | `tuist sandbox show <id>` |
| Pausar o reanudar | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Replicar los archivos del árbol de trabajo local de Git en ella | `tuist sandbox sync <id>` |
| Copiar archivos hacia fuera o hacia dentro | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Eliminar | `tuist sandbox delete <id> --yes` |
| Ver uso | `tuist sandbox analytics` |

Añade `--json` para obtener una salida legible por máquina. Consulta la <.localized_link href="/cli/sandbox">referencia de la CLI</.localized_link> para ver todas las opciones. Para gestionar sandboxes desde código, usa las mismas operaciones a través de la [API de Tuist](https://tuist.dev/api/docs) bajo `/api/accounts/{account_handle}/sandboxes`, o permite que un agente las use a través de <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

Las herramientas que no pueden iniciar sesión de forma interactiva, como un plugin de agente que compila en una sandbox de macOS, pueden autenticarse con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write` en su lugar. Puede crear sandboxes, ejecutar comandos en ellas y pausarlas, reanudarlas y eliminarlas, al igual que un miembro de la cuenta. Las sandboxes que sirven a una integración de Amp o Claude, así como la analítica y la configuración de integraciones, permanecen bajo la gestión de los administradores de la cuenta.

### Tuist dentro de la sandbox {#tuist-in-sandbox}

Las imágenes de sandbox no incluyen la CLI de Tuist, por lo que se ejecuta la versión fijada por tu propio proyecto. Después del primer `tuist sandbox sync`, ejecuta `mise install` en la raíz del repositorio en la sandbox (`mise` y `brew` están instalados), luego ejecuta `tuist` a través de mise, por ejemplo con `$HOME/.local/share/mise/shims` en `PATH`.

Cada comando que inicias con `tuist sandbox exec` también recibe lo que recibe un runner de Tuist, por lo que las compilaciones en la sandbox usan la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu cuenta sin que tengas que pasar credenciales:

- `TUIST_URL` y, donde el host de la sandbox pueda alcanzarlo, como en macOS, el `TUIST_CACHE_ENDPOINT` de la caché en el mismo rack.
- `TUIST_OIDC_TOKEN`, un token de identidad de corta duración para ese comando. La CLI de Tuist 4.218.0 y versiones posteriores inician sesión con él automáticamente; con las versiones 4.215.0 a 4.217.x, ejecuta primero `tuist auth login` en el mismo comando.

El token se genera para cada comando y solo puede intercambiarse por un token de Tuist mientras ese comando se ejecuta, por lo que una sandbox nunca almacena una credencial de larga duración. Nunca concede más permisos de los que la persona o el token que inició el comando tiene sobre la caché: los miembros de una cuenta cuyos tokens de caché solo tienen permiso de escritura obtienen acceso de lectura, y un token de cuenta necesita ámbitos de caché, como `ci`, junto con `account:sandboxes:write` para que la sandbox pueda usar la caché. Las variables que pases con `--env` tienen prioridad.

## Compilar en un Mac desde un agente de programación {#coding-agents}

Un agente de programación que se ejecuta en Linux, como una sesión de agente en la nube, puede compilar, probar y ejecutar código para plataformas Apple en una sandbox de macOS mientras sigue editando archivos donde se ejecuta. En Amp, instala el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin Tuist Mac</.localized_link>. Para otros agentes, como Claude Code o Cursor:

1. Conecta el agente al <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> de Tuist. Su herramienta `create_sandbox` indica al agente cómo controlar el Mac.
2. Instala la CLI de Tuist donde se ejecute el agente, por ejemplo en el script de configuración del entorno: `mise use -g tuist@latest`, o `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (`tuist-linux-aarch64` en ARM).
3. Autentica la CLI. El inicio de sesión del servidor MCP no se transfiere a ella, así que ejecuta `tuist auth login` como miembro de la cuenta o establece `TUIST_TOKEN` con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write`.
4. Si el entorno restringe el acceso a la red, permite `tuist.dev`. La CLI sube archivos al Mac a través de él, por lo que no necesita ningún otro dominio.

El agente crea un Mac por tarea y, antes de cada comando, ejecuta `tuist sandbox sync`. Copia los archivos que Git no ignora, estén o no confirmados, y después solo los que hayan cambiado. Tras la primera sincronización, ejecuta `mise install` en la raíz del repositorio en el Mac, para que el [Tuist fijado del proyecto](#tuist-in-sandbox) esté allí, con sesión iniciada en la caché de tu cuenta. Luego, el agente ejecuta comandos como `xcodebuild` con `tuist sandbox exec`, copia resultados como capturas de pantalla o una app compilada de vuelta con `tuist sandbox cp`, y elimina el Mac cuando la tarea finaliza. Un Mac permanece en ejecución durante 10 minutos tras su último comando, así que el siguiente comienza de inmediato; `tuist sandbox pause` lo devuelve antes. Un Mac abandonado se pausa y se elimina tras 14 días pausado.

## Linux y macOS {#platforms}

Las sandboxes de **Linux** ejecutan Ubuntu 24.04:

- 2 vCPU, 4 GiB de RAM (predeterminado)
- 4 vCPU, 8 GiB de RAM
- 8 vCPU, 16 GiB de RAM

Las sandboxes de **macOS** se ejecutan en silicio de Apple con Xcode:

- 8 vCPU, 8 GiB de RAM (predeterminado)
- 8 vCPU, 16 GiB de RAM
- 8 vCPU, 24 GiB de RAM

## Seguridad {#security}

- Cada sandbox es su propia máquina virtual. Las sandboxes no comparten sistema de archivos, memoria ni procesos entre sí ni con trabajos de CI.
- Las sandboxes pertenecen a una cuenta y solo sus administradores pueden gestionarlas. Las sesiones de una integración solo acceden a las sandboxes de la cuenta a la que está conectada la integración.
- Las credenciales que proporcionas a Tuist para conectar una integración, como un token de proveedor de Amp o una clave de entorno de Claude, se almacenan cifradas y nunca se vuelven a mostrar.
- Una sandbox puede acceder a Internet. Trata lo que un agente pueda acceder desde ella como tratarías un trabajo de CI.
