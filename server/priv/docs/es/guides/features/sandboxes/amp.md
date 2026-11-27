---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta los orbs de tu espacio de trabajo de Amp en Tuist Sandboxes, en Linux o macOS, o proporciona un Mac a cualquier hilo de Amp para compilaciones de Xcode con el plugin Tuist Mac."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Solo por invitación**
>
> Los entornos aislados (sandboxes) de Tuist, tanto en Linux como en macOS, están disponibles actualmente solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

[Amp](https://ampcode.com) ejecuta las herramientas de cada hilo en un [orb](https://ampcode.com/docs/orbs), una máquina con el repositorio del hilo clonado. Tuist puede ser el [proveedor de orbs autoalojado](https://ampcode.com/docs/orbs/self-hosted) de tu espacio de trabajo de Amp: cada hilo que lo seleccione se ejecutará en su propio <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> de Tuist, en Linux o macOS. No necesitas ejecutar ni alojar nada tú mismo.

Para mantener tus hilos en sus orbs actuales y compilar, probar y ejecutar código para plataformas Apple únicamente en un Mac, utiliza el [plugin Tuist Mac](#remote-mac) en su lugar.

## Conectar Amp {#connect}

Debes ser administrador tanto del espacio de trabajo de Amp como de la cuenta de Tuist.

1. En Amp, abre la sección **Settings → Orbs** de tu espacio de trabajo, haz clic en **Add Orb Provider** y asígnale un nombre, por ejemplo `tuist`. Los miembros seleccionan el proveedor por este nombre. Copia el token `aop_live_…`; Amp lo muestra solo una vez.
2. En el diálogo de **Edit** del proveedor en Amp, añade los **tipos de orb** que quieras ofrecer y elige el predeterminado. Los tipos de Linux coinciden con la memoria de los [orbs propios de Amp](https://ampcode.com/docs/orbs/sizes-and-costs). A cada uno se le garantiza un cuarto de vCPU por GiB de memoria y puede alcanzar picos de 16 vCPUs cuando la máquina tiene núcleos inactivos (consulta <.localized_link href="/guides/features/sandboxes#guaranteed-cpu">CPU garantizada</.localized_link>):

   | Tipo | Configuración |
   | --- | --- |
   | `linux` | Linux, 8 GiB de RAM, 2 vCPUs garantizadas |
   | `linux-tiny` | Linux, 2 GiB de RAM, 0.5 vCPUs garantizadas |
   | `linux-small` | Linux, 4 GiB de RAM, 1 vCPU garantizada |
   | `linux-medium` | Igual que `linux` |
   | `linux-large` | Linux, 16 GiB de RAM, 4 vCPUs garantizadas |
   | `linux-xxlarge` | Linux, 32 GiB de RAM, 8 vCPUs garantizadas |
   | `linux-3xlarge` | Linux, 44 GiB de RAM, 11 vCPUs garantizadas |
   | `macos` | macOS con la versión predeterminada de Xcode, 8 vCPUs, 8 GiB de RAM |
   | `macos-xcode-<version>` | macOS con esa [Xcode](#xcode), 8 vCPUs, 8 GiB de RAM |

   Los tipos de Linux tienen un espacio de trabajo de 10 GB, los de macOS de 30 GB.

3. En Tuist, abre **Sandboxes** en el panel de control de tu cuenta, haz clic en **Connect** en la tarjeta de Amp y pega el token.

La tarjeta muestra **Connected** una vez que Tuist está atendiendo al proveedor. Una cuenta de Tuist atiende a un único proveedor. Cualquier persona que pueda usar el proveedor en Amp ejecuta orbs bajo la cuenta de Tuist conectada, que es la que recibe los cargos. Para detenerlo, haz clic en **Disconnect** en la tarjeta o desactiva el proveedor en Amp.

## Iniciar un hilo {#start-a-thread}

En el compositor de nuevos hilos de Amp, haz clic en **Orb**, elige el proveedor de Tuist bajo **Self-Hosted** y selecciona un tipo, como `linux-small` para un repositorio que necesite menos recursos que `linux`, o `linux-large` para uno que necesite más. Desde la CLI de Amp:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Un hilo mantiene su tipo de orb durante toda su vida útil. Sin un tipo definido, obtiene el predeterminado del proveedor. Para usar un mismo tipo en cada nuevo hilo, elige el proveedor y su tipo bajo **Default Orb** en la sección **Settings → Orbs** de Amp.

### Elegir una versión de Xcode {#xcode}

`macos` ejecuta la versión predeterminada de <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link>. Para usar otra, añade un tipo de orb con su nombre, sustituyendo los puntos por guiones: `macos-xcode-26-1-1` ejecuta Xcode 26.1.1, `macos-xcode-27-0` Xcode 27.0. Añade uno por cada versión de Xcode que fijen tus repositorios y selecciónalo por hilo como cualquier otro tipo:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos-xcode-26-1-1
```

Un tipo para una versión de Xcode que Tuist no ofrece fallará al iniciar un nuevo orb. Un orb que ya se haya iniciado con él seguirá reanudándose aunque Tuist deje de ofrecer esa versión de Xcode.

Amp clona el repositorio, ejecuta tu script `.agents/setup` y configura las credenciales de Git, como hace con cada orb. Cada orb también puede leer la <.localized_link href="/guides/features/cache">caché</.localized_link> de Tuist de tu cuenta.

## Pausa y retención {#retention}

Cuando un hilo queda inactivo, Amp pausa su orb. El siguiente mensaje lo reanuda con sus archivos intactos.

- **Linux:** Los procesos en ejecución sobreviven a una pausa. Un orb que ha estado pausado durante mucho tiempo se mueve al almacenamiento de archivo y se restaura con el siguiente mensaje, sin sus procesos. Los orbs de Linux conservan sus archivos hasta que Amp elimina el orb del hilo.
- **macOS:** Un orb pausado, o en estado de error, durante 7 días se elimina. El siguiente mensaje del hilo inicia un orb nuevo y Amp vuelve a ejecutar `.agents/setup`. El primer orb de macOS en una máquina instala la CLI de Amp, por lo que puede tardar hasta dos minutos en iniciarse.

Un orb que permanece inactivo sin que Amp lo pause, por ejemplo porque nunca llegó la orden de pausa, se pausa después de diez minutos con un uso de CPU casi nulo.

## Usar un Mac desde cualquier hilo de Amp {#remote-mac}

El plugin Tuist Mac proporciona a un hilo de Amp un sandbox de macOS con Xcode, los simuladores de iOS y Homebrew, mientras el hilo sigue ejecutándose donde estaba, por ejemplo en uno de los orbs de Linux propios de Amp. Pide a Amp que realice el trabajo y este iniciará un Mac cuando lo necesite:

> Añade un interruptor de modo oscuro a la pantalla de ajustes, ejecuta la app en el simulador de iOS y muéstrame una captura de pantalla.

Amp sigue editando el código donde se ejecuta. Antes de cada comando en el Mac, el plugin ejecuta `tuist sandbox sync`, que copia los archivos que Git no ignora, estén confirmados o no, y después solo los que han cambiado. Los productos de compilación y otros archivos ignorados que crea el Mac permanecen allí, por lo que las compilaciones siguen siendo incrementales. El plugin añade estas herramientas y una habilidad `remote-mac` que indica a Amp cuándo y cómo usarlas:

| Herramienta | Qué hace |
| --- | --- |
| `tuist_mac_start` | Crea el Mac del hilo, o lo reutiliza, y sincroniza |
| `tuist_mac_shell` | Sincroniza y luego ejecuta un comando en el Mac |
| `tuist_mac_screenshot` | Muestra el simulador o la pantalla en el hilo |
| `tuist_mac_download` | Copia un archivo de vuelta, como una `.app`.app compilada |
| `tuist_mac_stop` | Elimina el Mac del hilo |

El Mac tiene la CLI de Tuist y ejecuta la versión propia del proyecto cuando se fija una mediante mise; `tuist_mac_shell` coloca los shims de mise al principio de `PATH`. Cada comando en el Mac <.localized_link href="/guides/features/sandboxes#tuist-in-sandbox">inicia sesión en la caché de tu cuenta</.localized_link> por su cuenta con Tuist 4.218.0 o posterior; con las versiones 4.215.0 a 4.217.x, Amp ejecuta primero `tuist auth login`.

Un hilo utiliza un solo Mac. Amp pasa a `tuist_mac_start` la versión de <.localized_link href="/guides/features/sandboxes#xcode">Xcode</.localized_link> que fija el repositorio, por ejemplo en `.xcode-version`, o puedes solicitar una ("usa Xcode 26.1.1"); si no se especifica, el Mac ejecuta la predeterminada. El Mac conserva su Xcode, por lo que cambiarlo implica detenerlo e iniciar otro. Tuist lo pausa cuando está inactivo y el siguiente comando lo reanuda. Amp lo elimina cuando la tarea ha finalizado; un Mac abandonado se elimina tras 14 días pausado. Los Macs cuentan para tu cuenta de Tuist como cualquier otro sandbox.

### Configurarlo {#remote-mac-setup}

1. **Instala el plugin.** Es un único archivo, [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Para que esté disponible para todos en tu espacio de trabajo de Amp, un administrador del espacio le pide a Amp en un hilo:

   > Añade https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts a los plugins de nuestro espacio de trabajo.

   Amp lo confirma en el [repositorio de plugins](https://ampcode.com/docs/customize/global-plugins-and-skills) del espacio de trabajo y pregunta antes de enviarlo. Pide "mis plugins personales" en su lugar para instalarlo solo para ti, o guarda el archivo como `.amp/plugins/tuist-mac.ts` en un repositorio para usarlo solo allí. El plugin es una copia: para actualizarlo, pide a Amp que lo reemplace con la última versión desde la misma URL.
2. **Instala la CLI de Tuist** donde se ejecute Amp. En los orbs, añádela al script [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) del repositorio, por ejemplo `mise use -g tuist@latest`, o `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **Permite que la CLI use los sandboxes de tu cuenta.** En los orbs, conecta tu espacio de trabajo de Amp a tu cuenta de Tuist como se describe en <.localized_link href="/guides/server/authentication#amp-orbs">Orbs de Amp</.localized_link>. Los orbs inician sesión por sí mismos, con acceso a los sandboxes. En otros entornos, como la CLI de Amp en una máquina Linux, ejecuta `tuist auth login` como miembro de la cuenta, o establece `TUIST_MAC_TOKEN` con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write`, más `ci` para que el Mac use la caché. El plugin pasa `TUIST_MAC_TOKEN` a la CLI en lugar de `TUIST_TOKEN`, así que establécelo también cuando tus orbs ya tengan un `TUIST_TOKEN` sin ese ámbito.
4. **Indica qué cuenta debe usar**, si el repositorio no tiene un `tuist.toml` con `project = "<account>/<project>"`. En Linux, la CLI no puede leer la cuenta desde `Tuist.swift`. Establece `TUIST_MAC_ACCOUNT` con el identificador de tu cuenta en las variables de entorno de tu proyecto de Amp. Sin ello, Amp pasa la cuenta desde el `fullHandle` de `Tuist.swift` a `tuist_mac_start`.

La CLI alcanza el Mac solo a través de `tuist.dev`, por lo que un entorno que restrinja el acceso a la red debe permitir solo ese dominio. Para usar una CLI que no esté en `PATH`, establece `TUIST_MAC_CLI` con su ruta.

Los agentes que no admiten plugins de Amp, como Claude Code o Cursor, pueden hacer lo mismo a través del servidor MCP de Tuist y la CLI, como se describe en <.localized_link href="/guides/features/sandboxes#coding-agents">Compilar en un Mac desde un agente de programación</.localized_link>.

### Usar Macs de Tuist en lugar de los Satélites macOS de Amp {#remote-mac-satellites}

Amp también tiene sus propios Macs en la nube, los [Satélites macOS](https://ampcode.com/docs/orbs/mac), en beta para espacios de trabajo que se unieron a su lista de espera. Cuando un hilo puede iniciar ambos, las instrucciones integradas de Amp envían el trabajo de macOS a sus satélites, por lo que rara vez elige el plugin. Para que los hilos usen Macs de Tuist, haz una de estas cosas:

- **Desactiva los Satélites macOS para ti.** Cada miembro los desactiva bajo **Satélites Mac** en [Configuración → Funcionalidades experimentales](https://ampcode.com/settings/experimental-features) de Amp.
- **Desactívalos para el espacio de trabajo.** Cuando los orbs de tu espacio de trabajo [se ejecutan en Tuist](#connect), un administrador del espacio puede establecer **Dónde se ejecutan los Orbs** como **Solo autoalojado** en la configuración del espacio de trabajo de Amp, bajo **Orbs**. Los agentes entonces no pueden iniciar satélites alojados por Amp, pero los miembros tampoco pueden usar los orbs integrados de Amp, así que haz esto solo cuando todos tus hilos se ejecuten en tus propios proveedores de orbs.
- **Solicita Macs de Tuist.** Añade "Usa las herramientas `tuist_mac_*` para el trabajo en macOS, no los Satélites macOS." al prompt, o a la guía de agentes de tu espacio de trabajo en la configuración del espacio de trabajo de Amp para que cada hilo la siga.
