---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 添加依赖项{#add-dependencies}

项目常需依赖第三方库以实现扩展功能。为获得最佳编辑体验，请执行以下命令：

```bash
tuist edit
```

Xcode项目将自动打开并包含您的项目文件。编辑`目录下的Package.swift文件，在` 路径下添加以下内容：

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

然后在项目中编辑应用程序目标，将`Kingfisher` 声明为依赖项：

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

然后运行`tuist install` 通过[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)解决并拉取依赖项。

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist推荐的依赖管理方案仅使用Swift Package Manager (SPM)
解决依赖问题。随后Tuist将这些依赖转换为Xcode项目和目标，以实现最大程度的可配置性和控制力。
<!-- -->
:::

## 可视化项目{#visualize-the-project}

可通过运行以下命令可视化项目结构：

```bash
tuist graph
```

该命令将在项目目录中输出并打开`graph.png` 文件：

![项目图](/images/guides/quick-start/graph.png)

## 使用依赖项{#use-the-dependency}

运行`tuist generate` 在 Xcode 中打开项目，并对`ContentView.swift 文件进行以下修改：`

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

在Xcode中运行应用程序，您应能看到从URL加载的图像。
