---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Proyecto generado con la integración del paquete basado en XcodeProj. {#generated-project-with-xcodeproj-based-integration}

Cuando utilices la integración basada en
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj</LocalizedLink>,
puedes usar el indicador ``--replace-scm-with-registry`` para resolver las
dependencias del registro, si están disponibles. Añádelo a `installOptions` en
tu archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quieres asegurarte de que el registro se utiliza cada vez que resuelves
dependencias, tendrás que actualizar `dependencies` en tu `Tuist/Package.swift`
archivo para utilizar el identificador del registro en lugar de una URL. El
identificador del registro siempre tiene el formato
`{organization}.{repository}`. Por ejemplo, para utilizar el registro para el
paquete `swift-composable-architecture`, haz lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
