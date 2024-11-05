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

> [!WARNING] Plugin 인프라는 현재 관리되지 않습니다. 우리는 이를 개선하는 데 도움을 줄 기여자를 찾고 있습니다. 관심이 있으시면 [Slack](https://slack.tuist.io/)을 통해 저희에게 연락해 주세요.

## Plugin types {#plugin-types}

### Project description helper plugin {#project-description-helper-plugin}

Project description helper plugin은 Plugin의 이름을 선언하는 'Plugin.swift' 매니페스트 파일이 포함된 디렉토리와 helper Swift files이 포함된 'ProjectDescriptionHelpers' 디렉토리로 표시됩니다.

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

<LocalizedLink href="/guides/develop/projects/synthesized-files#resource-accessors">synthesized Resource accessor</LocalizedLink>를 공유해야 하는 경우, 이 유형의 plugin을 사용할 수 있습니다. 이 plugin은 plugin의 이름을 선언하는 'Plugin.swift' 매니페스트 파일이 포함된 디렉토리와 resource accessor 템플릿 파일이 포함된 'ResourceSynthesizer' 디렉토리로 표시됩니다.

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

템플릿의 이름은 resource type의 [camel case](https://en.wikipedia.org/wiki/Camel_case) 버전입니다.

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

프로젝트에서 resource synthesizers를 정의할 때, plugin의 템플릿을 사용하도록 plugin 이름을 지정할 수 있습니다.

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Task plugin <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

Tasks는 'tuist-<task-name>' 명명 규칙을 따를 경우 'tuist' 명령을 통해 호출할 수 있는 '$PATH' 실행 파일입니다. 이전 버전에서 Tuist는 Swift 패키지에서 실행 파일로 구성된 'build', 'run', 'test' 및 'archive' 작업에 'tuist plugin'에 따라 몇 가지 약한 규칙과 도구를 제공했지만, 유지 관리 부담과 도구의 복잡성을 증가시키기 때문에 이 기능은 더 이상 지원되지 않습니다.

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
