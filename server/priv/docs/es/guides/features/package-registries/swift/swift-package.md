---
{
  "title": "Paquete Swift",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar el Registro de Tuist en un paquete Swift."
}
---
# Paquete Swift {#swift-package}

Si estás trabajando en un paquete Swift, puedes usar la opción `--replace-scm-with-registry` para resolver las dependencias desde el registro si están disponibles:

```bash
swift package --replace-scm-with-registry resolve
```

Si quieres asegurarte de que el registro se use cada vez que resuelvas dependencias, tendrás que actualizar `dependencies` en tu archivo `Package.swift` para usar el identificador del registro en lugar de una URL. El identificador del registro siempre tiene el formato `{organization}.{repository}`. Por ejemplo, para usar el registro del paquete `swift-composable-architecture`, haz lo siguiente:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
