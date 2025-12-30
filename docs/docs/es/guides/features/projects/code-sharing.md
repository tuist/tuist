---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Código compartido {#code-sharing}

Uno de los inconvenientes de Xcode cuando lo usamos con proyectos grandes es que
no permite reutilizar elementos de los proyectos que no sean las configuraciones
de compilación a través de los archivos `.xcconfig`. Poder reutilizar
definiciones de proyecto es útil por las siguientes razones:

- Facilita el mantenimiento de **** porque los cambios pueden aplicarse en un
  solo lugar y todos los proyectos reciben los cambios automáticamente.
- Permite definir las convenciones de **** a las que pueden ajustarse los nuevos
  proyectos.
- Los proyectos son más coherentes **** y, por lo tanto, la probabilidad de que
  se rompan las compilaciones debido a incoherencias es significativamente
  menor.
- Añadir un nuevo proyecto se convierte en una tarea fácil porque podemos
  reutilizar la lógica existente.

Tuist permite reutilizar código en distintos archivos de manifiesto gracias al
concepto de ayuda para la descripción de proyectos **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
A muchas organizaciones les gusta Tuist porque ven en los ayudantes de
descripción de proyectos una plataforma para que los equipos de la plataforma
codifiquen sus propias convenciones y creen su propio lenguaje para describir
sus proyectos. Por ejemplo, los generadores de proyectos basados en YAML tienen
que idear su propia solución de plantillas propietarias basadas en YAML, o
forzar a las organizaciones a construir sus herramientas sobre ellas.
<!-- -->
:::

## Ayudantes para la descripción de proyectos {#project-description-helpers}

Las ayudas para la descripción de proyectos son archivos Swift que se compilan
en un módulo, `ProjectDescriptionHelpers`, que los archivos de manifiesto pueden
importar. El módulo se compila reuniendo todos los archivos en el directorio
`Tuist/ProjectDescriptionHelpers`.

Puede importarlos a su archivo de manifiesto añadiendo una declaración de
importación en la parte superior del archivo:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` están disponibles en los siguientes manifiestos:
- `Proyecto.swift`
- `Package.swift` (sólo detrás de la bandera del compilador `#TUIST` )
- `Espacio de trabajo.swift`

## Ejemplo {#example}

Los siguientes fragmentos contienen un ejemplo de cómo ampliamos el modelo
`Project` para añadir constructores estáticos y cómo los utilizamos desde un
archivo `Project.swift`:

::: grupo de códigos
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

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
Observe cómo a través de la función estamos definiendo convenciones sobre el
nombre de los objetivos, el identificador del paquete y la estructura de
carpetas.
<!-- -->
:::
