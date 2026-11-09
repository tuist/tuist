---
{
  "title": "GitHub Actions",
  "titleTemplate": ":title · Proveedores de CI · Runners · Funcionalidades · Guías · Tuist",
  "description": "Ejecuta tu primer trabajo de GitHub Actions en los runners de Tuist: conecta GitHub, apunta runs-on a un perfil de Tuist y supervísalo en el panel."
}
---
# Acciones de GitHub {#github-actions}

<!-- @snippet: ./_invite-only -->

Ejecutar un trabajo en la flota requiere tres cambios: conectar GitHub, apuntar `runs-on` a un <.localized_link href="/guides/features/runners/profiles">perfil</.localized_link> de Tuist y hacer push.

1. **Conecta GitHub.** Asegúrate de que tu proyecto esté <.localized_link href="/guides/integrations/gitforge/github">conectado a tu organización de GitHub</.localized_link>. Tuist recibe eventos `workflow_job` para esa organización y envía los trabajos coincidentes a la flota. Sin esta conexión, ningún trabajo llega a tus runners.
2. **Apunta `runs-on` a un perfil de Tuist.** Cada cuenta habilitada comienza con dos <.localized_link href="/guides/features/runners/profiles">perfiles</.localized_link> listos para usar: `linux` y `macos`. Haz referencia a ellos con el prefijo `tuist-`:

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
   > Una imagen de runner macOS contiene una única versión de Xcode, que Tuist selecciona antes de que comience el trabajo según el perfil. Si estás migrando desde runners alojados en GitHub, elimina los pasos que usan `xcode-select --switch` (o `xcode-select -s`) u otras herramientas y acciones para cambiar de versión de Xcode. Esos pasos suelen hacer referencia a instalaciones de Xcode específicas de las imágenes alojadas en GitHub y pueden fallar en los Runners de Tuist.
   >
   > Para usar otra versión de Xcode, <.localized_link href="/guides/features/runners/profiles#creating-a-profile">crea o elige un perfil</.localized_link> con esa versión y actualiza `runs-on`, por ejemplo `runs-on: tuist-xcode-26-4`. `xcodebuild`, `xcrun` y `swift` usarán entonces la versión de Xcode seleccionada por el perfil sin necesidad de configuración adicional en el flujo de trabajo.

3. **Haz push y supervisa.** El trabajo se pone en cola, es reclamado por un runner y su salida se transmite a la sección **Runners** de tu panel de Tuist, donde puedes seguir sus registros, pasos y métricas de la máquina.

## Volúmenes de caché {#cache-volumes}

Mantén las cachés de Xcode, de módulos y de Gradle, así como otros directorios, entre trabajos con <.localized_link href="/guides/features/runners/cache-volumes">volúmenes de caché</.localized_link>. Añádelos después del checkout y antes de los comandos que los utilizan.

Otorga al trabajo el permiso `id-token: write` para que sus volúmenes de caché y el checkout en caché se adjunten tan pronto como comience. Sin él, el runner espera a que GitHub informe de qué trabajo está ejecutando, y un trabajo que GitHub informa tarde comienza con las cachés vacías. Un flujo de trabajo que inicia sesión en Tuist con OpenID Connect ya lo otorga.

```yaml
permissions:
  contents: read
  id-token: write
```
