---
{
  "title": "Buildkite",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first Buildkite job on Tuist Runners: connect your cluster, name a queue after a Tuist profile, and target it from a step."
}
---
# Buildkite {#buildkite}

> [!IMPORTANT]
> **Solo por invitación**
>
> Tuist Runners está disponible actualmente solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

Tuist supervisa las colas autoalojadas en tu clúster de Buildkite y ejecuta los trabajos que encuentra allí en la flota. Tus pipelines siguen ejecutándose en Buildkite; solo cambia el cómputo. Para ejecutar un trabajo en la flota se requieren tres cambios: conectar tu clúster, asignar a una cola el nombre de un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y apuntarla desde un paso.

1. **Solicita acceso.** Los runners están disponibles solo por invitación durante la beta. [Ponte en contacto](mailto:contact@tuist.dev) indicando la cuenta que deseas habilitar.
2. **Conecta tu clúster.** En Buildkite, abre tu clúster, ve a **Tokens de agente** y crea un token; comienza con `bkct_`. En tu panel de Tuist, ve a **Configuración → Integraciones**, selecciona **Conectar** en la tarjeta de Buildkite e introduce el slug de tu organización y el token. El token se almacena cifrado y no se vuelve a mostrar. Para cambiar la organización o rotar el token más adelante, edita los campos de la tarjeta y selecciona **Guardar cambios**. Tuist comienza a supervisar el clúster en menos de un minuto.
3. **Asigna a una cola el nombre de un perfil de Tuist.** Cada cuenta habilitada comienza con dos <.localized_link href="/guides/features/runners/profiles">perfiles</.localized_link> listos para usar, `linux` y `macos`, y un trabajo se recoge cuando la clave de su cola coincide con la etiqueta de un perfil. Crea colas autoalojadas en tu clúster con las claves `tuist-linux` y `tuist-macos`, luego apunta a una desde un paso:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

4. **Haz push y supervisa.** El trabajo se pone en cola, es reclamado por un runner y se transmite de vuelta a la sección **Runners** de tu panel de Tuist, donde puedes seguir sus registros, pasos y métricas de la máquina. El runner envía el registro desde dentro del trabajo con una credencial limitada únicamente a ese trabajo, por lo que no se necesita ningún token de API de Buildkite.

## Pausar y desconectar {#pausing-and-disconnecting}

Pausar el envío en una cola de Buildkite evita que Tuist tome nuevos trabajos de ella. Los trabajos que ya se están ejecutando no se ven afectados.

Desconectar el clúster en la tarjeta de Buildkite bajo **Configuración → Integraciones** hace que Tuist deje de supervisarlo por completo.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre trabajos con <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilizan.
