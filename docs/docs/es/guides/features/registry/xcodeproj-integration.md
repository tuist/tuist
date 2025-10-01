---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Proyecto generado con la integración de paquetes basada en XcodeProj {#generated-project-with-xcodeproj-based-integration}

Cuando utilice la integración basada en
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj</LocalizedLink>,
puede utilizar la bandera ``--replace-scm-with-registry`` para resolver
dependencias del registro si están disponibles. Añádalo a `installOptions` en su
archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quiere asegurarse de que se utiliza el registro cada vez que resuelva
dependencias, tendrá que actualizar `dependencies` en su archivo
`Tuist/Package.swift` para utilizar el identificador del registro en lugar de
una URL. El identificador del registro siempre tiene la forma
`{organization}.{repository}`. Por ejemplo, para utilizar el registro del
paquete `swift-composable-architecture`, haga lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
