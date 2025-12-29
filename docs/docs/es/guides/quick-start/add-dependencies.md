---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Añadir dependencias {#add-dependencies}

Es común que los proyectos dependan de bibliotecas de terceros para proporcionar
funcionalidad adicional. Para ello, ejecuta el siguiente comando para tener la
mejor experiencia editando tu proyecto:

```bash
tuist edit
```

Se abrirá un proyecto Xcode que contendrá los archivos de tu proyecto. Edite el
archivo `Package.swift` y añada el archivo

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

A continuación, edite el objetivo de la aplicación en su proyecto para declarar
`Kingfisher` como dependencia:

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

A continuación, ejecute `tuist install` para resolver y extraer las dependencias
mediante el [Gestor de paquetes
Swift](https://www.swift.org/documentation/package-manager/).

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
El enfoque recomendado por Tuist para las dependencias utiliza el Gestor de
Paquetes Swift (SPM) sólo para resolver las dependencias. A continuación, Tuist
las convierte en proyectos y objetivos de Xcode para ofrecer la máxima
configurabilidad y control.
<!-- -->
:::

## Visualizar el proyecto {#visualize-the-project}

Puede visualizar la estructura del proyecto ejecutando:

```bash
tuist graph
```

El comando generará y abrirá un archivo `graph.png` en el directorio del
proyecto:

[Gráfico del proyecto](/images/guides/quick-start/graph.png)

## Utilizar la dependencia {#use-the-dependency}

Ejecute `tuist generate` para abrir el proyecto en Xcode, y realice los
siguientes cambios en el archivo `ContentView.swift`:

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

Ejecute la aplicación desde Xcode, y debería ver la imagen cargada desde la URL.
