---
{
  "title": "Buildkite",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta tu primer trabajo de Buildkite en los runners de Tuist: conecta tu clúster, asigna a una cola el nombre de un perfil de Tuist y apúntala desde un paso."
}
---
# Buildkite {#buildkite}

<!-- @snippet: ./_invite-only -->

Tuist supervisa las colas autoalojadas en tu clúster de Buildkite y ejecuta los trabajos que encuentra allí en la flota. Tus pipelines siguen ejecutándose en Buildkite; solo cambia el cómputo. Para ejecutar un trabajo en la flota se requieren tres cambios: conecta tu clúster, asigna a una cola el nombre de un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y apúntala desde un paso.

1. **Conecta tu clúster.** En Buildkite, abre tu clúster, ve a **Agent Tokens** y crea un token; comienza con `bkct_`. En el panel de Tuist, ve a **Settings → Integrations**, elige **Connect** en la tarjeta de Buildkite e introduce el slug de tu organización y el token. El token se almacena cifrado y no se vuelve a mostrar. Para cambiar la organización o rotar el token más adelante, edita los campos de la tarjeta y elige **Save changes**. Tuist comienza a supervisar el clúster en menos de un minuto.
2. **Asigna a una cola el nombre de un perfil de Tuist.** Cada cuenta habilitada comienza con dos <.localized_link href="/guides/features/runners/profiles">perfiles</.localized_link> listos para usar, `linux` y `macos`, y un trabajo se recoge cuando su clave de cola coincide con la etiqueta de un perfil. Crea colas autoalojadas en tu clúster con las claves `tuist-linux` y `tuist-macos`, luego apunta a una desde un paso:

   ```yaml
   # .buildkite/pipeline.yml
   steps:
     - label: "Test"
       command: tuist test
       agents:
         queue: tuist-macos # or tuist-linux
   ```

3. **Haz push y observa.** El trabajo se pone en cola, es reclamado por un runner y se transmite de vuelta a la sección **Runners** de tu panel de Tuist, donde puedes seguir sus registros, pasos y métricas de la máquina. El runner envía el registro desde dentro del trabajo con una credencial limitada a ese único trabajo, por lo que no se necesita ningún token de la API de Buildkite.

## Pausar y desconectar {#pausing-and-disconnecting}

Pausar el envío en una cola de Buildkite evita que Tuist tome nuevos trabajos de ella. Los trabajos que ya se están ejecutando no se ven afectados.

Desconectar el clúster en la tarjeta de Buildkite bajo **Settings → Integrations** hace que Tuist deje de supervisarlo por completo.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre trabajos con <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilizan.
