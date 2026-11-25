---
{
  "title": "Sandboxes",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Los Sandboxes de Tuist son máquinas virtuales persistentes en Linux y macOS para agentes de programación como Amp y Claude. Cada sesión del agente obtiene su propia máquina, que se pausa cuando el agente está inactivo y se reanuda con sus archivos intactos."
}
---
# Sandboxes {#sandboxes}

> [!IMPORTANT]
> **Solo con invitación**
>
> Los Sandboxes de Tuist, tanto para Linux como para macOS, están disponibles actualmente solo por invitación mientras escalamos la capacidad. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta. Los precios se anunciarán cuando los Sandboxes estén disponibles para todo el público.

Un sandbox es una máquina virtual donde un agente de programación ejecuta sus comandos y edita sus archivos. Cada sesión de agente obtiene su propio sandbox, que conserva su repositorio clonado, los productos de compilación y las herramientas instaladas durante toda la vida de la sesión. Cuando el agente queda inactivo, el sandbox se pausa; el siguiente mensaje lo reanuda desde donde lo dejó.

Los sandboxes se ejecutan en la misma flota que los <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link>, junto a la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu equipo, por lo que las compilaciones de un agente pueden utilizar los mismos artefactos en caché que tu CI y tus máquinas locales.

Puedes usar sandboxes desde:

- **<.localized_link href="/guides/features/sandboxes/amp">Amp</.localized_link>**: ejecuta los orbs de tu espacio de trabajo de Amp en Tuist, o proporciona una Mac para compilaciones de Xcode a cualquier hilo de Amp con el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin Tuist Mac</.localized_link>.
- **<.localized_link href="/guides/features/sandboxes/claude">Claude</.localized_link>**: ejecuta sesiones de Claude Managed Agents y sesiones en la nube de Claude Code (claude.ai, las aplicaciones de escritorio y móviles, y `claude --cloud`) en Tuist.
- **[La CLI de Tuist](#cli)**: crea sandboxes y ejecuta comandos en ellos desde tu terminal, o desde tus propias herramientas a través de la API.

## Comienza con la CLI {#cli}

Crea un sandbox y ejecuta comandos en él desde tu terminal con `tuist sandbox`.

### 1. Iniciar sesión {#cli-log-in}

Cualquier miembro de la cuenta puede crear y gestionar sus sandboxes:

```bash
tuist auth login
```

### 2. Crear un sandbox {#cli-create}

```bash
tuist sandbox create --platform macos
```

Omite `--platform` para Linux. Pasa `--xcode` con una versión, como `--xcode 26.1.1`, para una Mac con esa [Xcode](#xcode); esto implica `--platform macos`. Pasa `--vcpus` con `--memory-gb` para una [forma](#platforms) mayor, `--guaranteed-vcpus` para garantizar a un sandbox de Linux más [CPU](#guaranteed-cpu), y `--workspace-gb` para un disco más grande. El sandbox se ejecuta durante dos horas desde su creación, y nuevamente desde cada reanudación; pasa `--lifetime-minutes` para un tiempo entre 5 minutos y un día. Cuando su vida útil termina, sus comandos en ejecución se cancelan y se pausa y archiva, conservando sus archivos, por lo que un sandbox olvidado deja de usar la capacidad de tu cuenta. El comando retorna una vez que el sandbox está en ejecución e imprime sus detalles, incluido su ID. Cuando todos los hosts están ocupados, como cuando trabajos de CI retienen las Macs compartidas, el servidor espera 25 segundos por uno antes de que la creación falle con `fleet_busy`; pasa `--wait-timeout 5m` para seguir intentándolo hasta por 5 minutos (como máximo una hora), con la razón repetida en stderr aproximadamente una vez por minuto. Usa la cuenta del proyecto Tuist en el directorio actual; pasa `--account` para elegir otra.

### 3. Ejecutar comandos {#cli-exec}

```bash
tuist sandbox exec <sandbox-id> -- xcodebuild -version
```

El comando se ejecuta con `bash -l` en el sandbox, que primero se reanuda si estaba pausado. `tuist` transmite su salida durante todo el tiempo que dure la ejecución y sale con el estado del comando; Ctrl-C lo cancela en el sandbox. Pasa `--cwd`, `--env NAME=VALUE` y `--timeout` (hasta seis horas) según sea necesario.

El comando se ejecuta desvinculado de `tuist`, por lo que sobrevive a una conexión perdida. Para ajustar una compilación larga a una llamada de herramienta con límite de tiempo, como la de un agente, pasa `--wait <seconds>`: cuando este tiempo expire primero, `tuist` deja el comando ejecutándose, sale con el código 75 e imprime el comando `tuist sandbox exec <sandbox-id> --attach <command-id> --stdout-offset … --stderr-offset …` que continúa su salida desde donde se detuvo y sale con el estado del comando.

### Tareas comunes {#cli-tasks}

| Tarea | Comando |
| --- | --- |
| Listar sandboxes | `tuist sandbox list` |
| Mostrar uno | `tuist sandbox show <id>` |
| Pausar o reanudar | `tuist sandbox pause <id>`, `tuist sandbox resume <id>` |
| Mantenerlo en ejecución después de su vencimiento | `tuist sandbox extend <id> --lifetime-minutes 240` |
| Sincronizar los archivos del árbol de trabajo local de Git en él | `tuist sandbox sync <id>` |
| Capturar pantalla del Simulador de iOS iniciado o de toda la pantalla de un sandbox macOS | `tuist sandbox screenshot <id> --out shot.png`, `tuist sandbox screenshot <id> --screen --out screen.png` |
| Copiar archivos hacia fuera o hacia dentro | `tuist sandbox cp <id>:<path> <local-path>`, `tuist sandbox cp <local-path> <id>:<path>` |
| Eliminar | `tuist sandbox delete <id> --yes` |
| Ver uso | `tuist sandbox analytics` |

Añade `--json` para obtener una salida legible por máquina. Consulta la <.localized_link href="/cli/sandbox">referencia de la CLI</.localized_link> para ver todas las opciones. Para controlar sandboxes desde código en su lugar, usa las mismas operaciones a través de la [API de Tuist](https://tuist.dev/api/docs) bajo `/api/accounts/{account_handle}/sandboxes`, o permite que un agente las use a través de <.localized_link href="/guides/features/agentic-coding/mcp">MCP</.localized_link>.

Las herramientas que no pueden iniciar sesión de forma interactiva, como un plugin de agente que compila en un sandbox macOS, pueden autenticarse con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write` en su lugar. Puede hacer lo que un miembro de la cuenta puede: crear sandboxes, ejecutar comandos en ellos, y pausarlos, reanudarlos, archivarlos y eliminarlos. La configuración de integraciones, y la ejecución de comandos en sandboxes que sirven a una integración, quedan reservadas a los administradores de la cuenta.

### Tuist dentro del sandbox {#tuist-in-sandbox}

Los sandboxes macOS vienen con la CLI de Tuist. Cuando tu proyecto fija Tuist mediante mise (`mise.toml` o `.tool-versions`), `tuist` ejecuta esa versión en su lugar, instalada la primera vez que un comando la necesita. Cada comando que inicias con `tuist sandbox exec` tiene los shims de mise (`$HOME/.local/share/mise/shims`) primero en `PATH` y el Tuist de la imagen al final, por lo que `tuist` y tus otras herramientas de mise se ejecutan en tus comandos y en las fases de compilación de Xcode, como las post-actions de un esquema. Cada Mac también incluye una guía para agentes de programación en `/opt/tuist/agent-guide.md`, generada a partir de su imagen: su Xcode y simuladores, dónde está el repositorio y qué contiene una instantánea lista. Claude Code, Codex y Amp ejecutándose en la Mac la encuentran desde sus archivos de instrucciones.

Cada comando que inicias con `tuist sandbox exec` también recibe lo que recibe un runner de Tuist, por lo que las compilaciones en el sandbox usan la <.localized_link href="/guides/features/cache">caché</.localized_link> de tu cuenta sin que tengas que pasar credenciales:

- `TUIST_URL` y, donde el host del sandbox pueda alcanzarlo, como en macOS, el `TUIST_CACHE_ENDPOINT` de la caché en el mismo rack.
- `TUIST_OIDC_TOKEN`, un token de identidad de corta duración para ese comando. Tuist CLI 4.218.0 y versiones posteriores inician sesión con él automáticamente; con las versiones 4.215.0 a 4.217.x, ejecuta `tuist auth login` primero en el mismo comando.

El token se emite para cada comando y solo puede intercambiarse por un token de Tuist mientras ese comando se ejecuta, por lo que un sandbox nunca almacena una credencial de larga duración. Nunca otorga más permisos de los que la persona o el token que inició el comando tiene sobre la caché: los miembros de una cuenta cuyos tokens de caché solo tienen permiso de escritura obtienen acceso de lectura, y un token de cuenta necesita ámbitos de caché, como `ci`, junto con `account:sandboxes:write` para que el sandbox pueda usar la caché. Las variables que pasas con `--env` tienen prioridad.

## Compilar en una Mac desde un agente de programación {#coding-agents}

Un agente de programación que se ejecuta en Linux, como una sesión de agente en la nube, puede compilar, probar y ejecutar código para plataformas Apple en un sandbox macOS mientras sigue editando archivos donde se ejecuta. En Amp, instala el <.localized_link href="/guides/features/sandboxes/amp#remote-mac">plugin Tuist Mac</.localized_link>. Para otros agentes, como Claude Code o Cursor:

1. Conecta el agente al <.localized_link href="/guides/features/agentic-coding/mcp">servidor MCP</.localized_link> de Tuist. Su herramienta `create_sandbox` indica al agente cómo controlar la Mac.
2. Instala la CLI de Tuist donde se ejecuta el agente, por ejemplo en el script de configuración del entorno: `mise use -g tuist@latest`, o `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist` (`tuist-linux-aarch64` en ARM).
3. Autentica la CLI. El inicio de sesión del servidor MCP no se transfiere a ella, así que ejecuta `tuist auth login` como miembro de la cuenta o establece `TUIST_TOKEN` con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> que tenga el ámbito `account:sandboxes:write`.
4. Si el entorno restringe el acceso a la red, permite `tuist.dev`. La CLI sube archivos a la Mac a través de él, por lo que no necesita ningún otro dominio.
5. Opcionalmente, permite que el agente cree y elimine Macs sin preguntar cada vez. Los agentes preguntan antes de llamar a `create_sandbox` porque una Mac cuenta para los límites de tu cuenta, y antes de `delete_sandbox` porque no se puede deshacer. En Claude Code, permite ambas acciones en `.claude/settings.json`, usando el nombre con el que registraste el servidor MCP (aquí `tuist`):

   ```json
   {
     "permissions": {
       "allow": ["mcp__tuist__create_sandbox", "mcp__tuist__delete_sandbox"]
     }
   }
   ```

Para que el agente realice la configuración, dale este prompt:

```text
Set up this environment so you can build and test this project on a Tuist macOS sandbox.

Read https://tuist.dev/en/docs/guides/features/sandboxes#coding-agents and follow its "Build on a Mac from a coding agent" section. It's the current Tuist guide for this, so prefer it over anything you remember about Tuist.

You're done when you have created a Mac with create_sandbox, synced this repository to it with tuist sandbox sync, run the project's build there with tuist sandbox exec, and deleted the Mac.

Ask me before anything that needs my login or approval, such as tuist auth login. If a step fails or is blocked, stop and tell me which step you reached and the exact error, without secrets.
```

El agente crea una Mac por tarea, con la versión de [Xcode](#xcode) que el proyecto fija: `create_sandbox` enumera las versiones de Xcode disponibles e indica al agente que lea la versión fijada del proyecto, como `.xcode-version`. Antes de cada comando, ejecuta `tuist sandbox sync`. Copia los archivos que Git no ignora, estén confirmados o no, y después solo los que hayan cambiado. La Mac ya tiene [Tuist](#tuist-in-sandbox), la versión fijada del proyecto si hay una, iniciada sesión en la caché de tu cuenta, y el agente lee la guía de la Mac una vez. Luego, el agente ejecuta comandos como `xcodebuild` con `tuist sandbox exec`, lanza la app en el Simulator y te la muestra con `get_sandbox_screenshot` del servidor MCP o con `tuist sandbox screenshot`, copia los resultados, como una app compilada, de vuelta con `tuist sandbox cp`, y elimina la Mac cuando la tarea termina. Una Mac permanece en ejecución durante 10 minutos después de su último comando, para que la siguiente comience de inmediato; `tuist sandbox pause` la devuelve antes. Una Mac abandonada se pausa, se archiva cuando termina su vida útil de dos horas y se elimina después de 14 días; el agente extiende la vida útil antes de una compilación larga.

## Linux y macOS {#platforms}

Los sandboxes **Linux** ejecutan Ubuntu 24.04. Cada sandbox Linux tiene 16 vCPUs y aprovecha los núcleos inactivos de la máquina en la que se ejecuta, por lo que su forma determina su memoria:

- 2 GiB de RAM (`--vcpus 1 --memory-gb 2`)
- 4 GiB de RAM (`--vcpus 2 --memory-gb 4`, predeterminado)
- 8 GiB de RAM (`--vcpus 4 --memory-gb 8`)
- 16 GiB de RAM (`--vcpus 8 --memory-gb 16`)
- 32 GiB de RAM (`--vcpus 16 --memory-gb 32`)
- 44 GiB de RAM (`--vcpus 16 --memory-gb 44`)

Los sandboxes **macOS** se ejecutan en silicona Apple con Xcode:

- 8 vCPU, 8 GiB de RAM (predeterminado)
- 8 vCPU, 16 GiB de RAM
- 8 vCPU, 24 GiB de RAM

### CPU garantizada {#guaranteed-cpu}

Un sandbox Linux tiene garantizado un cuarto de vCPU por GiB de su memoria, como 2 vCPUs para 8 GiB, y utiliza tantos más como núcleos inactivos tenga la máquina, hasta sus 16 vCPUs. Esto es ideal para un agente, que mayormente espera y luego compila en ráfagas. Cuando una compilación necesita más CPU constante incluso en una máquina ocupada, garantiza 1, 2, 4 u 8 vCPUs al crear el sandbox; obtendrá el mayor valor entre esa garantía y la garantía de su memoria:

| Dónde | Cómo |
| --- | --- |
| CLI | `tuist sandbox create --guaranteed-vcpus 4` |
| API y MCP `create_sandbox` | `"guaranteed_vcpus": 4` |

- **Una garantía es un mínimo, no un límite.** Un sandbox con 4 vCPUs garantizadas sigue aprovechando hasta 16 cuando hay núcleos inactivos. Bajo contención, cada sandbox recibe CPU en proporción a su garantía.
- **Se factura como un mínimo.** Un sandbox en ejecución se factura por la CPU que usa, pero nunca por menos de su garantía.
- **Un sandbox mantiene su garantía de por vida.** Para cambiarla, crea un nuevo sandbox.
- **Los sandboxes macOS siempre tienen toda su forma**, por lo que no requieren una garantía.

### Elegir una versión de Xcode {#xcode}

Cada sandbox macOS ejecuta una versión de Xcode, que eliges al crearlo. Arranca la misma imagen que el perfil de <.localized_link href="/guides/features/runners">Tuist Runners</.localized_link> para ese Xcode, por lo que un agente compila con la misma cadena de herramientas y simuladores que tu CI. En tuist.dev, los sandboxes macOS ofrecen actualmente:

- `26.6` (predeterminado)
- `26.1.1`
- `27.0`
- `27.1`
- `27.2`

Elige una con `xcode_version` (`--xcode` en la CLI), usando la versión exacta, como hacen los perfiles de runner:

| Dónde | Cómo |
| --- | --- |
| CLI | `tuist sandbox create --xcode 26.1.1` |
| API y MCP `create_sandbox` | `"xcode_version": "26.1.1"` |
| Plugin Tuist Mac para Amp | `tuist_mac_start` con `xcode` |
| Orbs de Amp | El tipo de orb `macos-xcode-26-1-1` (consulta <.localized_link href="/guides/features/sandboxes/amp#xcode">Amp</.localized_link>) |
| Claude Code y Claude Managed Agents | `xcode_version` en el entorno, o por sesión de Managed Agents (consulta <.localized_link href="/guides/features/sandboxes/claude#xcode">Claude</.localized_link>) |

- **Sin una versión**, un Mac obtiene la predeterminada.
- **Se rechaza una versión que Tuist no ofrece**, y el error enumera las versiones que puedes elegir, para que sepas qué hay disponible ahora mismo.
- **Tuist no lee el `.xcode-version` de tu repositorio.** Tú, o el agente que solicita el Mac, eliges la versión. La herramienta MCP y el plugin Tuist Mac indican a los agentes que coincidan con la versión que fija el proyecto.
- **Un sandbox mantiene su Xcode de por vida.** Para compilar con otro Xcode, crea un nuevo sandbox. `xcodebuild -version` muestra qué Xcode ejecuta un Mac.

## Seguridad {#security}

- Cada sandbox es su propia máquina virtual. Los sandboxes no comparten sistema de archivos, memoria ni procesos entre sí ni con trabajos de CI.
- Los sandboxes pertenecen a una cuenta y cualquiera de sus miembros puede usarlos y gestionarlos. Los sandboxes que atienden una integración, como un orb de Amp o una sesión de Claude Code, contienen el trabajo y las credenciales de esa sesión: los miembros pueden verlos, pausarlos, reanudarlos, archivarlos y eliminarlos, pero solo los administradores pueden ejecutar comandos en ellos o subirles archivos. Solo los administradores conectan integraciones. Las sesiones de una integración solo acceden a los sandboxes de la cuenta a la que está conectada la integración.
- Las credenciales que proporcionas a Tuist para conectar una integración, como un token de proveedor de Amp o una clave de entorno de Claude, se almacenan cifradas y nunca se vuelven a mostrar.
- Un sandbox puede acceder a Internet. Trata lo que un agente pueda acceder desde él como tratarías un trabajo de CI.
