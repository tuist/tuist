---
{
  "title": "Crear un proyecto generado",
  "titleTemplate": ":title · Xcode · Tutoriales · Tuist",
  "description": "Aprende a crear tu primer proyecto de Xcode generado con Tuist y a añadirle dependencias"
}
---
# Crear un proyecto generado {#create-a-generated-project}

La forma más fácil de empezar con Tuist en cualquier directorio o en el directorio de un proyecto existente:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

El comando te guiará paso a paso para <.localized_link href="/guides/features/projects">crear un proyecto generado</.localized_link> o integrar un proyecto o espacio de trabajo de Xcode existente. Te ayuda a conectar tu configuración con el servidor remoto, dándote acceso a funcionalidades como <.localized_link href="/guides/features/selective-testing">tests selectivos</.localized_link>, <.localized_link href="/guides/features/previews">previews</.localized_link> y el <.localized_link href="/guides/features/package-registries/swift">registry</.localized_link>.

> [!NOTE]
> **Migrar un proyecto existente**
>
> Si quieres migrar un proyecto existente a proyectos generados para mejorar la experiencia de desarrollo y aprovechar nuestra <.localized_link href="/guides/features/cache">caché</.localized_link>, consulta nuestra <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">guía de migración</.localized_link>.


## Añadir dependencias {#add-dependencies}

Es habitual que los proyectos dependan de bibliotecas de terceros para aportar funcionalidad adicional. Para ello, ejecuta el siguiente comando y obtén la mejor experiencia al editar tu proyecto:

```bash
tuist edit
```

Se abrirá un proyecto de Xcode con los archivos de tu proyecto. Edita el `Package.swift` y añade la

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

A continuación, edita el target de la aplicación en tu proyecto para declarar `Kingfisher` como dependencia:

```swift
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
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            buildableFolders: [
                "MyApp/Sources",
                "MyApp/Resources",
            ],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
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

Después, ejecuta `tuist install` para resolver y descargar las dependencias mediante el [Swift Package Manager](https://www.swift.org/documentation/package-manager/).

> [!NOTE]
> **SPM como resolvedor de dependencias**
>
> El enfoque recomendado por Tuist para las dependencias utiliza el Swift Package Manager (SPM) únicamente para resolverlas. Luego, Tuist las convierte en proyectos y targets de Xcode para ofrecer la máxima configurabilidad y control.


## Visualizar el proyecto {#visualize-the-project}

Puedes visualizar la estructura del proyecto ejecutando:

```bash
tuist graph
```

El comando generará y abrirá un archivo `graph.png` en el directorio del proyecto:

![Grafo del proyecto](/images/guides/quick-start/graph.png)

## Usar la dependencia {#use-the-dependency}

Ejecuta `tuist generate` para abrir el proyecto en Xcode y realiza los siguientes cambios en el archivo `ContentView.swift`:

```swift
import SwiftUI
import Kingfisher // [!code ++]

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("Hello, World!") // [!code --]
            .padding() // [!code --]
        KFImage(URL(string: "https://cloud.tuist.io/images/tuist_logo_32x32@2x.png")!) // [!code ++]
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

Ejecuta la app desde Xcode y deberías ver la imagen cargada desde la URL.
