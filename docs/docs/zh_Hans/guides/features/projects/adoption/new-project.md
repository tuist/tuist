---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 创建新项目{#create-a-new-project}

使用Tuist创建新项目的最简便方式是执行`命令：tuist init`
。该命令将启动交互式命令行界面，引导您完成项目配置。在提示时，请务必选择创建"生成项目"的选项。

随后可通过运行`tuist
edit`<LocalizedLink href="/guides/features/projects/editing">编辑项目</LocalizedLink>，Xcode将打开可编辑的项目。生成的文件之一是`Project.swift`
，其中包含项目定义。若您熟悉Swift Package Manager，可将其视为`Package.swift` 的Xcode项目版本。

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
为减少维护负担，我们刻意将可用模板列表保持精简。若需创建非应用程序类型的项目（如框架），可使用 ``` 或 `tuist init` `
作为起点，随后根据需求修改生成的项目。
<!-- -->
:::

## 手动创建项目{#manually-creating-a-project}

或者，您也可以手动创建项目。我们建议仅在您已熟悉 Tuist 及其概念时才采用此方法。首先需要为项目结构创建额外的目录：

```bash
mkdir MyFramework
cd MyFramework
```

然后创建`文件Tuist.swift` ，该文件用于配置Tuist并确定项目根目录；另创建`文件Project.swift` ，用于声明项目：

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
Tuist通过`Tuist/` 目录确定项目根目录，并由此通过目录通配符查找其他清单文件。建议使用您偏好的编辑器创建这些文件，之后可通过`tuist edit`
命令使用Xcode编辑项目。
<!-- -->
:::
