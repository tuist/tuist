---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Paquete Swift {#swift-package}

Si está trabajando en un paquete Swift, puede utilizar la bandera
`--replace-scm-with-registry` para resolver dependencias del registro si están
disponibles:

```bash
swift package --replace-scm-with-registry resolve
```

Si quiere asegurarse de que el registro se utiliza cada vez que resuelve
dependencias, tendrá que actualizar `dependencies` en su archivo `Package.swift`
para utilizar el identificador del registro en lugar de una URL. El
identificador del registro siempre tiene la forma `{organization}.{repository}`.
Por ejemplo, para utilizar el registro para el paquete
`swift-composable-architecture`, haga lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
