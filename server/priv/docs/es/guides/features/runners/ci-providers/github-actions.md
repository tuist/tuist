---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · CI providers · Runners · Features · Guides · Tuist",
  "description": "Run your first GitHub Actions job on Tuist Runners: connect GitHub, point runs-on at a Tuist profile, and watch it in the dashboard."
}
---
# GitHub Actions {#github-actions}

> [!IMPORTANT]
> **Solo por invitación**
>
> Tuist Runners está actualmente disponible solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

Ejecutar un trabajo en la flota requiere tres cambios: conectar GitHub, apuntar `runs-on` a un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y hacer push.

1. **Solicita acceso.** Los runners están disponibles solo por invitación durante la beta. [Ponte en contacto](mailto:contact@tuist.dev) indicando la cuenta que deseas habilitar.
2. **Conecta GitHub.** Asegúrate de que tu proyecto esté <.localized_link href="/guides/integrations/gitforge/github">conectado a tu organización de GitHub</.localized_link>. Tuist recibe eventos `workflow_job` para esa organización y envía los trabajos coincidentes a la flota. Sin esta conexión, ningún trabajo llegará a tus runners.
3. **Apunta `runs-on` a un perfil de Tuist.** Cada cuenta habilitada comienza con dos <.localized_link href="/guides/features/runners/profiles">perfiles</.localized_link> listos para usar: `linux` y `macos`. Haz referencia a ellos con el prefijo `tuist-`:

   ```yaml
   jobs:
     build:
       runs-on: tuist-macos # or tuist-linux
       steps:
         - uses: actions/checkout@v4
         - run: tuist test
   ```

   > [!IMPORTANT]
   > **Selecciona Xcode con el perfil del runner**
   >
   > Una imagen de runner macOS contiene una única versión de Xcode, que Tuist selecciona antes de que comience el trabajo en función del perfil. Si estás migrando desde runners alojados en GitHub, elimina los pasos que usan `xcode-select --switch` (o `xcode-select -s`) u otras herramientas y acciones para cambiar las versiones de Xcode. Esos pasos suelen hacer referencia a instalaciones de Xcode específicas de las imágenes alojadas en GitHub y pueden fallar en Tuist Runners.
   >
   > Para usar otra versión de Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">crea o elige un perfil</.localized_link> con esa versión y actualiza `runs-on`, por ejemplo `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` y `swift` usarán entonces la versión de Xcode seleccionada en el perfil sin necesidad de configuración adicional en el flujo de trabajo.

4. **Haz push y supervisa.** El trabajo se pone en cola, es asumido por un runner y se transmite de vuelta a la sección **Runners** de tu panel de control de Tuist, donde puedes seguir sus registros, pasos y métricas de la máquina.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre trabajos mediante <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilicen.
