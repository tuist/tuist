---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 插件{#plugins}

插件是跨多个项目共享和复用Tuist工件的工具。支持以下工件类型：

- <LocalizedLink href="/guides/features/projects/code-sharing">项目描述助手</LocalizedLink>跨多个项目。
- <LocalizedLink href="/guides/features/projects/templates">跨多个项目的模板</LocalizedLink>。
- 跨多个项目的任务。
- <LocalizedLink href="/guides/features/projects/synthesized-files">跨多个项目的资源访问器</LocalizedLink>模板

请注意，插件旨在为扩展Tuist功能提供简便途径。因此存在某些限制需予以考虑：****

- 插件不能依赖于另一个插件。
- 插件不能依赖第三方Swift包
- 插件不能使用调用该插件的项目中的项目描述辅助函数。

若需更灵活的处理方式，可考虑为该工具提交功能建议，或基于Tuist生成框架[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)构建自有解决方案。

## 插件类型{#plugin-types}

### 项目描述辅助插件{#project-description-helper-plugin}

项目描述辅助插件由以下目录构成：`包含声明插件名称的 manifest 文件 Plugin.swift` ` 包含辅助 Swift 文件的
ProjectDescriptionHelpers 目录`

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

若需共享<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">合成资源访问器</LocalizedLink>，可使用此类插件。该插件由以下目录构成：`Plugin.swift`
（声明插件名称的清单文件）`ResourceSynthesizers` （包含资源访问器模板文件的目录）


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

模板名称采用资源类型的驼峰式命名法：

| 资源类型  | 模板文件名                      |
| ----- | -------------------------- |
| 弦乐    | `字符串模板`                    |
| 资产    | `Assets.stencil`           |
| 属性列表  | `Plists.stencil`           |
| 字体    | `字体模板`                     |
| 核心数据  | `CoreData.stencil`         |
| 界面构建器 | `InterfaceBuilder.stencil` |
| JSON  | `JSON.stencil`             |
| YAML  | `YAML.stencil`             |

在项目中定义资源合成器时，可通过指定插件名称来使用插件提供的模板：

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 任务插件 <Badge type="warning" text="deprecated" />{#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
任务插件已弃用。若需为项目寻找自动化解决方案，请参阅[这篇博客文章](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)。
<!-- -->
:::

任务是`$PATH`-exposed可执行文件，若遵循命名规范`tuist-<task-name>` ，则可通过`tuist`
命令调用。早期版本中，Tuist在`tuist plugin`
提供了一些弱规范工具，用于构建Swift包中的可执行文件任务：`build`,`run`,`test` 及`archive`
。但因该功能增加工具维护负担与复杂度，现已弃用。</task-name>

若您使用Tuist分配任务，建议构建您的
- 您仍可使用随Tuist版本发布的`ProjectAutomation.xcframework` ，通过`let graph = try
  Tuist.graph()` 在逻辑中访问项目图。该命令使用系统进程运行`tuist` 命令，并返回项目图的内存表示。
- 为分发任务，建议在GitHub发布中包含支持`arm64` 和`x86_64`
  的胖二进制文件，并使用[Mise](https://mise.jdx.dev)作为安装工具。需创建插件仓库来指导Mise安装您的工具，可参考[Tuist's](https://github.com/asdf-community/asdf-tuist)实现方案。
- 若将工具命名为`tuist-{xxx}` ，用户可通过运行`mise install` 安装。安装后既可直接调用，也可通过`tuist xxx` 间接调用。

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
我们计划将`的ProjectAutomation（` ）与`的XcodeGraph（`
）整合为单一向后兼容框架，向用户完整呈现项目图谱。此外，我们将把生成逻辑提取至新层级`XcodeGraph（`
），您亦可将其用于自定义命令行界面。可将其视为构建专属的Tuist。
<!-- -->
:::

## 使用插件{#using-plugins}

要使用插件，需将其添加到项目<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>清单文件中：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

若需在不同仓库的项目间复用插件，可将插件推送到Git仓库，并在`的Tuist.swift文件中通过` 引用：

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

安装插件后，执行 ``tuist install` ` 命令将把插件下载至全局缓存目录。

::: info NO VERSION RESOLUTION
<!-- -->
如您所见，我们不提供插件的版本解析功能。建议使用Git标签或SHA值确保可重现性。
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
使用项目描述辅助工具插件时，包含辅助工具的模块名称即为插件名称
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
