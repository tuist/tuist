---
{
  "title": "Proyecto de Xcode generado",
  "titleTemplate": ":title · Snapshots · Funcionalidades · Guías · Tuist",
  "description": "Captura una instantánea de cada vista previa de SwiftUI de un proyecto generado por Tuist y revisa los cambios en Tuist."
}
---
# Instantáneas del proyecto de Xcode generado {#generated-xcode-project-snapshots}

> [!IMPORTANT]
> **Requisitos**
>
> - Instantáneas habilitadas para tu cuenta. Actualmente son solo por invitación: [ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso.
> - Un proyecto <.localized_link href="/guides/get-started/generated-xcode-project">conectado a Tuist</.localized_link>.
> - iOS 17 o macOS 14 para renderizar las vistas previas.

La biblioteca [tuist/snapshots](https://github.com/tuist/snapshots) convierte cada vista previa de SwiftUI de tu app en una imagen, para que no tengas que escribir tests de instantáneas a mano. `tuist test` sube las imágenes después de la ejecución y Tuist las compara con la <.localized_link href="/guides/features/snapshots#how-it-works">línea base</.localized_link>.

## Configuración {#set-up}

Añade el paquete a `Tuist/Package.swift`:

```swift
let package = Package(
    name: "App",
    dependencies: [
        .package(url: "https://github.com/tuist/snapshots", .upToNextMinor(from: "0.1.0")),
    ]
)
```

Luego añade un destino de test unitario que dependa de tu app y de `TuistSnapshotsTesting`, y un esquema que lo ejecute. El esquema da nombre al conjunto de instantáneas:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        // Your app target, named "App".
        .target(
            name: "AppSnapshotTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.app-snapshot-tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Tests/AppSnapshotTests/**"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TuistSnapshotsTesting"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppSnapshots",
            buildAction: .buildAction(targets: [.target("App")]),
            testAction: .targets([.testableTarget(target: "AppSnapshotTests")])
        ),
    ]
)
```

Añade una clase de test al destino. Cada vista previa se convierte en su propio test:

```swift
import TuistSnapshotsTesting

final class PreviewSnapshotTests: PreviewSnapshotTestCase {}
```

Ejecuta `tuist install` para obtener el paquete.

## Ejecución {#run}

Ejecuta el esquema con `tuist test`, siempre en el mismo simulador, porque un dispositivo diferente genera imágenes de un tamaño distinto:

```bash
tuist test AppSnapshots --device "iPhone 17"
```

En CI, las imágenes que generaron los tests se suben después de la ejecución y el comando falla cuando cambiaron y nadie aprobó los cambios. Las ejecuciones locales no suben nada, porque subirían cambios sin confirmar.

> [!TIP]
> Con los <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link>, un destino de test de instantáneas solo se omite una vez que sus imágenes pasaron o fueron aprobadas, así que una nueva ejecución no puede omitir un destino cuyos cambios nadie revisó. Cuando una ejecución omite destinos, las imágenes que no se renderizaron cuentan como omitidas, no como eliminadas.

<!-- @snippet: ./_previews-library -->
