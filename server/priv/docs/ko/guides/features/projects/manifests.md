---
{
  "title": "매니페스트",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist 프로젝트, 워크스페이스 및 생성 구성을 정의하는 매니페스트 파일입니다."
}
---
# 매니페스트 {#manifests}

Tuist는 프로젝트와 워크스페이스를 정의하고 생성 프로세스를 구성하는 기본 방식으로 Swift 파일을 사용합니다. 이러한 파일은 문서 전체에서 **매니페스트 파일**이라고 부릅니다.

Swift 사용 결정은 패키지를 정의하기 위해 Swift 파일을 사용하는 [Swift Package Manager](https://www.swift.org/documentation/package-manager/)에서 영감을 받았습니다. Swift를 사용하면 컴파일러를 활용해 콘텐츠의 정확성을 검증하고 다양한 매니페스트 파일 간에 코드를 재사용할 수 있으며, 구문 강조 표시, 자동 완성 및 검증을 통해 Xcode가 일류 편집 경험을 제공할 수 있습니다.

> [!NOTE]
> **캐싱**
>
> 매니페스트 파일은 컴파일해야 하는 Swift 파일이므로, Tuist는 파싱 속도를 높이기 위해 컴파일 결과를 캐시합니다. 따라서 Tuist를 처음 실행할 때는 프로젝트 생성에 조금 더 시간이 걸릴 수 있습니다. 이후 실행부터는 더 빠르게 진행됩니다.


## Project.swift {#projectswift}

[`Project.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/project) 매니페스트는 Xcode 프로젝트를 선언합니다. 프로젝트는 매니페스트 파일이 위치한 디렉토리에 `name` 속성에 지정된 이름으로 생성됩니다.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING]
> **루트 변수**
>
> 매니페스트 루트에 있어야 하는 유일한 변수는 `let project = Project(...)`입니다. 매니페스트의 여러 부분에서 코드를 재사용해야 한다면 Swift 함수를 사용할 수 있습니다.


## Workspace.swift {#workspaceswift}

기본적으로 Tuist는 생성 중인 프로젝트와 해당 의존성의 프로젝트를 포함하는 [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)를 생성합니다. 추가 프로젝트를 추가하거나 파일과 그룹을 포함하도록 워크스페이스를カスタ마이즈하려면 [`Workspace.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/workspace) 매니페스트를 정의하면 됩니다.

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

> [!NOTE]
> Tuist는 의존성 그래프를 해결하고 의존성의 프로젝트를 워크스페이스에 포함합니다. 수동으로 포함할 필요는 없습니다. 이는 빌드 시스템이 의존성을 올바르게 해결하는 데 필요합니다.


### 멀티 또는 모노 프로젝트 {#multi-or-monoproject}

워크스페이스에서 단일 프로젝트를 사용할지 여러 프로젝트를 사용할지에 대한 질문이 자주 제기됩니다. Tuist가 없는 세계에서는 모노 프로젝트 설정이 빈번한 Git 충돌로 이어지기 때문에 워크스페이스 사용이 권장됩니다. 그러나 Tuist가 생성한 Xcode 프로젝트를 Git 리포지토리에 포함하지 않는 것을 권장하므로 Git 충돌은 문제가 되지 않습니다. 따라서 워크스페이스에서 단일 프로젝트 또는 여러 프로젝트를 사용할지는 여러분의 선택입니다.

Tuist 프로젝트에서는 콜드 생성 시간이 더 빠르고(컴파일해야 할 매니페스트 파일이 적음) <.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>를 캡슐화 단위로 활용하기 때문에 모노 프로젝트를 선호합니다. 그러나 애플리케이션의 서로 다른 도메인을 나타내기 위해 Xcode 프로젝트를 캡슐화 단위로 사용하고 싶을 수 있으며, 이는 Xcode에서 권장하는 프로젝트 구조와 더 잘 일치합니다.

## Tuist.swift {#tuistswift}

Tuist는 프로젝트 구성을 단순화하기 위해 <.localized_link href="/contributors/principles#default-to-conventions">합리적인 기본값</.localized_link>을 제공합니다. 그러나 프로젝트 루트에 [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist)를 정의하여 구성을 커스터마이즈할 수 있으며, Tuist는 이를 사용하여 프로젝트 루트를 결정합니다.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
