---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 插件{#plugins}

插件是在多个项目中共享和重用 Tuist 工具的工具。支持以下工件：

- <LocalizedLink href="/guides/features/projects/code-sharing">跨多个项目的项目描述助手</LocalizedLink>。
- <LocalizedLink href="/guides/features/projects/templates">跨多个项目的模板</LocalizedLink>。
- 跨多个项目的任务。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨多个项目的资源访问器</LocalizedLink>模板

请注意，插件的设计初衷是作为扩展 Tuist 功能的一种简单方式。因此，**，需要考虑一些限制** ：

- 一个插件不能依赖于另一个插件。
- 插件不能依赖第三方 Swift 软件包
- 插件不能使用使用该插件的项目中的项目描述助手。

如果您需要更多灵活性，可以考虑为工具提出功能建议，或者在 Tuist 的生成框架
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)
上构建自己的解决方案。

## 插件类型{#plugin-types}

### 项目描述辅助插件{#project-description-helper-plugin}

项目描述辅助插件由一个目录表示，该目录包含一个`Plugin.swift` manifest
文件，其中声明了插件的名称，以及一个`ProjectDescriptionHelpers` 目录，其中包含辅助 Swift 文件。

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

如果需要共享<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成的资源访问器</LocalizedLink>，可以使用这种类型的插件。插件由一个包含`Plugin.swift`
manifest 文件（声明插件名称）和`ResourceSynthesizers` 目录（包含资源访问器模板文件）的目录表示。


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

模板名称是资源类型的 [camel case](https://en.wikipedia.org/wiki/Camel_case) 版本：

| 资源类型  | 模板文件名称                     |
| ----- | -------------------------- |
| 弦乐    | `字符串模板`                    |
| 资产    | `Assets.stencil`           |
| 财产清单  | `Plists.stencil`           |
| 字体    | `字体模板`                     |
| 核心数据  | `CoreData.stencil`         |
| 界面生成器 | `InterfaceBuilder.stencil` |
| JSON  | `JSON.stencil`             |
| YAML  | `YAML.stencil`             |

在项目中定义资源合成器时，可以指定插件名称，以便使用插件中的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任务插件 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任务插件已过时。如果您正在为您的项目寻找自动化解决方案，请查看
[本博文](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任务是`$PATH`-exposed executables（暴露的可执行文件），如果它们遵循命名规范`tuist-<task-name>`
，则可通过`tuist` 命令调用。在早期版本中，Tuist 在`tuist plugin`
下提供了一些弱约定和工具，用于`build`,`run`,`test` 和`archive` 任务，这些任务由 Swift
包中的可执行文件表示，但我们已弃用这一功能，因为它增加了工具的维护负担和复杂性。

如果您使用 Tuist 来分发任务，我们建议您构建自己的
- 您可以继续使用随每个 Tuist 版本发布的`ProjectAutomation.xcframework` ，通过`let graph = try
  Tuist.graph()` 从逻辑中访问项目图。该命令使用系统进程运行`tuist` 命令，并返回项目图的内存表示。
- 要发布任务，我们建议在 GitHub 发布中加入支持`arm64` 和`x86_64` 的胖二进制文件，并使用
  [Mise](https://mise.jdx.dev) 作为安装工具。要指导 Mise 如何安装你的工具，你需要一个插件仓库。您可以使用
  [Tuist's](https://github.com/asdf-community/asdf-tuist) 作为参考。
- 如果将工具命名为`tuist-{xxx}` ，用户可以通过运行`mise install` 来安装它，他们可以直接调用它，也可以通过`tuist xxx`
  运行它。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我们计划将`ProjectAutomation` 和`XcodeGraph`
的模型合并为一个单一的向后兼容框架，向用户公开项目图的整体性。此外，我们还将把生成逻辑提取到一个新的层中，即`XcodeGraph` ，您也可以通过自己的
CLI 使用该层。将其视为构建您自己的 Tuist。
<!-- -->
:::

## 使用插件{#using-plugins}

要使用插件，必须将其添加到项目的
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

如果想在不同版本库的项目中重复使用插件，可以将插件推送到 Git 版本库，并在`Tuist.swift` 文件中引用它：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

添加插件后，`tuist install` 将从全局缓存目录中获取插件。

::: info NO VERSION RESOLUTION
<!-- -->
您可能已经注意到，我们不提供插件的版本解析。我们建议使用 Git 标签或 SHA 以确保可重复性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用项目描述帮助插件时，包含帮助程序的模块名称就是插件名称
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
