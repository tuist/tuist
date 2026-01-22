---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Paquete Swift {#swift-package}

Si estás trabajando en un paquete Swift, puedes utilizar el indicador
`--replace-scm-with-registry` para resolver las dependencias del registro si
están disponibles:

```bash
swift package --replace-scm-with-registry resolve
```

Si desea asegurarse de que el registro se utilice cada vez que resuelva
dependencias, deberá actualizar `dependencies` en su `Package.swift` archivo
para utilizar el identificador del registro en lugar de una URL. El
identificador del registro siempre tiene el formato
`{organization}.{repository}`. Por ejemplo, para utilizar el registro del
paquete `swift-composable-architecture`, haga lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
