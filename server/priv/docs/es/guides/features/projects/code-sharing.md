---
{
  "title": "Compartición de código",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a compartir código entre archivos de manifiesto para reducir duplicaciones y garantizar la coherencia"
}
---
# Compartir código {#code-sharing}

Uno de los inconvenientes de Xcode cuando lo usamos con proyectos grandes es que no permite reutilizar elementos de los proyectos aparte de la configuración de compilación mediante archivos `.xcconfig`. Poder reutilizar las definiciones del proyecto resulta útil por las siguientes razones:

- Facilita el **mantenimiento** porque los cambios se pueden aplicar en un solo lugar y todos los proyectos reciben los cambios automáticamente.
- Permite definir **convenciones** a las que los nuevos proyectos pueden ajustarse.
- Los proyectos son más **consistentes** y, por tanto, la probabilidad de que las compilaciones fallen debido a inconsistencias es significativamente menor.
- Agregar nuevos proyectos se convierte en una tarea sencilla porque podemos reutilizar la lógica existente.

Reutilizar código entre archivos de manifiesto es posible en Tuist gracias al concepto de **project description helpers**.

> [!TIP]
> **Un activo único de Tuist**
>
> A muchas organizaciones les gusta Tuist porque ven en los project description helpers una plataforma para que los equipos de plataforma codifiquen sus propias convenciones y desarrollen su propio lenguaje para describir sus proyectos. Por ejemplo, los generadores de proyectos basados en YAML tienen que crear su propia solución de plantillas propietaria basada en YAML o forzar a las organizaciones a construir sus herramientas sobre ella.


## Project description helpers {#project-description-helpers}

Los project description helpers son archivos Swift que se compilan en un módulo, `ProjectDescriptionHelpers`, que los archivos de manifiesto pueden importar. El módulo se compila reuniendo todos los archivos del directorio `Tuist/ProjectDescriptionHelpers`.

Puedes importarlos en tu archivo de manifiesto añadiendo una sentencia de importación al principio del archivo:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` están disponibles en los siguientes manifiestos:
- `Project.swift`
- `Package.swift` (solo con la bandera de compilación `#TUIST`)
- `Workspace.swift`

## Ejemplo {#example}

Los fragmentos siguientes contienen un ejemplo de cómo extendemos el modelo `Project` para añadir constructores estáticos y cómo los usamos desde un archivo `Project.swift`:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

> [!TIP]
> **Una herramienta para establecer convenciones**
>
> Observa cómo, a través de la función, estamos definiendo convenciones sobre el nombre de los targets, el identificador del bundle y la estructura de carpetas.
