---
{
  "title": "Crear un nuevo proyecto",
  "titleTemplate": ":title · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a crear un nuevo proyecto con Tuist."
}
---
# Crear un nuevo proyecto {#create-a-new-project}

La forma más sencilla de iniciar un nuevo proyecto con Tuist es usar el comando `tuist init`. Este comando inicia una CLI interactiva que te guía durante la configuración del proyecto. Cuando se te solicite, asegúrate de seleccionar la opción para crear un "proyecto generado".

A continuación, puedes <.localized_link href="/guides/features/projects/editing">editar el proyecto</.localized_link> ejecutando `tuist edit`, y Xcode abrirá un proyecto donde podrás editarlo. Uno de los archivos generados es `Project.swift`, que contiene la definición de tu proyecto. Si estás familiarizado con Swift Package Manager, piénsalo como `Package.swift`, pero con la terminología de los proyectos de Xcode.

::: code-group
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

> [!NOTE]
> Mantenemos intencionadamente corta la lista de plantillas disponibles para minimizar la sobrecarga de mantenimiento. Si quieres crear un proyecto que no sea una aplicación, por ejemplo un framework, puedes usar `tuist init` como punto de partida y luego modificar el proyecto generado según tus necesidades.


## Crear un proyecto manualmente {#manually-creating-a-project}

Como alternativa, puedes crear el proyecto manualmente. Recomendamos hacerlo solo si ya estás familiarizado con Tuist y sus conceptos. Lo primero que debes hacer es crear directorios adicionales para la estructura del proyecto:

```bash
mkdir MyFramework
cd MyFramework
```

Luego crea un archivo `Tuist.swift`, que configurará Tuist y lo usará para determinar el directorio raíz del proyecto, y un `Project.swift`, donde se declarará tu proyecto:

::: code-group
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

> [!WARNING]
> Tuist usa el directorio `Tuist/` para determinar la raíz de tu proyecto y, a partir de ahí, busca otros archivos de manifiesto recorriendo los directorios. Recomendamos crear esos archivos con el editor que prefieras y, a partir de ese momento, puedes usar `tuist edit` para editar el proyecto con Xcode.
