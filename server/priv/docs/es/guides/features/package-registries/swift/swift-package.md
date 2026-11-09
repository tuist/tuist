---
{
  "title": "Paquete Swift",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar el registro de Tuist en un paquete Swift."
}
---
# Paquete Swift {#swift-package}

Si estás trabajando en un paquete Swift, puedes usar la opción `--replace-scm-with-registry` para resolver las dependencias desde el registro si están disponibles:

```bash
swift package --replace-scm-with-registry resolve
```

Si quieres asegurarte de que se use el registro cada vez que resuelvas las dependencias, tendrás que actualizar `dependencies` en tu archivo `Package.swift` para usar el identificador del registro en lugar de una URL.

<!-- @snippet: ./_registry-identifier -->
