---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Добавьте зависимости {#add-dependencies}

Обычно проекты зависят от сторонних библиотек, предоставляющих дополнительную
функциональность. Для этого выполните следующую команду, чтобы получить
наилучший опыт редактирования проекта:

```bash
tuist edit
```

Откроется проект Xcode, содержащий файлы вашего проекта. Отредактируйте файл
`Package.swift` и добавьте файл

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

Затем отредактируйте целевое приложение в вашем проекте, чтобы объявить
`Kingfisher` в качестве зависимости:

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

Затем выполните `tuist install`, чтобы разрешить и извлечь зависимости с помощью
[Swift Package Manager](https://www.swift.org/documentation/package-manager/).

> [!ПРИМЕЧАНИЕ] SPM КАК РЕСОРВЕР ЗАВИСИМОСТЕЙ Рекомендуемый Tuist подход к
> зависимостям использует менеджер пакетов Swift (SPM) только для разрешения
> зависимостей. Затем Tuist преобразует их в проекты и цели Xcode для
> максимальной конфигурации и контроля.

## Визуализируйте проект {#visualize-the-project}

Вы можете визуализировать структуру проекта, выполнив команду:

```bash
tuist graph
```

Команда выведет и откроет файл `graph.png` в директории проекта:

![Граф проекта](/images/guides/quick-start/graph.png)

## Используйте зависимость {#use-the-dependency}

Запустите `tuist generate`, чтобы открыть проект в Xcode, и внесите следующие
изменения в файл `ContentView.swift`:

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

Запустите приложение из Xcode, и вы увидите изображение, загруженное по URL.
