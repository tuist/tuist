---
{
  "title": "Proyecto generado con la integración de paquetes de Xcode",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Aprende a usar el Registry de Tuist en un proyecto de Xcode generado con la integración de paquetes de Xcode."
}
---
# Proyecto generado con la integración de paquetes de Xcode {#generated-project-with-xcode-based-integration}

Si estás usando la <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">integración predeterminada de Xcode</.localized_link> de paquetes con Tuist Projects, debes usar el identificador del registro en lugar de una URL al añadir un paquete:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
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
> No tienes que añadir cada paquete por su identificador de registro. Ejecutar `tuist registry setup` una vez generado el proyecto también configura Xcode para resolver los paquetes declarados con una URL de control de código fuente desde el registro, lo cual `registryEnabled` no hace por sí solo. Consulta <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Resolver paquetes de control de código fuente</.localized_link>.
