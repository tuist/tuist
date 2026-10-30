---
{
  "title": "创建新项目",
  "titleTemplate": ":title · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何使用 Tuist 创建新项目。"
}
---
# 创建新项目 {#create-a-new-project}

使用 Tuist 启动新项目最直接的方式是运行 `tuist init` 命令。该命令会启动一个交互式 CLI，引导你完成项目设置。在提示时，请务必选择创建“生成式项目”的选项。

随后，你可以运行 `tuist edit` 来 <.localized_link href="/guides/features/projects/editing">编辑项目</.localized_link>，Xcode 将打开该项目供你编辑。生成的文件之一是 `Project.swift`，其中包含项目的定义。如果你熟悉 Swift Package Manager，可以将其视为 `Package.swift`，但使用的是 Xcode 项目的术语。

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
> 我们有意保持可用模板列表简短，以最小化维护开销。如果你想创建一个不代表应用程序的项目（例如框架），可以将 `tuist init` 作为起点，然后修改生成的项目以满足你的需求。


## 手动创建项目 {#manually-creating-a-project}

或者，你也可以手动创建项目。我们建议仅在你已经熟悉 Tuist 及其概念时才这样做。你需要做的第一件事是为项目结构创建额外的目录：

```bash
mkdir MyFramework
cd MyFramework
```

然后创建一个 `Tuist.swift` 文件，用于配置 Tuist 并帮助 Tuist 确定项目的根目录，以及一个 `Project.swift`，用于声明你的项目：

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
> Tuist 使用 `Tuist/` 目录来确定项目的根目录，并从那里通过通配符搜索其他清单文件。我们建议使用你喜欢的编辑器创建这些文件，之后你可以使用 `tuist edit` 在 Xcode 中编辑项目。
