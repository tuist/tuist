---
{
  "title": "创建生成式项目",
  "titleTemplate": ":title · Xcode · 教程 · Tuist",
  "description": "了解如何创建你的首个由 Tuist 生成的 Xcode 项目并为其添加依赖"
}
---
# 创建生成式项目 {#create-a-generated-project}

在任何目录或现有项目的目录中开始使用 Tuist 的最简单方法：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

该命令将引导你完成 <.localized_link href="/guides/features/projects">创建生成式项目</.localized_link> 或集成现有 Xcode 项目或工作区的步骤。它帮助你将本地设置连接到远程服务器，让你能够使用 <.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link>、<.localized_link href="/guides/features/previews">预览</.localized_link> 和 <.localized_link href="/guides/features/package-registries/swift">注册表</.localized_link> 等功能。

> [!NOTE]
> **迁移现有项目**
>
> 如果你希望将现有项目迁移到生成式项目以改善开发体验并利用我们的 <.localized_link href="/guides/features/cache">缓存</.localized_link>，请查看我们的 <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">迁移指南</.localized_link>。


## 添加依赖项 {#add-dependencies}

项目通常依赖第三方库来提供额外功能。为此，请运行以下命令以获得最佳的项目编辑体验：

```bash
tuist edit
```

系统将打开一个包含你项目文件的 Xcode 项目。编辑 `Package.swift` 并添加

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

然后编辑项目中的应用目标，将 `Kingfisher` 声明为依赖项：

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

然后运行 `tuist install`，使用 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解析并拉取依赖项。

> [!NOTE]
> **使用 SPM 作为依赖解析器**
>
> Tuist 推荐的依赖管理方法仅使用 Swift Package Manager (SPM) 来解析依赖项。随后，Tuist 会将它们转换为 Xcode 项目和目标，以实现最大的可配置性和控制力。


## 可视化项目结构 {#visualize-the-project}

你可以通过运行以下命令来可视化项目结构：

```bash
tuist graph
```

该命令将在项目目录中输出并打开一个 `graph.png` 文件：

![项目依赖图](/images/guides/quick-start/graph.png)

## 使用依赖项 {#use-the-dependency}

运行 `tuist generate` 在 Xcode 中打开项目，并对 `ContentView.swift` 文件进行以下更改：

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

从 Xcode 运行应用，你应该能看到从 URL 加载的图片。
