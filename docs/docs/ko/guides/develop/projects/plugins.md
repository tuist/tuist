---
title: Plugins
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist에서 Plugin을 생성하고 사용하여 기능을 확장하는 방법을 알아보세요.
---

# Plugins {#plugins}

Plugin은 여러 프로젝트에서 Tuist 아티팩트를 공유하고 재사용할 수 있는 도구입니다. 지원되는 아티팩트는 다음과 같습니다:

- <LocalizedLink href="/guides/develop/projects/code-sharing">Project description helpers</LocalizedLink>를 여러 프로젝트에서 사용.
- <LocalizedLink href="/guides/develop/projects/templates"> Templates</LocalizedLink>을 여러 프로젝트에서 사용.
- Tasks를 여러 프로젝트에서 사용.
- <LocalizedLink href="/guides/develop/projects/synthesized-files">Resource accessor</LocalizedLink> 템플릿을 여러 프로젝트에서 사용.

Plugin은 Tuist의 기능을 확장하기 위한 간단한 방법으로 설계되었습니다. 따라서 고려해야 할 **몇 가지 제한 사항이 있습니다.**

- Plugin은 다른 Plugin에 의존할 수 없습니다.
- Plugin은 서드파티 Swift 패키지에 의존할 수 없습니다.
- Plugin은 Plugin을 사용하는 프로젝트에 project description helpers을 사용할 수 없습니다.

더 많은 유연성이 필요하다면, 도구에 대한 기능 제안을 하거나 Tuist의 생성 프레임워크인 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)를 기반으로 자체 솔루션을 구축하는 것을 고려해 보세요.

> [!경고] Plugin 인프라는 현재 관리되지 않습니다. 우리는 이를 개선하는 데 도움을 줄 기여자를 찾고 있습니다. 관심이 있으시면 [Slack](https://slack.tuist.io/)을 통해 저희에게 연락해 주세요.

## Plugin types {#plugin-types}

### Project description helper plugin {#project-description-helper-plugin}

A project description helper plugin is represented by a directory containing a `Plugin.swift` manifest file that declares the plugin's name and a `ProjectDescriptionHelpers` directory containing the helper Swift files.

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

:::

### Resource accessor templates plugin {#resource-accessor-templates-plugin}

If you need to share <LocalizedLink href="/guides/develop/projects/synthesized-files#resource-accessors">synthesized resource accessors</LocalizedLink> you can use
this type of plugin. The plugin is represented by a directory containing a `Plugin.swift` manifest file that declares the plugin's name and a `ResourceSynthesizers` directory containing the resource accessor template files.

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

:::

The name of the template is the [camel case](https://en.wikipedia.org/wiki/Camel_case) version of the resource type:

| Resource type     | Template file name                       |
| ----------------- | ---------------------------------------- |
| Strings           | Strings.stencil          |
| Assets            | Assets.stencil           |
| Property Lists    | Plists.stencil           |
| Fonts             | Fonts.stencil            |
| Core Data         | CoreData.stencil         |
| Interface Builder | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

When defining the resource synthesizers in the project, you can specify the plugin name to use the templates from the plugin:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Task plugin <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

Tasks are `$PATH`-exposed executables that are invocable through the `tuist` command if they follow the naming convention `tuist-<task-name>`. In earlier versions, Tuist provided some weak conventions and tools under `tuist plugin` to `build`, `run`, `test` and `archive` tasks represented by executables in Swift Packages, but we have deprecated this feature since it increases the maintenance burden and complexity of the tool.

If you were using Tuist for distributing tasks, we recommend building your

- You can continue using the `ProjectAutomation.xcframework` distributed with every Tuist release to have access to the project graph from your logic with `let graph = try Tuist.graph()`. The command uses sytem process to run the `tuist` command, and return the in-memory representation of the project graph.
- To distribute tasks, we recommend including the a fat binary that supports the `arm64` and `x86_64` in GitHub releases, and using [Mise](https://mise.jdx.dev) as an installation tool. To instruct Mise on how to install your tool, you'll need a plugin repository. You can use [Tuist's](https://github.com/asdf-community/asdf-tuist) as a reference.
- If you name your tool `tuist-{xxx}` and users can install it by running `mise install`, they can run it either invoking it directly, or through `tuist xxx`.

> [!NOTE] THE FUTURE OF PROJECTAUTOMATION
> We plan to consolidate the models of `ProjectAutomation` and `XcodeGraph` into a single backward-compatible framework that exposes the entirity of the project graph to the user. Moreover, we'll extract the generation logic into a new layer, `XcodeGraph` that you can also use from your own CLI. Think of it as building your own Tuist.

## Using plugins {#using-plugins}

To use a plugin, you'll have to add it to your project's <LocalizedLink href="/references/project-description/structs/config">`Config.swift`</LocalizedLink> manifest file:

```swift
import ProjectDescription


let config = Config(
    plugins: [
        .local(path: "/Plugins/MyPlugin")
    ]
)
```

If you want to reuse a plugin across projects that live in different repositories, you can push your plugin to a Git repository and reference it in the `Config.swift` file:

```swift
import ProjectDescription


let config = Config(
    plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ]
)
```

After adding the plugins, `tuist install` will fetch the plugins in a global cache directory.

> [!NOTE] NO VERSION RESOLUTION
> As you might have noted, we don't provide version resolution for plugins. We recommend using Git tags or SHAs to ensure reproducibility.

> [!TIP] PROJECT DESCRIPTION HELPERS PLUGINS
> When using a project description helpers plugin, the name of the module that contains the helpers is the name of the plugin
>
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
