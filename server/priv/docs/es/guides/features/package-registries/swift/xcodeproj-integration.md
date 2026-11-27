---
{
  "title": "Proyecto generado con la integración de paquetes basada en XcodeProj",
  "titleTemplate": ":title · Swift · Package Registries · Funcionalidades · Guías · Tuist",
  "description": "Usa el registro de Tuist con la integración de paquetes basada en XcodeProj en proyectos generados."
}
---
# Proyecto generado con la integración de paquetes basada en XcodeProj {#generated-project-with-xcodeproj-based-integration}

Al usar la <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">integración basada en XcodeProj</.localized_link>, puedes usar la bandera `--replace-scm-with-registry` para resolver las dependencias desde el registro si están disponibles. Añádela a `installOptions` en tu archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quieres asegurarte de que el registro se use cada vez que resuelvas dependencias, tendrás que actualizar `dependencies` en tu archivo `Tuist/Package.swift` para usar el identificador del registro en lugar de una URL.

<!-- @snippet: ./_registry-identifier -->
