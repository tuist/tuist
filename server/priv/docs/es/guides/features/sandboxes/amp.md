---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta los orbs de tu espacio de trabajo de Amp en Tuist Sandboxes, en Linux o macOS, o proporciona un Mac a cualquier hilo de Amp para compilaciones de Xcode con el complemento Tuist Mac."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Solo con invitación**
>
> Los sandboxes de Tuist, tanto en Linux como en macOS, están disponibles solo con invitación. [Contacta con nosotros](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

[Amp](https://ampcode.com) ejecuta las herramientas de cada hilo en un [orb](https://ampcode.com/docs/orbs), una máquina con el repositorio del hilo descargado. Tuist puede ser el [proveedor de orbs autoalojado](https://ampcode.com/docs/orbs/self-hosted) de tu espacio de trabajo de Amp: cada hilo que lo seleccione se ejecutará en su propio <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> de Tuist, en Linux o macOS. No necesitas ejecutar ni alojar nada por tu cuenta.

Para mantener tus hilos en sus orbs actuales y compilar, probar y ejecutar código para plataformas de Apple únicamente en un Mac, utiliza el [plugin Tuist Mac](#remote-mac).

## Conectar Amp {#connect}

Debes ser administrador tanto del espacio de trabajo de Amp como de la cuenta de Tuist.

1. En Amp, abre la sección **Settings → Orbs** de tu espacio de trabajo, haz clic en **Add Orb Provider** y asígnale un nombre, por ejemplo `tuist`. Los miembros seleccionan el proveedor por este nombre. Copia el token `aop_live_…`; Amp lo muestra solo una vez.
2. En el diálogo **Edit** del proveedor en Amp, añade los **tipos de orb** que quieras ofrecer y elige el predeterminado. Los tipos de Linux coinciden con los tamaños de los [orbs propios de Amp](https://ampcode.com/docs/orbs/sizes-and-costs):

   | Tipo | Plataforma | Configuración |
   | --- | --- | --- |
   | `linux` | Linux | 4 vCPU, 8 GiB de RAM, 10 GB de espacio de trabajo |
   | `linux-tiny` | Linux | 1 vCPU, 2 GiB de RAM, 10 GB de espacio de trabajo |
   | `linux-small` | Linux | 2 vCPU, 4 GiB de RAM, 10 GB de espacio de trabajo |
   | `linux-medium` | Linux | 4 vCPU, 8 GiB de RAM, 10 GB de espacio de trabajo (igual que `linux`) |
   | `linux-large` | Linux | 8 vCPU, 16 GiB de RAM, 10 GB de espacio de trabajo |
   | `linux-xxlarge` | Linux | 16 vCPU, 32 GiB de RAM, 10 GB de espacio de trabajo |
   | `linux-3xlarge` | Linux | 16 vCPU, 44 GiB de RAM, 10 GB de espacio de trabajo |
   | `macos` | macOS con Xcode | 8 vCPU, 8 GiB de RAM, 10 GB de espacio de trabajo |

3. En Tuist, abre **Sandboxes** en el panel de control de tu cuenta, haz clic en **Connect** en la tarjeta de Amp y pega el token.

La tarjeta mostrará **Connected** cuando Tuist esté sirviendo al proveedor. Una cuenta de Tuist sirve a un único proveedor. Cualquier persona que pueda usar el proveedor en Amp ejecutará orbs que se cargarán a la cuenta de Tuist conectada. Para detenerlo, haz clic en **Disconnect** en la tarjeta o desactiva el proveedor en Amp.

## Iniciar un hilo {#start-a-thread}

En el compositor de nuevos hilos de Amp, haz clic en **Orb**, elige el proveedor de Tuist bajo **Self-Hosted** y selecciona un tipo, como `linux-small` para un repositorio que necesite menos recursos que `linux`, o `linux-large` para uno que necesite más. Desde la CLI de Amp:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Un hilo mantiene su tipo de orb durante toda su vida útil. Sin un tipo definido, recibe el predeterminado del proveedor. Para usar un mismo tipo para cada nuevo hilo, elige el proveedor y su tipo bajo **Default Orb** en la sección **Settings → Orbs** de Amp.

Amp clona el repositorio, ejecuta tu script `.agents/setup` y configura las credenciales de Git, como hace con cada orb. Cada orb también puede leer la <.localized_link href="/guides/features/cache">caché</.localized_link> de Tuist de tu cuenta.

## Pausa y retención {#retention}

Cuando un hilo queda inactivo, Amp pausa su orb. El siguiente mensaje lo reanuda con sus archivos intactos.

- **Linux:** Los procesos en ejecución sobreviven a una pausa. Un orb que ha estado pausado durante mucho tiempo se mueve al almacenamiento de archivo y se restaura con el siguiente mensaje, sin sus procesos. Los orbs de Linux conservan sus archivos hasta que Amp elimina el orb del hilo.
- **macOS:** Un orb pausado, o en estado de error, durante 7 días se elimina. El siguiente mensaje del hilo inicia un orb nuevo y Amp vuelve a ejecutar `.agents/setup`. El primer orb de macOS en una máquina instala la CLI de Amp, por lo que puede tardar hasta dos minutos en iniciarse.

Un orb que permanece inactivo sin que Amp lo pause, por ejemplo porque nunca llegó una pausa, se pausa después de diez minutos con casi ningún uso de CPU.

## Usar un Mac desde cualquier hilo de Amp {#remote-mac}

El plugin Tuist Mac proporciona a un hilo de Amp un sandbox de macOS con Xcode, los simuladores de iOS y Homebrew mientras el hilo sigue ejecutándose donde está, por ejemplo en uno de los orbs Linux propios de Amp. Pídele el trabajo a Amp y este iniciará un Mac cuando lo necesite:

> Añade un interruptor de modo oscuro a la pantalla de ajustes, ejecuta la app en el Simulador de iOS y muéstrame una captura de pantalla.

Amp sigue editando el código donde se ejecuta. Antes de cada comando en el Mac, el plugin ejecuta `tuist sandbox sync`, que copia los archivos que Git no ignora, estén o no confirmados, y después solo los que hayan cambiado. Los productos de compilación y otros archivos ignorados que crea el Mac permanecen allí, por lo que las compilaciones siguen siendo incrementales. El plugin añade estas herramientas y una habilidad `remote-mac` que indica a Amp cuándo y cómo usarlas:

| Herramienta | Qué hace |
| --- | --- |
| `tuist_mac_start` | Crea el Mac del hilo, o lo reutiliza, y sincroniza |
| `tuist_mac_shell` | Sincroniza y luego ejecuta un comando en el Mac |
| `tuist_mac_screenshot` | Muestra el simulador o la pantalla en el hilo |
| `tuist_mac_download` | Copia un archivo de vuelta, como una `.app` compilada |
| `tuist_mac_stop` | Elimina el Mac del hilo |

Un hilo usa un único Mac. Tuist lo pausa cuando está inactivo y el siguiente comando lo reanuda. Amp lo elimina cuando la tarea está completada; un Mac abandonado se elimina tras 14 días pausado. Los Macs cuentan para tu cuenta de Tuist como cualquier otro sandbox.

### Configurarlo {#remote-mac-setup}

1. **Instala el plugin.** Es un único archivo, [`tuist-mac.ts`](https://github.com/tuist/tuist/blob/main/.amp/plugins/tuist-mac.ts). Para hacerlo disponible para todos en tu espacio de trabajo de Amp, un administrador del espacio le pide a Amp en un hilo:

   > Añade https://raw.githubusercontent.com/tuist/tuist/main/.amp/plugins/tuist-mac.ts a los plugins de nuestro espacio de trabajo.

   Amp lo confirma en el [repositorio de plugins](https://ampcode.com/docs/customize/global-plugins-and-skills) del espacio de trabajo y pregunta antes de enviarlo. Pide "mis plugins personales" para instalarlo solo para ti, o guarda el archivo como `.amp/plugins/tuist-mac.ts` en un repositorio para usarlo solo allí. El plugin es una copia: para actualizarlo, pide a Amp que lo reemplace con la última versión desde la misma URL.
2. **Instala la CLI de Tuist** donde se ejecute Amp. En los orbs, añádela al script [`.agents/setup`](https://ampcode.com/docs/orbs/customizing) del repositorio, por ejemplo `mise use -g tuist@latest`, o `curl -fsSL https://github.com/tuist/tuist/releases/download/<version>/tuist-linux-x86_64.tar.gz | tar -xz -C /usr/local/bin tuist`.
3. **Permite que la CLI use los sandboxes de tu cuenta.** En los orbs, conecta tu espacio de trabajo de Amp a tu cuenta de Tuist como se describe en <.localized_link href="/guides/server/authentication#amp-orbs">Orbs de Amp</.localized_link>. Los orbs inician sesión por sí mismos, con acceso a los sandboxes. En otros lugares, como la CLI de Amp en una máquina Linux, ejecuta `tuist auth login` como miembro de la cuenta, o establece `TUIST_MAC_TOKEN` con un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link> con el ámbito `account:sandboxes:write`. El plugin pasa `TUIST_MAC_TOKEN` a la CLI en lugar de `TUIST_TOKEN`, así que configúralo también cuando tus orbs ya tengan un `TUIST_TOKEN` sin ese ámbito.
4. **Indícale qué cuenta usar**, si el repositorio no tiene un `tuist.toml` con `project = "<account>/<project>"`. En Linux, la CLI no puede leer la cuenta desde `Tuist.swift`. Establece `TUIST_MAC_ACCOUNT` con el identificador de tu cuenta en las variables de entorno de tu proyecto de Amp. Sin ello, Amp pasa la cuenta desde el `fullHandle` de `Tuist.swift` a `tuist_mac_start`.

La CLI accede al Mac solo a través de `tuist.dev`, por lo que un entorno que restrinja el acceso a la red debe permitir solo ese dominio. Para usar una CLI que no esté en `PATH`, establece `TUIST_MAC_CLI` con su ruta.

Los agentes que no admiten plugins de Amp, como Claude Code o Cursor, pueden hacer lo mismo a través del servidor MCP de Tuist y la CLI, como se describe en <.localized_link href="/guides/features/sandboxes#coding-agents">Compilar en un Mac desde un agente de programación</.localized_link>.

### Usar Macs de Tuist en lugar de los Satélites macOS de Amp {#remote-mac-satellites}

Amp también tiene sus propios Macs en la nube, [Satélites macOS](https://ampcode.com/docs/orbs/mac), en beta para espacios de trabajo que se unieron a su lista de espera. Cuando un hilo puede iniciar ambos, las instrucciones integradas de Amp envían el trabajo de macOS a sus satélites, por lo que rara vez elige el plugin. Para que los hilos usen Macs de Tuist, haz una de estas cosas:

- **Desactiva los Satélites macOS para ti.** Cada miembro los desactiva bajo **Satélites Mac** en [Settings → Experimental Features](https://ampcode.com/settings/experimental-features) de Amp.
- **Desactívalos para el espacio de trabajo.** Cuando los orbs de tu espacio de trabajo [se ejecuten en Tuist](#connect), un administrador del espacio puede establecer **Where Orbs Run** en **Self-Hosted Only** en la configuración del espacio de trabajo de Amp, bajo **Orbs**. Los agentes entonces no podrán iniciar satélites alojados por Amp, pero los miembros tampoco podrán usar los orbs integrados de Amp, así que haz esto solo cuando todos tus hilos se ejecuten en tus propios proveedores de orbs.
- **Solicita Macs de Tuist.** Añade "Usa las herramientas `tuist_mac_*` para el trabajo en macOS, no los Satélites macOS." al prompt, o a las directrices del agente de tu espacio de trabajo en la configuración del espacio de trabajo de Amp para que cada hilo las siga.
