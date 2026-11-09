---
{
  "title": "Proyecto generado con la integración de paquetes de Xcode",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar el registro de Tuist en un proyecto de Xcode generado con la integración de paquetes de Xcode."
}
---
# Proyecto generado con la integración de paquetes de Xcode {#generated-project-with-xcode-based-integration}

Si utilizas la <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">integración predeterminada de Xcode</.localized_link> de paquetes con Proyectos Tuist, debes usar el identificador del registro en lugar de una URL al añadir un paquete:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```

> [!TIP]
> No es necesario añadir cada paquete por su identificador de registro. Ejecutar `tuist registry setup` una vez generado el proyecto también configura Xcode para resolver los paquetes declarados con una URL de control de código fuente desde el registro, algo que `registryEnabled` no hace por sí solo. Consulta <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Resolución de paquetes de control de código fuente</.localized_link>.
