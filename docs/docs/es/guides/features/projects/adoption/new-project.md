---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Crear un nuevo proyecto {#create-a-new-project}

La forma más sencilla de iniciar un nuevo proyecto con Tuist es utilizar el
comando `tuist init`. Este comando lanza una CLI interactiva que te guía a
través de la configuración de tu proyecto. Cuando se te pregunte, asegúrate de
seleccionar la opción de crear un "proyecto generado".

A continuación, puede
<LocalizedLink href="/guides/features/projects/editing">editar el proyecto</LocalizedLink> ejecutando `tuist edit`, y Xcode abrirá un proyecto en
el que podrá editar el proyecto. Uno de los archivos que se generan es el
`Project.swift`, que contiene la definición de tu proyecto. Si estás
familiarizado con el Gestor de Paquetes Swift, piensa en él como el
`Package.swift` pero con la jerga de los proyectos de Xcode.

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

::: info
<!-- -->
Mantenemos intencionadamente corta la lista de plantillas disponibles para
minimizar la sobrecarga de mantenimiento. Si quieres crear un proyecto que no
represente una aplicación, por ejemplo un framework, puedes utilizar `tuist
init` como punto de partida y luego modificar el proyecto generado para
adaptarlo a tus necesidades.
<!-- -->
:::

## Creación manual de un proyecto {#manually-creating-a-project}

También puedes crear el proyecto manualmente. Te recomendamos hacerlo sólo si ya
estás familiarizado con Tuist y sus conceptos. Lo primero que tendrás que hacer
es crear directorios adicionales para la estructura del proyecto:

```bash
mkdir MyFramework
cd MyFramework
```

A continuación, crea un archivo `Tuist.swift`, que configurará Tuist y es
utilizado por Tuist para determinar el directorio raíz del proyecto, y un
`Project.swift`, donde se declarará tu proyecto:

::: grupo de códigos
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

::: advertencia
<!-- -->
Tuist utiliza el directorio `Tuist/` para determinar la raíz de tu proyecto, y a
partir de ahí busca otros archivos de manifiesto globbing los directorios.
Recomendamos crear esos archivos con el editor de tu elección, y a partir de
ahí, puedes usar `tuist edit` para editar el proyecto con Xcode.
<!-- -->
:::
