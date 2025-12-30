---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# 플러그인 {#plugins}

플러그인은 여러 프로젝트에서 Tuist 아티팩트를 공유하고 재사용할 수 있는 도구입니다. 지원되는 아티팩트는 다음과 같습니다:

- <LocalizedLink href="/guides/features/projects/code-sharing">여러 프로젝트에 걸친 프로젝트 설명 도우미</LocalizedLink>.
- <LocalizedLink href="/guides/features/projects/templates">템플릿</LocalizedLink>을
  여러 프로젝트에 걸쳐 사용합니다.
- 여러 프로젝트에 걸친 작업.
- <LocalizedLink href="/guides/features/projects/synthesized-files">여러 프로젝트에 걸친 리소스 접근자</LocalizedLink> 템플릿

플러그인은 Tuist의 기능을 간단하게 확장할 수 있도록 설계되었습니다. 따라서 고려해야 할 **몇 가지 제한 사항이 있습니다(**):

- 플러그인은 다른 플러그인에 의존할 수 없습니다.
- 플러그인은 타사 Swift 패키지에 의존할 수 없습니다.
- 플러그인은 플러그인을 사용하는 프로젝트의 프로젝트 설명 도우미를 사용할 수 없습니다.

더 많은 유연성이 필요한 경우, 도구의 기능을 제안하거나 Tuist의 생성 프레임워크인
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator)을
기반으로 자체 솔루션을 구축하는 것을 고려하세요.

## 플러그인 유형 {#plugin-types}

### 프로젝트 설명 도우미 플러그인 {#project-description-helper-plugin}

프로젝트 설명 도우미 플러그인은 플러그인 이름을 선언하는 `Plugin.swift` 매니페스트 파일과 도우미 Swift 파일을 포함하는
`ProjectDescriptionHelpers` 디렉터리가 포함된 디렉토리로 표시됩니다.

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

<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">합성된 리소스 접근자</LocalizedLink>를 공유해야 하는 경우 이 유형의 플러그인을 사용할 수 있습니다. 플러그인은 플러그인 이름을
선언하는 `Plugin.swift` 매니페스트 파일과 리소스 접근자 템플릿 파일이 포함된 `ResourceSynthesizers` 디렉터리가
포함된 디렉터리로 표현됩니다.


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

템플릿의 이름은 리소스 유형의 [낙타 케이스](https://en.wikipedia.org/wiki/Camel_case) 버전입니다:

| 리소스 유형   | 템플릿 파일 이름        |
| -------- | ---------------- |
| 문자열      | 문자열.스텐실          |
| 자산       | Assets.stencil   |
| 속성 목록    | Plists.stencil   |
| 글꼴       | Fonts.stencil    |
| 핵심 데이터   | CoreData.stencil |
| 인터페이스 빌더 | 인터페이스 빌더 스텐실     |
| JSON     | JSON.stencil     |
| YAML     | YAML.stencil     |

프로젝트에서 리소스 신디사이저를 정의할 때 플러그인의 템플릿을 사용하도록 플러그인 이름을 지정할 수 있습니다:

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

작업은 `$PATH`- 노출된 실행 파일로, 명명 규칙 `tuist-&lt;작업 이름&gt;` 을 따르는 경우 `tuist` 명령을 통해 호출할
수 있습니다. 이전 버전에서는 튜이스트가 `tuist 플러그인` 에서 `빌드`, `실행`, `테스트` 및 `아카이브` 실행 파일로 표현되는 몇
가지 약한 규칙과 도구를 제공했지만, 이 기능은 유지 관리 부담과 도구의 복잡성을 증가시키기 때문에 더 이상 사용되지 않습니다.

작업을 배포하는 데 Tuist를 사용 중이라면
- 모든 튜이스트 릴리스와 함께 배포되는 `ProjectAutomation.xcframework` 를 계속 사용하여 `let graph =
  try Tuist.graph()` 로 로직에서 프로젝트 그래프에 액세스할 수 있습니다. 이 명령은 시스템 프로세스를 사용하여 `tuist`
  명령을 실행하고 프로젝트 그래프의 인메모리 표현을 반환합니다.
- 작업을 배포하려면 `arm64` 및 `x86_64` 를 지원하는 팻 바이너리를 GitHub 릴리스에 포함시키고
  [Mise](https://mise.jdx.dev)를 설치 도구로 사용하는 것이 좋습니다. Mise에 도구 설치 방법을 지시하려면 플러그인
  리포지토리가 필요합니다. Tuist's](https://github.com/asdf-community/asdf-tuist)를 참조로 사용할
  수 있습니다.
- 도구의 이름을 `tuist-{xxx}` 로 지정하고 사용자가 `mise install` 을 실행하여 설치하면 직접 실행하거나 `tuist
  xxx` 을 통해 실행할 수 있습니다.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
저희는 프로젝트 그래프의 실체를 사용자에게 노출하는 단일 하위 호환 프레임워크에 `ProjectAutomation` 및 `XcodeGraph`
모델을 통합할 계획입니다. 또한 생성 로직을 새로운 레이어인 `XcodeGraph` 로 추출하여 자체 CLI에서도 사용할 수 있습니다. 나만의
튜이스트를 구축한다고 생각하면 됩니다.
<!-- -->
:::

## 플러그인 사용 {#using-plugins}

플러그인을 사용하려면 프로젝트의
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
매니페스트 파일에 플러그인을 추가해야 합니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

다른 저장소에 있는 프로젝트에서 플러그인을 재사용하려면 플러그인을 Git 저장소로 푸시하고 `Tuist.swift` 파일에서 참조하면 됩니다:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

플러그인을 추가한 후 `tuist install` 을 입력하면 글로벌 캐시 디렉터리에서 플러그인을 가져옵니다.

::: info NO VERSION RESOLUTION
<!-- -->
아시다시피 워드프레스닷컴은 플러그인에 대한 버전 확인 기능을 제공하지 않습니다. 재현성을 보장하기 위해 Git 태그 또는 SHA를 사용하는 것이
좋습니다.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
프로젝트 설명 헬퍼 플러그인을 사용하는 경우 헬퍼가 포함된 모듈의 이름은 플러그인의 이름입니다.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
