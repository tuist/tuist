---
{
  "title": "Xcode",
  "titleTemplate": ":title · Instantáneas · Funcionalidades · Guías · Tuist",
  "description": "Captura una instantánea de cada vista previa de SwiftUI de un proyecto de Xcode y revisa los cambios en Tuist."
}
---
# Instantáneas de Xcode {#xcode-snapshots}

> [!IMPORTANT]
> **Requisitos**
>
> - Instantáneas habilitadas para tu cuenta. Actualmente son solo por invitación: [ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso.
> - Un proyecto <.localized_link href="/guides/get-started/existing-xcode-project">conectado a Tuist</.localized_link>.
> - iOS 17 o macOS 14 para renderizar las previews.

La biblioteca [tuist/snapshots](https://github.com/tuist/snapshots) convierte cada preview de SwiftUI de tu app en una imagen, así no tienes que escribir tests de instantáneas a mano. `tuist xcodebuild test` sube las imágenes después de la ejecución y Tuist las compara con la <.localized_link href="/guides/features/snapshots#how-it-works">línea base</.localized_link>.

## Configuración {#set-up}

1. En Xcode, añade el paquete `https://github.com/tuist/snapshots`, desde la versión `0.1.0`.
2. Crea un target de tests unitarios alojado por tu app, por ejemplo `AppSnapshotTests`, y enlaza el producto `TuistSnapshotsTesting` del paquete a ese target.
3. Añade una clase de test a ese target. Cada preview se convierte en su propio test:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

4. Añade un scheme que ejecute el target, por ejemplo `AppSnapshots`. El scheme da nombre al conjunto de instantáneas.

## Ejecución {#run}

Ejecuta los tests mediante `tuist xcodebuild test`, siempre en el mismo simulador, porque un dispositivo diferente renderiza imágenes de distinto tamaño:

```bash
tuist xcodebuild test -scheme AppSnapshots -destination 'platform=iOS Simulator,name=iPhone 17'
```

En CI, las imágenes que generan los tests se suben después de la ejecución y el comando falla cuando han cambiado y nadie ha aprobado los cambios. Las ejecuciones locales no suben nada, porque subirían cambios sin confirmar.

<!-- @snippet: ./_previews-library -->
