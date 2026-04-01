---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 플러그인 {#plugins}

플러그인은 여러 프로젝트에서 Tuist 아티팩트를 공유하고 재사용할 수 있는 도구입니다. 다음 아티팩트가 지원됩니다:

- <LocalizedLink href="/guides/features/projects/code-sharing">여러 프로젝트에 걸쳐 프로젝트
  설명 도우미</LocalizedLink>를 제공합니다.
- <LocalizedLink href="/guides/features/projects/templates">여러 프로젝트에 걸쳐 있는
  템플릿</LocalizedLink>.
- 여러 프로젝트에 걸친 작업.
- <LocalizedLink href="/guides/features/projects/synthesized-files">여러 프로젝트에 걸친
  리소스 액세서</LocalizedLink> 템플릿

플러그인은 Tuist의 기능을 확장하는 간단한 방법으로 설계되었습니다. 따라서 **고려해야 할 몇 가지 제한 사항이 있습니다**:

- 플러그인은 다른 플러그인에 대한 의존성을 가질 수 없습니다.
- 플러그인은 타사 Swift 패키지에 의존성을 가질 수 없습니다
- 플러그인은 해당 플러그인을 사용하는 프로젝트의 프로젝트 설명 헬퍼를 사용할 수 없습니다.

더 많은 유연성이 필요하다면, 도구에 대한 기능 제안을 고려하거나 Tuist의 생성
프레임워크([`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator))를
기반으로 직접 솔루션을 구축해 보세요.

## 플러그인 유형 {#plugin-types}

### 프로젝트 설명 도우미 플러그인 {#project-description-helper-plugin}

프로젝트 설명 헬퍼 플러그인은 플러그인 이름과 매니페스트 파일을 선언하는 ` `Plugin.swift`` 파일과 헬퍼 Swift 파일이 포함된
` `ProjectDescriptionHelpers`` 디렉터리로 구성됩니다.

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

### 리소스 액세서 템플릿 플러그인 {#resource-accessor-templates-plugin}

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">합성된
리소스 액세서</LocalizedLink>를 공유해야 하는 경우, 이 유형의 플러그인을 사용할 수 있습니다. 이 플러그인은 플러그인 이름과
매니페스트 파일을 선언하는 ` `Plugin.swift`` 파일과 리소스 액세서 템플릿 파일이 포함된 `
`ResourceSynthesizers`` 디렉터리로 구성됩니다.


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

템플릿 이름은 리소스 유형의 [카멜 케이스](https://en.wikipedia.org/wiki/Camel_case) 형식입니다:

| 리소스 유형   | 템플릿 파일 이름                |
| -------- | ------------------------ |
| 문자열      | Strings.stencil          |
| Assets   | Assets.stencil           |
| 속성 목록    | Plists.stencil           |
| 글꼴       | Fonts.stencil            |
| 핵심 데이터   | CoreData.stencil         |
| 인터페이스 빌더 | InterfaceBuilder.stencil |
| JSON     | JSON.stencil             |
| YAML     | YAML.stencil             |

프로젝트에서 리소스 합성기를 정의할 때, 플러그인 이름을 지정하여 해당 플러그인의 템플릿을 사용할 수 있습니다:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### 작업 플러그인 <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
[!WARNING] 사용 중단된 작업 플러그인은 더 이상 사용되지 않습니다. 프로젝트를 위한 자동화 솔루션을 찾고 있다면 [이 블로그
게시물](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects)을 확인하세요.
<!-- -->
:::

작업(Tasks)은 `$PATH` 에 노출된 실행 파일로, `tuist-<task-name>` 라는 명명 규칙을 따를 경우 `tuist`
명령어를 통해 호출할 수 있습니다. 이전 버전에서 Tuist는 `tuist plugin` 하에 Swift 패키지의 실행 파일로 표현되는
`build`, `run`, `test` 및 `archive` 작업을 위한 약간의 약한 규칙과 도구를 제공했으나, 이는 도구의 유지보수 부담과
복잡성을 증가시키므로 이 기능을 더 이상 권장하지 않습니다.</task-name>

Tuist를 사용하여 작업을 배정하고 있다면, 다음을 구축하는 것을 권장합니다.
- 모든 Tuist 릴리스와 함께 배포되는 `ProjectAutomation.xcframework` 를 계속 사용하여, `let graph =
  try Tuist.graph()` 와 같이 로직 내에서 프로젝트 그래프에 접근할 수 있습니다. 이 명령어는 시스템 프로세스를 사용하여
  `tuist` 명령어를 실행하고, 프로젝트 그래프의 메모리 내 표현을 반환합니다.
- 작업 분산을 위해 GitHub 릴리스에 `arm64` 및 `x86_64` 를 지원하는 fat 바이너리를 포함하고, 설치 도구로
  [Mise](https://mise.jdx.dev)를 사용하는 것을 권장합니다. Mise에 도구 설치 방법을 알려주려면 플러그인 저장소가
  필요합니다. [Tuist](https://github.com/asdf-community/asdf-tuist)를 참고할 수 있습니다.
- 도구 이름을 `tuist-{xxx}` 로 지정하고, 사용자가 `mise install` 를 실행하여 설치할 수 있다면, 사용자는 도구를 직접
  호출하거나 `tuist xxx` 를 통해 실행할 수 있습니다.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
`의 ProjectAutomation(` )과 `의 XcodeGraph(` ) 모델을 통합하여, 프로젝트 그래프 전체를 사용자에게 노출하는 단일
후방 호환 프레임워크를 제공할 계획입니다. 또한, 생성 로직을 새로운 레이어인 `의 XcodeGraph(` )로 분리할 예정이며, 이 레이어는
사용자만의 CLI에서도 사용할 수 있습니다. 이를 자신만의 Tuist를 구축하는 과정으로 생각하시면 됩니다.
<!-- -->
:::

## 플러그인 사용 {#using-plugins}

플러그인을 사용하려면 프로젝트의
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
매니페스트 파일에 다음을 추가해야 합니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

서로 다른 저장소에 있는 프로젝트 간에 플러그인을 재사용하려면, 플러그인을 Git 저장소에 푸시하고 `Tuist.swift` 파일에서 참조할 수
있습니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

플러그인을 추가한 후, ` ``를 실행하면 `tuist install` ` 명령어가 플러그인을 전역 캐시 디렉터리에 가져옵니다.

::: info NO VERSION RESOLUTION
<!-- -->
아시다시피, 저희는 플러그인에 대한 버전 해결 기능을 제공하지 않습니다. 재현성을 보장하기 위해 Git 태그나 SHA를 사용하는 것을
권장합니다.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
프로젝트 설명 헬퍼 플러그인을 사용할 때, 헬퍼가 포함된 모듈의 이름이 바로 플러그인의 이름이 됩니다
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
