---
{
  "title": "Proyecto generado con la integración de paquetes basada en XcodeProj",
  "titleTemplate": ":title · Swift · Registros de paquetes · Funcionalidades · Guías · Tuist",
  "description": "Usa el Registro de Tuist con la integración de paquetes basada en XcodeProj en proyectos generados."
}
---
# Proyecto generado con la integración de paquetes basada en XcodeProj {#generated-project-with-xcodeproj-based-integration}

Al usar la <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">integración basada en XcodeProj</.localized_link>, puedes usar el indicador `--replace-scm-with-registry` para resolver las dependencias desde el registro si están disponibles. Añádelo a `installOptions` en tu archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quieres asegurarte de que se use el registro cada vez que resuelvas las dependencias, tendrás que actualizar `dependencies` en tu archivo `Tuist/Package.swift` para usar el identificador del registro en lugar de una URL.

<!-- @snippet: ./_registry-identifier -->
