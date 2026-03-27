---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Добавление зависимостей {#add-dependencies}

Обычно проекты зависят от сторонних библиотек, которые предоставляют
дополнительную функциональность. Чтобы добавить их и получить наилучший опыт при
редактировании проекта, выполните следующую команду:

```bash
tuist edit
```

Откроется проект Xcode, содержащий файлы вашего проекта. Отредактируйте файл
`Package.swift` и добавьте

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

Затем отредактируйте application target в проекте, указав `Kingfisher` в
качестве зависимости:

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

Затем выполните команду `tuist install`, чтобы разрешить и извлечь зависимости с
помощью [Swift Package
Manager](https://www.swift.org/documentation/package-manager/).

::: info SPM КАК СРЕДСТВО РАЗРЕШЕНИЯ ЗАВИСИМОСТЕЙ
<!-- -->
Рекомендуемый Tuist подход к управлению зависимостями использует Swift Package
Manager (SPM) только для их разрешения. Затем Tuist преобразует их в проекты и
цели Xcode для обеспечения максимальной гибкости настройки и контроля.
<!-- -->
:::

## Визуализация проекта {#visualize-the-project}

Вы можете визуализировать структуру проекта, выполнив:

```bash
tuist graph
```

Команда создаст и откроет файл `graph.png` в директории проекта:

![Project graph](/images/guides/quick-start/graph.png)

## Использование зависимости {#use-the-dependency}

Запустите `tuist generate`, чтобы открыть проект в Xcode, и внесите следующие
изменения в файл `contentView.swift`:

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

Запустите приложение из Xcode, и вы должны увидеть изображение, загруженное с
URL-адреса.
