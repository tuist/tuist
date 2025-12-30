---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifests {#manifests}

Tuist는 프로젝트와 워크스페이스를 선언하고 생성 프로세스를 환경 설정하는 주요 방법으로써 Swift 파일들을 기본으로 합니다. 이 파일들은
These 문서를 통해 **manifest 파일** 로 참조 됩니다.

Swift를 사용하는 것에 대한 결정은 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/)가 패키지를 정의하기 위해
Swift 파일들을 사용하는 것에서 영감을 받았습니다고맙게도 Swift를 사용해서 우리는 컴파일러를 실행할 수 있었는데 여러 다른
Manifest 파일들에 전체적으로 내용의 정확성과 코드 재사용을, 문법 강조, 자동완성, 유효성 검증 등 최고의 편집 경험을 제공하기 위해
Xcode를 문법을 강조하고 사용할 수 있게 되었습니다.

::: info 캐싱
<!-- -->
Manifest 파일들이 컴파일이 되어야 하는 Swift 파일들이기 때문에, Tuist는 파싱 속도를 높이기 위해 컴파일 결과를 캐시 합니다.
그러므로, 여러분은 Tuist를 처음 실행하면 프로젝트를 다시 만들지 않고 다음에는 더 빨라 진다는 것을 알 겁니다.
<!-- -->
:::

## Project.swift {#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
Manifest는 Xcode 프로젝트를 선언 합니다. 프로젝트는 Manifest 파일이 있는 같은 폴더에 `name` 속성으로 명시된 이름으로
생성 됩니다.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning 최상위 변수
<!-- -->
최상위 Manifest에 만 존재해야 하는 변수는 `let project = Project(...)` 입니다. 코드를 Manifest의 여러
부분에서 재사용 해야 한다면, Swift 함수를 사용할 수 있습니다.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

기본적으로, Tuist는 생성된 프로젝트와 그것을 참조하는 프로젝트들 포함해서 [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)를
생성 합니다. 만약 워크스페이스에 추가적인 프로젝트나 파일, 그룹을 추가하고 싶으면,
<LocalizedLink href="/references/project-description/structs/workspace">Workspace.swift</LocalizedLink>
Manifest도 사용할 수 있습니다.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

::: info Mise란?
<!-- -->
Tuist는 의존성 그래프를 찾아서 의존하는 프로젝트들을 워크스페이스에 포함시킬 것 입니다. 여러분이 수동으로 포함 시킬 필요가 없습니다. 이
작업은 의존성을 정확하게 찾기 위해 빌드 시스템에 필요 합니다.
<!-- -->
:::

### 여러 또는 단일 프로젝트 {#multi-or-monoproject}

자주 하는 질문은 워크스페이스에서 단일 또는 여러 프로젝트를 사용해야 할 지 입니다. Tuist가 없는 세계에서는 단일 프로젝트가
워크스페이스에서 잦은 Git 충돌을 유발할 것 입니다. 하지만 우리가 Tuist로 생성된 프로젝트를 Git에 포함하는 것을 권장하지 않기
때문에, Git 충돌은 더 이상 이슈가 아닙니다. 그러므로 단일 또는 다중 프로젝트를 사용할 지는 여러분의 결정에 달렸습니다.

Tuist 프로젝트에서 우리는 단일 프로젝트에 기댑니다, 짧은 생성 시간(적은 Manifest를 컴파일해서)이 더 빠르고 우리는
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>를 캡슐화 단위로 사용하기 때문 입니다. 하지만 여러분은 아마 Xcode의 권장 프로젝트 구조에 가깝게
앱의 여러 다른 도메인을 나타내기 위해 Xcode 프로젝트를 캡슐화 단위로 사용하길 원할지도 모릅니다.

## Tuist.swift {#tuistswift}

Tuist는 프로젝트 환경 설정을 단순화 하기 위해
<LocalizedLink href="/contributors/principles.html#default-to-conventions">적절한 기본 값</LocalizedLink>를 제공합니다. 하지만
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>를
최상위에 정의해서 프로젝트가 최상위 프로젝트를 결정하는데 사용하도록 설정하실 수도 있습니다.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
