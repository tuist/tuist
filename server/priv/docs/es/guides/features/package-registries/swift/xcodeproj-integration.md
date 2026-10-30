---
{
  "title": "Proyecto generado con la integración de paquetes basada en XcodeProj",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Usa el Registro de Tuist con la integración de paquetes basada en XcodeProj en proyectos generados."
}
---
# Proyecto generado con la integración de paquetes basada en XcodeProj {#generated-project-with-xcodeproj-based-integration}

Cuando uses la <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">integración basada en XcodeProj</.localized_link>, puedes utilizar el indicador ``--replace-scm-with-registry`` para resolver las dependencias desde el registro si están disponibles. Añádelo a las `installOptions` en tu archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quieres asegurarte de que se use el registro cada vez que resuelvas las dependencias, tendrás que actualizar `dependencies` en tu archivo `Tuist/Package.swift` para usar el identificador del registro en lugar de una URL. El identificador del registro siempre tiene el formato `{organization}.{repository}`. Por ejemplo, para usar el registro del paquete `swift-composable-architecture`, haz lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
