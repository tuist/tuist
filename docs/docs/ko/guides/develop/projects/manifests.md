---
title: Manifests
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Tuist가 프로젝트와 워크스페이스를 정의하고 생성 프로세스를 구성하는데 사용하는 매니페스트 파일에 대해 알아봅니다.
---

# Manifests {#manifests}

Tuist는 프로젝트와 워크스페이스를 정의하고 생성 프로세스를 구성하는데 기본적으로 Swift 파일을 사용합니다. 이러한 파일은 이 문서에서 **매니페스트 파일**이라고 합니다.

Swift를 사용하기로 결정한 것은 패키지를 정의하기 위해 Swift 파일을 사용하는 [Swift Package Manager](https://www.swift.org/documentation/package-manager/)에서 영감을 받았습니다. Swift를 사용하면, 컴파일러를 활용해 컨텐츠의 정확성을 검증하고 다른 매니페스트 파일에서 코드를 재사용할 수 있고 Xcode를 활용하여 구문 강조, 자동 완성, 그리고 검증으로 좋은 편집 환경을 제공합니다.

> [!NOTE] 캐싱
> 매니페스트 파일은 컴파일 되어야 할 Swift 파일이므로, Tuist는 파싱 과정의 속도를 올리기 위해 결과를 캐시합니다. 그래서 Tuist를 처음 실행해 프로젝트를 생성할 때 조금 더 시간이 걸릴 수 있습니다. 이후 실행은 더 빨라 집니다.

## Project.swift {#projectswift}

<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink> 매니페스트는 Xcode 프로젝트를 선언합니다. 프로젝트는 `name` 프로퍼티에 지정된 이름으로 매니페스트 파일이 위치한 디렉토리에 생성됩니다.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```

> [!WARNING] 루트 변수
> 매니페스트의 루트에 있어야 하는 변수는 `let project = Project(...)` 입니다. 매니페스트의 일부분을 코드에서 재사용 해야 된다면 Swift 함수를 사용할 수 있습니다.

## Workspace.swift {#workspaceswift}

기본적으로 Tuist는 생성된 프로젝트와 해당 프로젝트가 의존하고 있는 프로젝트를 포함하는 [Xcode Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)를 생성합니다. 워크스페이스에 프로젝트를 추가하거나 파일과 그룹을 포함하려면 <LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink> 매니페스트를 정의해서 사용할 수 있습니다.

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

> [!NOTE]\
> Tuist는 의존성 그래프를 해결하고 의존성의 프로젝트를 워크스페이스에 포함 시킵니다. 수동으로 포함 시킬 필요가 없습니다. 이는 의존성을 올바르게 해결하기 위해 빌드 시스템에 필요합니다.

### 다중 또는 단일 프로젝트 {#multi-or-monoproject}

자주 질문하는 내용 중에 하나는 워크스페이스에 단일 프로젝트를 사용할지 아니면 여러 프로젝트를 사용할지에 대한 것입니다. Tuist가 없다면 단일 프로젝트 설정으로 인해 Git 충돌이 자주 발생하므로 워크스페이스 사용을 권장합니다. 그러나 Tuist로 생성한 Xcode 프로젝트는 Git 리포지토리에 포함하는 것을 권장하지 않으므로 Git 충돌은 문제가 되지 않습니다. 따라서 워크스페이스에서 단일 프로젝트를 사용할지 여러 프로젝트를 사용할지는 여러분 결정에 달렸습니다.

Tuist 프로젝트에서는 첫 생성 시간 (Cold generation time) 이 더 빠르고 (더 적은 매니페스트 파일을 컴파일 하기 때문) <LocalizedLink href="/guides/develop/projects/code-sharing">프로젝트 설명 도우미</LocalizedLink>를 캡슐화 단위로 사용하기 때문에 단일 프로젝트를 사용합니다. 그러나 애플리케이션에 다른 도메인을 나타내기 위해 캡슐화의 단위로 Xcode 프로젝트를 사용하면 Xcode에서 권장하는 프로젝트 구조와 더 일치합니다.

## Tuist.swift {#tuistswift}

Tuist는 프로젝트 구성을 단순화 하기 위해 <LocalizedLink href="/contributors/principles.html#default-to-conventions">기본값 (Sensible defaults)</LocalizedLink>을 제공합니다. 하지만 Tuist가 프로젝트의 루트를 결정하는데 사용되는 <LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>를 정의하여 구성을 사용자화 할 수 있습니다.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
