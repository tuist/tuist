---
{
  "title": "插件",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 中创建和使用插件以扩展其功能。"
}
---
# 插件 {#plugins}

插件是一种在多个项目之间共享和复用 Tuist 构件的工具。支持以下构件：

- <.localized_link href="/guides/features/projects/code-sharing">跨多个项目的</.localized_link>项目描述辅助工具
- <.localized_link href="/guides/features/projects/templates">跨多个项目的</.localized_link>模板
- 跨多个项目的任务
- <.localized_link href="/guides/features/projects/synthesized-files">跨多个项目的</.localized_link>资源访问器模板

请注意，插件旨在提供一种扩展 Tuist 功能的简单方式。因此，有**一些限制需要考虑**：

- 插件不能依赖其他插件。
- 插件不能依赖第三方 Swift 包
- 插件不能使用使用该插件的项目中的项目描述辅助工具。

如果你需要更高的灵活性，可以考虑为工具提出功能建议，或者基于 Tuist 的生成框架 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator) 构建你自己的解决方案。

## 插件类型 {#plugin-types}

### 项目描述辅助插件 {#project-description-helper-plugin}

项目描述辅助插件由一个目录表示，该目录包含声明插件名称的 `Plugin.swift` 清单文件，以及包含辅助 Swift 文件的 `ProjectDescriptionHelpers` 目录。

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### 资源访问器模板插件 {#resource-accessor-templates-plugin}

如果你需要共享<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">合成的资源访问器</.localized_link>，可以使用此类插件。该插件由一个目录表示，该目录包含声明插件名称的 `Plugin.swift` 清单文件，以及包含资源访问器模板文件的 `ResourceSynthesizers` 目录。


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

模板的名称是资源类型的[小驼峰式](https://en.wikipedia.org/wiki/Camel_case)版本：

| 资源类型 | 模板文件名 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

在项目中定义资源合成器时，你可以指定插件名称以使用来自该插件的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任务插件 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **已弃用**
>
> 任务插件已弃用。如果你正在为项目寻找自动化解决方案，请参阅[这篇博客文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。


任务是 `$PATH` 暴露的可执行文件，如果遵循 `tuist-<task-name>` 命名约定，则可以通过 `tuist` 命令调用。在早期版本中，Tuist 在 `tuist plugin` 下提供了一些较弱的约定和工具，用于 `build`、`run`、`test` 和 `archive` 由 Swift 包中的可执行文件表示的任务，但由于这增加了工具的维护负担和复杂性，我们已弃用此功能。

如果你曾使用 Tuist 分发任务，我们建议你构建自己的
- 你可以继续使用随每个 Tuist 版本分发的 `ProjectAutomation.xcframework`，通过 `let graph = try Tuist.graph()` 从你的逻辑中访问项目图。该命令使用系统进程运行 `tuist` 命令，并返回项目图的内存表示。
- 为了分发任务，我们建议在 GitHub 发布中包含支持 `arm64` 和 `x86_64` 的通用二进制文件，并使用 [Mise](https://mise.jdx.dev) 作为安装工具。要指导 Mise 如何安装你的工具，你需要一个插件仓库。你可以参考 [Tuist 的](https://github.com/asdf-community/asdf-tuist)。
- 如果你将工具命名为 `tuist-{xxx}`，并且用户可以通过运行 `mise install` 进行安装，那么他们可以直接调用它，或者通过 `tuist xxx` 运行它。

> [!NOTE]
> **ProjectAutomation 的未来**
>
> 我们计划将 `ProjectAutomation` 和 `XcodeGraph` 的模型合并为一个向后兼容的框架，向用户公开完整的项目图。此外，我们将把生成逻辑提取到一个新的层 `XcodeGraph` 中，你也可以在自己的 CLI 中使用它。可以将其视为构建你自己的 Tuist。


## 使用插件 {#using-plugins}

要使用插件，你必须将其添加到项目的 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 清单文件中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

如果你想在位于不同仓库的项目之间复用插件，可以将插件推送到 Git 仓库，并在 `Tuist.swift` 文件中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加插件后，`tuist install` 将在一个全局缓存目录中获取插件。

> [!NOTE]
> **无版本解析**
>
> 如你可能注意到的那样，我们不为插件提供版本解析。我们建议使用 Git 标签或 SHA 以确保可重现性。


> [!TIP]
> **项目描述辅助插件**
>
> 使用项目描述辅助插件时，包含辅助工具的模块名称即为插件名称
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
