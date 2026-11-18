---
{
  "title": "Amp",
  "titleTemplate": ":title · Sandboxes · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta los orbs de tu espacio de trabajo de Amp en Tuist Sandboxes, en Linux o macOS."
}
---
# Amp {#amp}

> [!IMPORTANT]
> **Solo con invitación**
>
> Los Sandboxes de Tuist, tanto en Linux como en macOS, están disponibles solo con invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

[Amp](https://ampcode.com) ejecuta las herramientas de cada hilo en un [orb](https://ampcode.com/docs/orbs), una máquina con el repositorio del hilo descargado. Tuist puede ser el [proveedor de orbs autoalojados](https://ampcode.com/docs/orbs/self-hosted) de tu espacio de trabajo de Amp: cada hilo que lo seleccione se ejecutará en su propio <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link> de Tuist, en Linux o macOS. No necesitas ejecutar ni alojar nada por tu cuenta.

## Conectar Amp {#connect}

Debes ser administrador tanto del espacio de trabajo de Amp como de la cuenta de Tuist.

1. En Amp, abre la sección **Settings → Orbs** de tu espacio de trabajo, haz clic en **Add Orb Provider** y asígnale un nombre, por ejemplo `tuist`. Los miembros seleccionan el proveedor por este nombre. Copia el token `aop_live_…`; Amp lo muestra solo una vez.
2. En el diálogo **Edit** del proveedor en Amp, añade estos **Tipos de orb** y selecciona el predeterminado:

   | Tipo | Plataforma | Configuración |
   | --- | --- | --- |
   | `linux` | Linux | 2 vCPU, 4 GiB de RAM, 10 GB de espacio de trabajo |
   | `macos` | macOS con Xcode | 8 vCPU, 8 GiB de RAM, 10 GB de espacio de trabajo |

3. En Tuist, abre **Sandboxes** en el panel de control de tu cuenta, haz clic en **Connect** en la tarjeta de Amp y pega el token.

La tarjeta muestra **Connected** una vez que Tuist está atendiendo al proveedor. Una cuenta de Tuist atiende a un único proveedor. Cualquier persona que pueda usar el proveedor en Amp ejecutará orbs bajo la cuenta de Tuist conectada, que será la facturada. Para detenerlo, haz clic en **Disconnect** en la tarjeta o desactiva el proveedor en Amp.

## Iniciar un hilo {#start-a-thread}

En el compositor de nuevos hilos de Amp, haz clic en **Orb**, selecciona el proveedor de Tuist bajo **Self-Hosted** y elige `linux` o `macos`. Desde la CLI de Amp:

```bash
amp -ox "Fix the failing snapshot tests" --orb-provider tuist --orb-size macos
```

Un hilo mantiene su tipo de orb durante toda su vida útil. Sin un tipo definido, obtiene el valor predeterminado del proveedor. Para usar una plataforma para cada nuevo hilo, elige el proveedor y su tipo bajo **Default Orb** en la sección **Settings → Orbs** de Amp.

Amp clona el repositorio, ejecuta tu script `.agents/setup` y configura las credenciales de Git, como hace con cada orb. Cada orb también puede leer la <.localized_link href="/guides/features/cache">caché</.localized_link> de Tuist de tu cuenta.

## Pausa y retención {#retention}

Cuando un hilo queda inactivo, Amp pausa su orb. El siguiente mensaje lo reanuda con sus archivos intactos.

- **Linux:** Los procesos en ejecución sobreviven a una pausa. Un orb que ha estado pausado durante mucho tiempo se mueve al almacenamiento de archivo y se restaura con el siguiente mensaje, sin sus procesos. Los orbs de Linux conservan sus archivos hasta que Amp elimina el orb del hilo.
- **macOS:** Un orb pausado, o en estado de error, durante 7 días se elimina. El siguiente mensaje del hilo inicia un orb nuevo y Amp vuelve a ejecutar `.agents/setup`. El primer orb de macOS en una máquina instala la CLI de Amp, por lo que puede tardar hasta dos minutos en iniciarse.

Un orb que permanece inactivo sin que Amp lo pause, por ejemplo porque nunca llegó una pausa, se pausa después de diez minutos con un uso de CPU casi nulo.
