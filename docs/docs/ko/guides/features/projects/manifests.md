---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# 매니페스트 {#매니페스트}

Tuist는 프로젝트와 작업 공간을 정의하고 생성 프로세스를 구성하는 기본 방법으로 Swift 파일을 기본으로 사용합니다. 이러한 파일은 문서
전체에서 **매니페스트 파일** 이라고 합니다.

Swift를 사용하기로 결정한 것은 Swift 파일을 사용하여 패키지를 정의하는 [Swift 패키지
관리자](https://www.swift.org/documentation/package-manager/)에서 영감을 얻었습니다. Swift를
사용하면 컴파일러를 활용하여 콘텐츠의 정확성을 검증하고 여러 매니페스트 파일에서 코드를 재사용할 수 있으며, Xcode는 구문 강조 표시, 자동
완성 및 유효성 검사 덕분에 최고 수준의 편집 환경을 제공할 수 있습니다.

> [참고] 캐싱 매니페스트 파일은 컴파일해야 하는 Swift 파일이므로, Tuist는 컴파일 결과를 캐싱하여 구문 분석 프로세스의 속도를
> 높입니다. 따라서 처음 Tuist를 실행하면 프로젝트를 생성하는 데 시간이 조금 더 걸릴 수 있습니다. 이후 실행은 더 빨라질 것입니다.

## Project.swift {#projectswift}

1}`Project.swift`</LocalizedLink> 매니페스트는 Xcode 프로젝트를 선언합니다. 프로젝트는 매니페스트 파일이 있는
디렉토리와 동일한 디렉터리에 `이름` 속성에 표시된 이름으로 생성됩니다.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!경고] 루트 변수 매니페스트의 루트에 있어야 하는 유일한 변수는 `let project = Project(...)` 입니다. 매니페스트의
> 여러 부분에서 코드를 재사용해야 하는 경우 Swift 함수를 사용할 수 있습니다.

## Workspace.swift {#workspaceswift}

기본적으로 Tuist는 생성 중인 프로젝트와 그 종속 프로젝트가 포함된 [Xcode 작업
공간](https://developer.apple.com/documentation/xcode/projects-and-workspaces)을
생성합니다. 어떤 이유로든 프로젝트를 추가하거나 파일 및 그룹을 포함하도록 작업 공간을 사용자 지정하려는 경우
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
매니페스트를 정의하여 이를 수행할 수 있습니다.

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

> [참고] Tuist는 종속성 그래프를 해결하고 종속성의 프로젝트를 작업 영역에 포함합니다. 수동으로 포함할 필요는 없습니다. 이는 빌드
> 시스템이 종속성을 올바르게 해결하는 데 필요합니다.

### 멀티 또는 모노 프로젝트 {#멀티 또는 모노 프로젝트}

작업 공간에서 단일 프로젝트를 사용할지, 아니면 여러 프로젝트를 사용할지 자주 묻는 질문이 있습니다. 단일 프로젝트 설정으로 인해 잦은 Git
충돌이 발생하는 Tuist가 없는 환경에서는 워크스페이스 사용을 권장합니다. 그러나 Git 리포지토리에 Tuist에서 생성한 Xcode
프로젝트를 포함하지 않는 것이 좋으므로 Git 충돌은 문제가 되지 않습니다. 따라서 하나의 프로젝트 또는 여러 프로젝트를 하나의 워크스페이스에
사용할지 여부는 사용자가 결정할 수 있습니다.

Tuist 프로젝트에서는 콜드 생성 시간이 더 빠르고(컴파일할 매니페스트 파일 수가 적음)
<LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명
헬퍼</LocalizedLink>를 캡슐화 단위로 활용하기 때문에 모노 프로젝트를 사용합니다. 그러나 Xcode 프로젝트를 캡슐화 단위로
사용하여 애플리케이션의 다양한 도메인을 표현하는 것이 Xcode의 권장 프로젝트 구조에 더 가깝게 부합할 수 있습니다.

## Tuist.swift {#tuistswift}

Tuist는 프로젝트 구성을 간소화하기 위해
<LocalizedLink href="/contributors/principles.html#default-to-conventions">감각적인
기본값</LocalizedLink>을 제공합니다. 그러나 프로젝트의 루트에
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>를
정의하여 구성을 사용자 지정할 수 있으며, 이는 Tuist에서 프로젝트의 루트를 결정하는 데 사용됩니다.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
