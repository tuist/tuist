---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Adicionar dependências {#add-dependencies}

É comum que os projectos dependam de bibliotecas de terceiros para fornecer
funcionalidades adicionais. Para tal, execute o seguinte comando para ter a
melhor experiência de edição do seu projeto:

```bash
tuist edit
```

Será aberto um projeto Xcode com os seus ficheiros de projeto. Edite o arquivo
`Package.swift` e adicione o

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

Em seguida, edite o destino da aplicação no seu projeto para declarar
`Kingfisher` como uma dependência:

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

Em seguida, execute `tuist install` para resolver e obter as dependências usando
o [Swift Package Manager](https://www.swift.org/documentation/package-manager/).

> [O SPM COMO RESOLVEDOR DE DEPENDÊNCIAS A abordagem recomendada pelo Tuist para
> dependências usa o Swift Package Manager (SPM) apenas para resolver
> dependências. O Tuist então as converte em projetos e alvos do Xcode para
> máxima configurabilidade e controle.

## Visualizar o projeto {#visualize-the-project}

É possível visualizar a estrutura do projeto executando:

```bash
tuist graph
```

O comando produzirá e abrirá um ficheiro `graph.png` no diretório do projeto:

![Gráfico do projeto](/images/guides/quick-start/graph.png)

## Utilizar a dependência {#use-the-dependency}

Execute `tuist generate` para abrir o projeto no Xcode e faça as seguintes
alterações no ficheiro `ContentView.swift`:

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

Execute a aplicação a partir do Xcode e deverá ver a imagem carregada a partir
do URL.
