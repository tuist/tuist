---
title: Добавление зависимостей
titleTemplate: :title · Начало · Руководства · Tuist
description: Научитесь добавлять зависимости к вашему первому Swift проекту
---

# Добавление зависимостей {#add-dependencies}

Часто проекты зависят от сторонних библиотек для обеспечения дополнительной функциональности. Для того чтобы улучшить опыт редактирования вашего проекта, воспользуемтесь командой:

```bash
tuist edit
```

Откроется проект Xcode, содержащий файлы вашего проекта. Отредактируйте файл Package.swift и добавьте

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

Затем отредактируйте таргет приложения в вашем проекте, чтобы объявить Kingfisher как зависимость:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

Затем выполните команду tuist install, чтобы разрешить и загрузить зависимости с использованием [Swift Package Manager](https://www.swift.org/documentation/package-manager/).

> [!NOTE] SPM в качестве средства разрешения зависимостей
> Рекомендуемый подход Tuist к управлению зависимостями предполагает использование Swift Package Manager (SPM) только для разрешения зависимостей. Затем Tuist преобразует их в Xcode проекты и таргеты для максимальной настраиваемости и контроля.

## Визуализируйте проект {#visualize-the-project}

Вы можете визуализировать структуру проекта, запустив команду:

```bash
tuist graph
```

Команда создаст и откроет файл graph.png в директории проекта:

![Project graph](/images/guides/quick-start/graph.png)

## Использование зависимости {#use-the-dependency}

Запустите tuist generate, чтобы открыть проект в Xcode, и внесите следующие изменения в файл ContentView.swift:

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
