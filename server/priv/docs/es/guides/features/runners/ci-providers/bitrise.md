---
{
  "title": "Bitrise",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta tus compilaciones de Bitrise en los Runners de Tuist: conecta tu espacio de trabajo, vincula un grupo de runners autoalojados con un perfil de Tuist y selecciona el grupo en tu flujo de trabajo."
}
---
# Bitrise {#bitrise}

> [!IMPORTANT]
> **Solo por invitación**
>
> Los Tuist Runners están disponibles solo por invitación. [Contacta con nosotros](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

> [!WARNING]
> **Solo repositorios privados**
>
> Tuist confía en cada compilación de Bitrise: las compilaciones comparten la caché de tu cuenta y pueden escribir en ella. No vincules un pool cuyos flujos de trabajo compile pull requests desde forks de un repositorio público.

Tuist gestiona los pools de runners autoalojados de tu espacio de trabajo de Bitrise. Una compilación que seleccione uno de esos pools se ejecuta en una máquina de Tuist del <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> que vincules con el pool. Tus flujos de trabajo, activadores y registros permanecen en Bitrise; solo cambian las máquinas.

1. **Solicita acceso.** Los runners están disponibles solo por invitación durante la beta. [Contacta con nosotros](mailto:contact@tuist.dev) indicando la cuenta que deseas habilitar.
2. **Conecta tu espacio de trabajo.** En Bitrise, abre **Configuración del espacio de trabajo → Seguridad → Tokens de API del espacio de trabajo** y crea un token con el rol de espacio de trabajo **Viewer** y acceso **Tester/QA** a Bitrise CI para todos los proyectos. En tu panel de Tuist, ve a **Configuración → Integraciones**, elige **Conectar** en la tarjeta de Bitrise y pega el token. Tuist lee el espacio de trabajo desde el token, lo almacena cifrado y nunca vuelve a mostrarlo.
3. **Crea un pool de runners.** En Bitrise, abre **Configuración del espacio de trabajo → Infraestructura**, elige **Añadir pool de runners** y asígnale el nombre de la máquina que representa, por ejemplo `tuist-macos`. Copia el token del pool: Bitrise lo muestra solo una vez.
4. **Vincula el pool con un perfil de Tuist.** En la tarjeta de Bitrise en Tuist, bajo **Pools de runners**, selecciona el pool, el perfil de Tuist en el que deben ejecutarse sus compilaciones, pega el token del pool y elige **Añadir pool**. Cada cuenta habilitada comienza con dos perfiles, `tuist-linux` y `tuist-macos`. Añade un pool por cada perfil que quieras usar.
5. **Selecciona el pool en tu flujo de trabajo.** En el editor de flujos de trabajo de Bitrise, abre **Stacks y máquinas** y elige **Runner autoalojado: tuist-macos**. En `bitrise.yml`, configura el stack del pool, que Tuist muestra bajo el nombre del pool:

   ```yaml
   meta:
     bitrise.io:
       stack: agent-pool-a0c641c0-142f-427d-a326-07f0f6c2a1be
   ```

6. **Ejecuta una compilación.** En unos segundos, una máquina de Tuist se conecta al pool, toma la compilación y se desconecta cuando finaliza. La compilación aparece en la sección **Runners** de tu panel de Tuist con las métricas de la máquina y un enlace de vuelta a Bitrise, donde permanecen sus registros.

## Pools dedicados {#dedicated-pools}

Usa los pools que vincules con Tuist exclusivamente para Tuist. Si una de tus propias máquinas también se conecta a un pool vinculado, competirá con Tuist por las compilaciones de ese pool.

## Límite de runners {#runner-limit}

Cada máquina de Tuist cuenta como un runner de Bitrise mientras ejecuta una compilación y deja de contar cuando se desconecta. Por lo tanto, el límite de runners de tu plan de Bitrise restringe cuántas de tus compilaciones se ejecutan en Tuist al mismo tiempo, junto con tu límite de concurrencia de Tuist.

## Desconexión {#disconnecting}

Eliminar un pool de la tarjeta de Bitrise impide que Tuist tome las compilaciones de ese pool. Las compilaciones que ya se estén ejecutando no se ven afectadas.

Elegir **Desconectar** en la tarjeta de Bitrise elimina el espacio de trabajo y todos sus pools.
