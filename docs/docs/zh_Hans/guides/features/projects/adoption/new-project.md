---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 创建新项目{#create-a-new-project}

使用 Tuist 启动新项目的最简单方法是执行`tuist init`
命令。该命令将启动一个交互式命令行界面，引导您完成项目设置。在系统提示时，请务必选择创建“生成项目”的选项。

随后，您可以通过运行`tuist edit` 来
<LocalizedLink href="/guides/features/projects/editing">编辑该项目</LocalizedLink>，Xcode
将打开一个项目供您进行编辑。生成的文件之一是`Project.swift` ，其中包含项目的定义。如果您熟悉 Swift Package
Manager，可以将其视为`Package.swift` ，只不过采用了 Xcode 项目的术语。

代码组
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

信息
<!-- -->
我们特意将可用模板列表保持简短，以尽量减少维护工作量。如果您想创建一个不代表应用程序的项目（例如框架），可以使用`tuist init`
作为起点，然后根据需要修改生成的项目。
<!-- -->
:::

## 手动创建项目{#manually-creating-a-project}

或者，您可以手动创建项目。我们建议仅在您已熟悉 Tuist 及其相关概念时才采用此方法。首先，您需要为项目结构创建额外的目录：

```bash
mkdir MyFramework
cd MyFramework
```

然后创建一个`Tuist.swift` 文件，该文件将配置 Tuist 并用于确定项目的根目录；同时创建一个`Project.swift`
文件，用于声明您的项目：

代码组
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

:: 警告
<!-- -->
Tuist 通过`Tuist/` 目录来确定项目的根目录，并以此为起点，通过通配符查找其他 manifests
文件。我们建议您使用自己喜欢的编辑器创建这些文件，之后即可使用`tuist edit` 命令在 Xcode 中编辑项目。
<!-- -->
:::
