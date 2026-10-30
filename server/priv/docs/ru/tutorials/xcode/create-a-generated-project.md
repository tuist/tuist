---
{
  "title": "Создание сгенерированного проекта",
  "titleTemplate": ":title · Xcode · Обучающие материалы · Tuist",
  "description": "Узнайте, как создать свой первый проект Xcode, сгенерированный Tuist, и добавить в него зависимости"
}
---
# Создание сгенерированного проекта {#create-a-generated-project}

Самый простой способ начать работу с Tuist в любом каталоге или в каталоге существующего проекта:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

Команда проведет вас через шаги по <.localized_link href="/guides/features/projects">созданию сгенерированного проекта</.localized_link> или интеграции существующего проекта или рабочей области Xcode. Она поможет подключить вашу среду к удаленному серверу, предоставив доступ к таким возможностям, как <.localized_link href="/guides/features/selective-testing">выборочное тестирование</.localized_link>, <.localized_link href="/guides/features/previews">превью</.localized_link> и <.localized_link href="/guides/features/package-registries/swift">реестр</.localized_link>.

> [!NOTE]
> **Миграция существующего проекта**
>
> Если вы хотите перенести существующий проект на сгенерированные проекты, чтобы улучшить опыт разработки и воспользоваться нашим <.localized_link href="/guides/features/cache">кэшем</.localized_link>, ознакомьтесь с нашим <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">руководством по миграции</.localized_link>.


## Добавление зависимостей {#add-dependencies}

Проекты часто зависят от сторонних библиотек для предоставления дополнительной функциональности. Для этого выполните следующую команду, чтобы получить наилучший опыт редактирования вашего проекта:

```bash
tuist edit
```

Откроется проект Xcode, содержащий файлы вашего проекта. Отредактируйте `Package.swift` и добавьте

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

Затем отредактируйте цель приложения в вашем проекте, чтобы объявить `Kingfisher` зависимостью:

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

Затем выполните `tuist install`, чтобы разрешить и загрузить зависимости с помощью [Swift Package Manager](https://www.swift.org/documentation/package-manager/).

> [!NOTE]
> **SPM как средство разрешения зависимостей**
>
> Рекомендуемый Tuist подход к зависимостям использует Swift Package Manager (SPM) только для разрешения зависимостей. Затем Tuist преобразует их в проекты и цели Xcode для максимальной гибкости настройки и контроля.


## Визуализация проекта {#visualize-the-project}

Вы можете визуализировать структуру проекта, выполнив:

```bash
tuist graph
```

Команда создаст и откроет файл `graph.png` в каталоге проекта:

![Граф проекта](/images/guides/quick-start/graph.png)

## Использование зависимости {#use-the-dependency}

Выполните `tuist generate`, чтобы открыть проект в Xcode, и внесите следующие изменения в файл `ContentView.swift`:

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

Запустите приложение из Xcode, и вы должны увидеть изображение, загруженное по URL.
