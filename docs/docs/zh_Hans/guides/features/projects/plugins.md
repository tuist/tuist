---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 插件{#plugins}

插件是用于在多个项目间共享和复用 Tuist 构建成果的工具。支持以下构建成果：

- <LocalizedLink href="/guides/features/projects/code-sharing">跨多个项目的项目描述助手</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">跨多个项目的模板</LocalizedLink>。
- 跨多个项目的任务。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨多个项目的资源访问器</LocalizedLink>模板

请注意，插件的设计初衷是作为扩展 Tuist 功能的简便方式。因此，**存在一些需要考虑的限制**:

- 一个插件不能依赖另一个插件。
- 插件不能依赖第三方 Swift 包
- 插件无法使用调用该插件的项目的项目描述辅助函数。

如果您需要更大的灵活性，可以考虑为该工具提交功能建议，或者基于 Tuist 的生成框架
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)
构建自己的解决方案。

## 插件类型{#plugin-types}

### 项目描述辅助插件{#project-description-helper-plugin}

项目描述辅助插件由一个目录表示，该目录包含一个声明插件名称的 ``Plugin.swift`` 清单文件，以及一个包含辅助 Swift 文件的
``ProjectDescriptionHelpers`` 目录。

代码组
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

### 资源访问器模板插件{#resource-accessor-templates-plugin}

如果您需要共享
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成资源访问器</LocalizedLink>，可以使用此类插件。该插件由一个目录表示，其中包含一个声明插件名称的`Plugin.swift`
清单文件，以及一个包含资源访问器模板文件的`ResourceSynthesizers` 目录。


代码组
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

模板名称是资源类型的 [驼峰式命名法](https://en.wikipedia.org/wiki/Camel_case) 版本：

| 资源类型  | 模板文件名                      |
| ----- | -------------------------- |
| 弦乐    | `字符串模板`                    |
| 资源    | `Assets.stencil`           |
| 属性列表  | `Plists.stencil`           |
| 字体    | `字体模板`                     |
| 核心数据  | `CoreData.stencil`         |
| 界面构建器 | `InterfaceBuilder.stencil` |
| JSON  | `JSON.stencil`             |
| YAML  | `YAML.stencil`             |

在项目中定义资源合成器时，您可以指定插件名称以使用该插件的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任务插件 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任务插件已弃用。如果您正在为项目寻找自动化解决方案，请参阅[这篇博客文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任务是`$PATH`- 通过`tuist` 命令可调用的公开可执行文件，前提是它们遵循命名约定`tuist-<task-name>` 。在早期版本中，Tuist
曾在`tuist plugin` 下提供了一些简单的约定和工具，用于`构建` 、`运行` 、`测试` 以及`归档` 任务（这些任务由 Swift
包中的可执行文件表示），但我们已弃用此功能，因为它增加了工具的维护负担和复杂性。</task-name>

如果您使用 Tuist 进行任务分发，我们建议您构建您的
- 您可以继续使用随每个 Tuist 版本发布的`ProjectAutomation.xcframework` ，通过`let graph = try
  Tuist.graph()` 在逻辑中访问项目图。该命令使用系统进程运行`tuist` 命令，并返回项目图的内存表示。
- 为了分发任务，我们建议在 GitHub 发布中包含支持`arm64` 和`x86_64` 的 fat 二进制文件，并使用
  [Mise](https://mise.jdx.dev) 作为安装工具。要指导 Mise 如何安装您的工具，您需要一个插件仓库。您可以参考
  [Tuist](https://github.com/asdf-community/asdf-tuist) 的做法。
- 如果您将工具命名为`tuist-{xxx}` ，用户可以通过运行`mise install` 进行安装，他们既可以直接调用该工具，也可以通过`tuist
  xxx` 运行它。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我们计划将`ProjectAutomation` 和`XcodeGraph`
的模型整合为一个向后兼容的框架，该框架将向用户完整展示项目图。此外，我们将把生成逻辑提取到一个新层中，即`XcodeGraph` ，您也可以在自己的命令行界面
(CLI) 中使用它。您可以将其视为构建您自己的 Tuist。
<!-- -->
:::

## 使用插件{#using-plugins}

要使用插件，您需要将其添加到项目的
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
清单文件中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

若需在不同仓库中的项目间复用插件，可将插件推送到 Git 仓库，并在`Tuist.swift` 文件中引用该插件：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

安装插件后，执行`tuist install` 命令将把插件下载到全局缓存目录中。

::: info NO VERSION RESOLUTION
<!-- -->
您可能已经注意到，我们不提供插件的版本解析功能。我们建议使用 Git 标签或 SHA 值来确保可重现性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用项目描述辅助程序插件时，包含这些辅助程序的模块名称即为插件名称
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
