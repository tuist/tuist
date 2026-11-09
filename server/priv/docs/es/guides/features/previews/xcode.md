---
{
  "title": "Previews de Xcode",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Comparte previews de aplicaciones desde proyectos existentes de Xcode y proyectos generados con Tuist."
}
---
# Previews de Xcode

Compila tu aplicación y luego usa `tuist share` para publicarla en tu proyecto de Tuist. Conecta primero tu proyecto siguiendo la guía de <.localized_link href="/guides/get-started/existing-xcode-project">proyecto de Xcode existente</.localized_link> o de <.localized_link href="/guides/get-started/generated-xcode-project">proyecto generado</.localized_link>.

## Compilar y compartir

Para un proyecto generado por Tuist:

```bash
tuist generate App
tuist xcodebuild build -scheme App -workspace App.xcworkspace \
  -configuration Debug -sdk iphonesimulator
tuist share App
```

Para un proyecto de Xcode existente:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -sdk iphonesimulator
tuist share App --configuration Debug --platforms iOS
```

Reemplaza los nombres del scheme, el proyecto y el workspace por los tuyos. Para compartir una compilación de Release, usa `-configuration Release` al compilar y `--configuration Release` al compartir.

## Dispositivos físicos

Eres responsable de firmar las compilaciones para dispositivo con un perfil de aprovisionamiento que permita la instalación en el dispositivo del destinatario. Compila con un destino de dispositivo en lugar del SDK del simulador:

```bash
tuist xcodebuild build -scheme App -project App.xcodeproj \
  -configuration Debug -destination 'generic/platform=iOS'
tuist share App --configuration Debug --platforms iOS
```

También puedes compartir un IPA ya exportado:

```bash
tuist share App.ipa
```

Los destinatarios pueden abrir un enlace de preview de IPA en su dispositivo móvil para instalar la aplicación. La autenticación y la visibilidad de las previews del proyecto siguen aplicándose.

## CI y números de compilación

Usa tu <.localized_link href="/guides/integrations/continuous-integration">autenticación de CI</.localized_link> existente y haz que `CFBundleVersion` sea único para cada nueva compilación. Por ejemplo, usa <code v-pre>${{ github.run_number }}</code> de GitHub Actions. Volver a subir el mismo binario y número de compilación mediante `tuist share` falla en lugar de crear un duplicado.

```bash
tuist share App --track beta --release-notes "Fix sign-in"
```

Consulta <.localized_link href="/guides/features/previews#run-a-preview">Ejecutar una preview</.localized_link> para ejecutar compilaciones publicadas, gestionar el acceso, los tracks y las insignias de README.

<!-- @snippet: ./_tuist-share -->

Los destinatarios pueden usar la <.localized_link href="/guides/features/previews/run/macos">app de Tuist para macOS</.localized_link> o la <.localized_link href="/guides/features/previews/run/ios">app para iPhone</.localized_link> independientemente de la integración con el sistema de compilación. La guía para iPhone también cubre las <.localized_link href="/guides/features/previews/run/ios#in-app-update-notifications">notificaciones de actualización en la app</.localized_link> con el SDK de Tuist.
