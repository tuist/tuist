---
{
  "title": "Sandboxes",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Sandboxes de Tuist son máquinas virtuales persistentes en Linux y macOS para agentes de programación como Amp y Claude. Cada sesión de agente obtiene su propia máquina, que se pausa cuando el agente está inactivo y se reanuda con sus archivos intactos."
}
---
# Sandboxes {#sandboxes}

> [!IMPORTANT]
> **Solo con invitación**
>
> Los Sandboxes de Tuist, tanto en Linux como en macOS, están disponibles actualmente solo con invitación mientras escalamos la capacidad. [Contáctanos](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta. Los precios se anunciarán cuando los Sandboxes estén disponibles de forma general.

Un sandbox es una máquina virtual donde un agente de programación ejecuta sus comandos y edita sus archivos. Cada sesión de agente tiene su propio sandbox, que mantiene su checkout, los productos de compilación y las herramientas instaladas durante toda la vida de la sesión. Cuando el agente queda inactivo, el sandbox se pausa; el siguiente mensaje lo reanuda donde lo dejó.

Los sandboxes se ejecutan en la misma flota que los <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, junto a la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu equipo, por lo que las compilaciones de un agente pueden usar los mismos artefactos en caché que tu CI y tus máquinas locales.

Puedes usar sandboxes desde:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: ejecuta los orbs de tu espacio de trabajo de Amp en Tuist, o proporciona una Mac para compilaciones de Xcode a cualquier hilo de Amp con el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin de Tuist para Mac</.localized_link>.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y `claude --cloud`) en Tuist.
- **[La CLI de Tuist](#cli)**: crea sandboxes y ejecuta comandos en ellos desde tu terminal, o desde tus propias herramientas a través de la API.

## Comienza con la CLI {#cli}

Crea un sandbox y ejecuta comandos en él desde tu terminal con `tuist sandbox`.

### 1. Inicia sesión {#cli-log-in}

Cualquier miembro de la cuenta puede crear y gestionar sus sandboxes:

```bash
tuist auth login
```

### 2. Crea un sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omite `--platform` para Linux. Pasa `--xcode` con una versión, como `--xcode 26.1.1`, para una Mac con esa [Xcode](#xcode); esto implica `--platform macos`. Pasa `--vcpus` con `--memory-gb` para una [forma](#platforms) más grande, y `--workspace-gb` para un disco más grande. El comando devuelve el control una vez que el sandbox está en ejecución e imprime sus detalles, incluido su ID. Usa la cuenta del proyecto de Tuist en el directorio actual; pasa `--account` para elegir otra.

### 3. Ejecuta comandos {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

El comando se ejecuta con `bash -l` en el sandbox, que se reanuda primero si estaba pausado. `tuist` transmite su salida durante todo el tiempo que dure la ejecución y sale con el estado del comando; Ctrl-C lo cancela en el sandbox. Pasa `--cwd`, `--env NAME=VALUE` y `--timeout` (hasta seis horas) según sea necesario.

### Tareas comunes {#cli-tasks}

| Tarea | Comando |
| --- | --- |
| Listar sandboxes | `tuist sandbox list` |
| Mostrar uno | `tuist sandbox show <id>` |
| Pausar o reanudar | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Sincronizar los archivos del árbol de trabajo local de Git en él | `tuist sandbox sync <id>` |
| Copiar archivos hacia fuera o hacia dentro | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Eliminar | `tuist sandbox delete <id> --yes` |
| Ver uso | `tuist sandbox analytics` |

Añade `--json` para obtener una salida legible por máquina. Consulta la <.localized_link href="/cli/sandbox">referencia de la CLI</.localized_link> para ver todas las opciones. Para controlar sandboxes desde código, usa las mismas operaciones a través de la [API de Tuist](https://tuist.dev/api/docs) en `/api/accounts/{account_handle}/sandboxes`, o permite que un agente las use a través de <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

Las herramientas que no pueden iniciar sesión de forma interactiva, como un plugin de agente que compila en un sandbox de macOS, pueden autenticarse con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write` en su lugar. Puede hacer lo que un miembro de la cuenta puede: crear sandboxes, ejecutar comandos en ellos, y pausarlos, reanudarlos, archivarlos y eliminarlos. La configuración de las integraciones permanece con los administradores de la cuenta.

### Tuist dentro del sandbox {#tuist-in-sandbox}

Las imágenes de sandbox no incluyen la CLI de Tuist, por lo que se ejecuta la versión fijada por tu propio proyecto. Después de la primera `tuist sandbox sync`, ejecuta `mise install` en la raíz del repositorio en el sandbox (`mise` y `brew` están instalados). Cada comando que inicias con `tuist sandbox exec` tiene los shims de mise (`$HOME/.local/share/mise/shims`) primero en `PATH`, por lo que `tuist` y otras herramientas de mise se ejecutan en tus comandos y en las fases de compilación de Xcode, como las post-actions de un esquema.

Cada comando que inicias con `tuist sandbox exec` también recibe lo que recibe un runner de Tuist, por lo que las compilaciones en el sandbox usan la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu cuenta sin que tengas que pasar credenciales:

- `TUIST_URL` y, donde el host del sandbox pueda alcanzarlo, como en macOS, el `TUIST_CACHE_ENDPOINT` de la caché en el mismo rack.
- `TUIST_OIDC_TOKEN`, un token de identidad de corta duración para ese comando. La CLI de Tuist 4.218.0 y versiones posteriores inician sesión con él automáticamente; con las versiones 4.215.0 a 4.217.x, ejecuta `tuist auth login` primero en el mismo comando.

El token se emite para cada comando y solo puede intercambiarse por un token de Tuist mientras ese comando se ejecuta, por lo que un sandbox nunca almacena una credencial de larga duración. Nunca concede más permisos de los que la persona o el token que inició el comando tiene sobre la caché: los miembros de una cuenta cuyos tokens de caché solo tienen permiso de escritura obtienen acceso de lectura, y un token de cuenta necesita ámbitos de caché, como `ci`, junto con `account:sandboxes:write` para que el sandbox pueda usar la caché. Las variables que pases con `--env` tienen prioridad.

## Compila en una Mac desde un agente de programación {#coding-agents}

Un agente de programación que se ejecuta en Linux, como una sesión de agente en la nube, puede compilar, probar y ejecutar código para plataformas de Apple en un sandbox de macOS mientras sigue editando archivos donde se ejecuta. En Amp, instala el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin de Tuist para Mac</.localized_link>. Para otros agentes, como Claude Code o Cursor:

1. Conecta el agente al <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> de Tuist. Su herramienta `create_sandbox` indica al agente cómo controlar la Mac.
2. Instala la CLI de Tuist donde se ejecuta el agente, por ejemplo en el script de configuración del entorno: `mise use -g tuist@latest`, o `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (`tuist-linux-aarch64` en ARM).
3. Autentica la CLI. El inicio de sesión del servidor MCP no se transfiere a ella, así que ejecuta `tuist auth login` como miembro de la cuenta, o establece `TUIST_TOKEN` con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write`.
4. Si el entorno restringe el acceso a la red, permite `tuist.dev`. La CLI sube archivos a la Mac a través de ella, por lo que no necesita ningún otro dominio.

El agente crea una Mac por tarea, con el [Xcode](#xcode) que el proyecto fija: `create_sandbox` enumera los Xcodes que puede elegir e indica al agente que lea la versión fijada del proyecto, como `.xcode-version`. Antes de cada comando, ejecuta `tuist sandbox sync`. Copia los archivos que Git no ignora, estén o no confirmados, y después solo los que han cambiado. Tras la primera sincronización, ejecuta `mise install` en la raíz del repositorio en la Mac, de modo que el [Tuist fijado del proyecto](#tuist-in-sandbox) esté allí, con sesión iniciada en la caché de tu cuenta. Luego, el agente ejecuta comandos como `xcodebuild` con `tuist sandbox exec`, copia resultados como capturas de pantalla o una app compilada de vuelta con `tuist sandbox cp`, y elimina la Mac cuando la tarea termina. Una Mac permanece en ejecución durante 10 minutos después de su último comando, para que la siguiente comience de inmediato; `tuist sandbox pause` la devuelve antes. Una Mac abandonada se pausa y se elimina tras 14 días pausada.

## Linux y macOS {#platforms}

Los sandboxes de **Linux** ejecutan Ubuntu 24.04:

- 2 vCPU, 4 GiB de RAM (predeterminado)
- 4 vCPU, 8 GiB de RAM
- 8 vCPU, 16 GiB de RAM

Los sandboxes de **macOS** se ejecutan en silicio de Apple con Xcode:

- 8 vCPU, 8 GiB de RAM (predeterminado)
- 8 vCPU, 16 GiB de RAM
- 8 vCPU, 24 GiB de RAM

### Elige un Xcode {#xcode}

Cada sandbox de macOS ejecuta un Xcode, que eliges al crearlo. Arranca la misma imagen que el perfil de <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> para ese Xcode, de modo que un agente compila con la misma cadena de herramientas y simuladores que tu CI. En tuist.dev, los sandboxes de macOS ofrecen actualmente:

- `26.6` (predeterminado)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Elige uno con `xcode_version` (`--xcode` en la CLI), usando la versión exacta, como hacen los perfiles de runner:

| Dónde | Cómo |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API y MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Plugin de Tuist para Mac en Amp | `tuist_mac_start` con `xcode` |
| Orbs de Amp | El tipo de orb `macos-xcode-26-1-1` (consulta <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code y Claude Managed Agents | `xcode_version` en el entorno, o por sesión de Managed Agents (consulta <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sin una versión**, una Mac recibe la predeterminada.
- **Se rechaza una versión que Tuist no ofrece**, y el error enumera las versiones que puedes elegir, para que sepas qué está disponible ahora mismo.
- **Tuist no lee el `.xcode-version` de tu repositorio.** Tú, o el agente que solicita la Mac, eliges la versión. La herramienta MCP y el plugin de Tuist para Mac indican a los agentes que coincidan con la versión que el proyecto fija.
- **Un sandbox mantiene su Xcode de por vida.** Para compilar con otro Xcode, crea un nuevo sandbox. `xcodebuild -version` muestra qué Xcode ejecuta una Mac.

## Seguridad {#security}

- Cada sandbox es su propia máquina virtual. Los sandboxes no comparten sistema de archivos, memoria ni procesos entre sí ni con trabajos de CI.
- Los sandboxes pertenecen a una cuenta, y cualquiera de sus miembros puede usarlos y gestionarlos, incluidos los sandboxes que sirven a una integración. Solo los administradores conectan integraciones. Las sesiones de una integración solo alcanzan los sandboxes de la cuenta a la que está conectada la integración.
- Las credenciales que proporcionas a Tuist para conectar una integración, como un token de proveedor de Amp o una clave de entorno de Claude, se almacenan cifradas y nunca se vuelven a mostrar.
- Un sandbox puede acceder a Internet. Trata lo que un agente pueda acceder desde él como tratarías un trabajo de CI.
