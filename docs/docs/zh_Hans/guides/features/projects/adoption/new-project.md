---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 创建新项目{#create-a-new-project}

使用 Tuist 启动新项目的最直接方法是使用`tuist init` 命令。该命令会启动一个交互式 CLI，引导您完成项目设置。出现提示时，请确保选择创建
"生成项目 "选项。

然后，您可以 <LocalizedLink href="/guides/features/projects/editing"> 编辑项目</LocalizedLink>，运行`tuist edit` ，Xcode
将打开一个项目，您可以在其中编辑项目。生成的文件之一是`Project.swift` ，其中包含项目定义。如果您熟悉 Swift
包管理器，可以将其理解为`Package.swift` ，但要使用 Xcode 项目的行话。

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
我们有意保持可用模板列表的简短，以尽量减少维护开销。如果你想创建一个不代表应用程序的项目，例如一个框架，你可以使用`tuist init`
作为起点，然后根据你的需要修改生成的项目。
<!-- -->
:::

## 手动创建项目{#manually-creating-a-project}

或者，您也可以手动创建项目。我们建议您在已经熟悉 Tuist 及其概念的情况下才这样做。首先需要为项目结构创建附加目录：

```bash
mkdir MyFramework
cd MyFramework
```

然后创建`Tuist.swift` 文件，用于配置 Tuist 并由 Tuist 确定项目的根目录，并创建`Project.swift` ，在此声明您的项目：

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
Tuist 会使用`Tuist/`
目录来确定项目的根目录，并从该目录中查找屏蔽目录的其他清单文件。我们建议您使用自己选择的编辑器创建这些文件，然后就可以使用`tuist edit` 通过
Xcode 编辑项目了。
<!-- -->
:::
