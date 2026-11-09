---
{
  "title": "Proyecto generado con la integración de paquetes basada en XcodeProj",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Usa el Registry de Tuist con la integración de paquetes basada en XcodeProj en proyectos generados."
}
---
# Proyecto generado con la integración de paquetes basada en XcodeProj {#generated-project-with-xcodeproj-based-integration}

Cuando utilices la <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">integración basada en XcodeProj</.localized_link>, puedes usar el indicador `--replace-scm-with-registry` para resolver las dependencias desde el registro si están disponibles. Añádelo a `installOptions` en tu archivo `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Si quieres asegurarte de que el registro se utiliza cada vez que resuelves las dependencias, tendrás que actualizar `dependencies` en tu archivo `Tuist/Package.swift` para usar el identificador del registro en lugar de una URL.

<!-- @snippet: ./_registry-identifier -->
