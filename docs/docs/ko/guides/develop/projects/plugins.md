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

## Plugin types {#plugin-types}

### Project description helper plugin {#project-description-helper-plugin}

Project description helper plugin은 Plugin의 이름을 선언하는 `Plugin.swift` 매니페스트 파일이 포함된 디렉토리와 helper Swift files이 포함된 `ProjectDescriptionHelpers` 디렉토리로 표시됩니다.

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

<LocalizedLink href="/guides/develop/projects/synthesized-files#resource-accessors">synthesized Resource accessor</LocalizedLink>를 공유해야 하는 경우, 이 유형의 plugin을 사용할 수 있습니다. 이 plugin은 plugin의 이름을 선언하는 `Plugin.swift` 매니페스트 파일이 포함된 디렉토리와 resource accessor 템플릿 파일이 포함된 `ResourceSynthesizer` 디렉토리로 표시됩니다.

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

> [!WARNING] DEPRECATED
> Task plugins are deprecated and we are working on a more flexible and powerful solution, <LocalizedLink href="/en/guides/develop/automate/workflows">workflows</LocalizedLink>. We recommend not developing new plugins until the new solution is available.

Tasks는 `tuist--<task-name>` 명명 규칙을 따를 경우 `tuist` 명령을 통해 호출할 수 있는 `$PATH` 실행 파일입니다. 이전 버전에서 Tuist는 Swift 패키지에서 실행 파일로 구성된 `build`, `run`, `test` 및 `archive` 작업에 `tuist plugin`에 따라 몇 가지 약한 규칙과 도구를 제공했지만, 유지 관리 부담과 도구의 복잡성을 증가시키기 때문에 이 기능은 더 이상 지원되지 않습니다.

Tuist를 tasks 배포에 사용하고 있었다면, 자체 솔루션을 구축할 것을 권장합니다.

- 프로젝트 그래프에 접근하려면 매 Tuist 릴리스에 포함된 `ProjectAutomation.xcframework`를 계속 사용할 수 있으며, `let graph = try Tuist.graph()`와 같은 방식으로 로직에서 그래프에 접근할 수 있습니다. 이 명령은 시스템 프로세스를 사용하여 `tuist` 명령을 실행하고, 프로젝트 그래프의 in-memory 표현을 반환합니다.
- Tasks를 배포하려면, `arm64` and `x86_64`를 지원하는 fat binary를 GitHub 릴리스에 포함하고, 설치 도구로 [Mise](https://mise.jdx.dev) 를 사용하는 것을 권장합니다. Mise에 도구 설치 방법을 알려주려면, plugin repository가 필요합니다. [Tuist's](https://github.com/asdf-community/asdf-tuist) 를 참고할 수 있습니다.
- 도구의 이름을 `tuist-{xxx}`로 지정하면, 사용자는 `mise install`을 실행하여 설치할 수 있으며, 이를 직접 호출하거나 `tuist xxx`를 통해 실행할 수 있습니다.

> [!NOTE] 프로젝트 자동화의 미래
> 우리는 `ProjectAutomation`과 `XcodeGraph`의 모델을 하나의 하위 호환 프레임워크로 통합하여 프로젝트 그래프의 전체를 사용자에게 보여줄 계획입니다. 또한, 생성 로직을 새로운 레이어인 `XcodeGraph`로 분리하여 여러분의 CLI에서도 사용할 수 있도록 할 예정입니다. 자신만의 Tuist를 만든다고 생각하세요.

## Using plugins {#using-plugins}

plugin을 사용하려면, 프로젝트의 <LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink> manifest 파일에 추가해야 합니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

repository에 있는 프로젝트들 간에 plugin을 재사용하려면, plugin을 Git repository에 push하고 `Tuist.swift` 파일에서 참조할 수 있습니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

plugin을 추가한 후, `tuist install`을 실행하면 플러그인이 전역 캐시 디렉토리로 가져와집니다.

> [!NOTE] 버전 해결 없음
> 눈치채셨겠지만, 우리는 plugins에 대한 버전 해결을 제공하지 않습니다. 재현 가능성을 보장하기 위해 Git 태그나 SHA를 사용하는 것을 권장합니다.

> [!TIP] PROJECT DESCRIPTION HELPERS PLUGINS
> project description helpers plugin을 사용할 때, helpers를 포함하는 모듈의 이름은 plugin의 이름과 같습니다.
>
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
