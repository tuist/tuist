---
{
  "title": "플러그인",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist에서 플러그인을 생성하고 사용하여 기능을 확장하는 방법을 알아보세요."
}
---
# 플러그인 {#plugins}

플러그인은 여러 프로젝트에서 Tuist 아티팩트를 공유하고 재사용하기 위한 도구입니다. 다음 아티팩트가 지원됩니다:

- <.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>를 여러 프로젝트에서 사용
- <.localized_link href="/guides/features/projects/templates">템플릿</.localized_link>을 여러 프로젝트에서 사용
- 여러 프로젝트에서 태스크 사용
- 여러 프로젝트에서 <.localized_link href="/guides/features/projects/synthesized-files">리소스 접근자</.localized_link> 템플릿 사용

플러그인은 Tuist의 기능을 간단하게 확장할 수 있도록 설계되었습니다. 따라서 **고려해야 할 몇 가지 제한 사항**이 있습니다:

- 플러그인은 다른 플러그인에 의존할 수 없습니다.
- 플러그인은 서드파티 Swift 패키지에 의존할 수 없습니다.
- 플러그인은 해당 플러그인을 사용하는 프로젝트의 프로젝트 설명 헬퍼를 사용할 수 없습니다.

더 많은 유연성이 필요하다면, 도구에 대한 기능 제안을 고려하거나 Tuist의 생성 프레임워크인 [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)을 기반으로 자체 솔루션을 구축해 보세요.

## 플러그인 유형 {#plugin-types}

### 프로젝트 설명 헬퍼 플러그인 {#project-description-helper-plugin}

프로젝트 설명 헬퍼 플러그인은 플러그인 이름을 선언하는 `Plugin.swift` 매니페스트 파일과 헬퍼 Swift 파일을 포함하는 `ProjectDescriptionHelpers` 디렉터리로 구성된 디렉터리로 표현됩니다.

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

### 리소스 접근자 템플릿 플러그인 {#resource-accessor-templates-plugin}

<.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">생성된 리소스 접근자</.localized_link>를 공유해야 하는 경우 이 유형의 플러그인을 사용할 수 있습니다. 이 플러그인은 플러그인 이름을 선언하는 `Plugin.swift` 매니페스트 파일과 리소스 접근자 템플릿 파일을 포함하는 `ResourceSynthesizers` 디렉터리로 구성된 디렉터리로 표현됩니다.


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

템플릿 이름은 리소스 유형의 [카멜 케이스](https://en.wikipedia.org/wiki/Camel_case) 버전입니다:

| 리소스 유형 | 템플릿 파일 이름 |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

프로젝트에서 리소스 신서사이저를 정의할 때, 플러그인의 템플릿을 사용하기 위해 플러그인 이름을 지정할 수 있습니다:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 태스크 플러그인 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **사용 중단됨**
>
> 태스크 플러그인은 사용 중단되었습니다. 프로젝트의 자동화 솔루션을 찾고 있다면 [이 블로그 포스트](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)를 확인하세요.


태스크는 `tuist-<task-name>` 네이밍 규칙을 따르는 경우 `tuist` 명령어를 통해 호출할 수 있는 `$PATH`에 노출된 실행 파일입니다. 이전 버전에서 Tuist는 Swift 패키지의 실행 파일로 표현되는 `build`, `run`, `test` 및 `archive` 태스크를 위해 `tuist plugin` 아래에 일부 느슨한 규칙과 도구를 제공했지만, 이 기능은 도구의 유지 관리 부담과 복잡성을 증가시키므로 사용 중단했습니다.

Tuist를 사용하여 태스크를 배포하고 있었다면, 직접 구축하는 것을 권장합니다.
- `let graph = try Tuist.graph()`를 사용하여 로직에서 프로젝트 그래프에 접근하기 위해 모든 Tuist 릴리스와 함께 배포되는 `ProjectAutomation.xcframework`를 계속 사용할 수 있습니다. 이 명령어는 시스템 프로세스를 사용하여 `tuist` 명령어를 실행하고 프로젝트 그래프의 인메모리 표현을 반환합니다.
- 태스크를 배포하려면 GitHub 릴리스에 `arm64` 및 `x86_64`를 지원하는 유니버설 바이너리를 포함하고, 설치 도구로 [Mise](https://mise.jdx.dev)를 사용하는 것을 권장합니다. Mise에게 도구를 설치하는 방법을 지시하려면 플러그인 저장소가 필요합니다. 참고 자료로 [Tuist의](https://github.com/asdf-community/asdf-tuist) 저장소를 사용할 수 있습니다.
- 도구 이름을 `tuist-{xxx}`로 지정하고 사용자가 `mise install`를 실행하여 설치할 수 있도록 하면, 도구를 직접 호출하거나 `tuist xxx`를 통해 실행할 수 있습니다.

> [!NOTE]
> **Projectautomation의 미래**
>
> 사용자에게 프로젝트 그래프 전체를 노출하는 단일 하위 호환 프레임워크로 `ProjectAutomation` 및 `XcodeGraph` 모델을 통합할 계획입니다. 또한 생성 로직을 새로운 레이어인 `XcodeGraph`로 추출하여 자체 CLI에서도 사용할 수 있도록 할 예정입니다. 이를 자체 Tuist를 구축하는 것으로 생각하면 됩니다.


## 플러그인 사용 {#using-plugins}

플러그인을 사용하려면 프로젝트의 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) 매니페스트 파일에 추가해야 합니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

서로 다른 저장소에 있는 여러 프로젝트에서 플러그인을 재사용하려면, 플러그인을 Git 저장소에 푸시하고 `Tuist.swift` 파일에서 참조할 수 있습니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

플러그인을 추가한 후 `tuist install`가 전역 캐시 디렉터리에서 플러그인을 가져옵니다.

> [!NOTE]
> **버전 해결 없음**
>
> 알 수 있듯이, 플러그인에 대한 버전 해결 기능을 제공하지 않습니다. 재현성을 보장하기 위해 Git 태그 또는 SHA를 사용하는 것을 권장합니다.


> [!TIP]
> **프로젝트 설명 헬퍼 플러그인**
>
> 프로젝트 설명 헬퍼 플러그인을 사용할 때, 헬퍼를 포함하는 모듈의 이름은 플러그인의 이름과 같습니다.
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
