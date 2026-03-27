---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 새로운 프로젝트 생성 {#create-a-new-project}

가장 간단하게 새 프로젝트를 시작하는 방법은 `tuist init` 명령어를 사용하는 것입니다. 이 명령어는 프로젝트 설정 과정을 안내하는
대화형 CLI를 실행합니다. 안내에 따라 진행할 때 "generated project"를 생성하는 옵션을 선택해야 합니다.

그런 다음 `tuist edit`를 수행해서
<LocalizedLink href="/guides/features/projects/editing">프로젝트를 편집할 수 있고</LocalizedLink>, 프로젝트를 수정할 수 있게 Xcode가 열립니다. 생성한 파일 중에 하나는 `Project.swift`이며,
이것은 프로젝트 정의를 포함합니다. Swift Package Manager에 익숙하다면, 이것을 `Package.swift`로 생각하면 되지만
Xcode 프로젝트의 용어로 표현된 것이라고 생각하면 됩니다.

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```
<!-- -->
:::

::: info Mise란?
<!-- -->
유지 관리 부담을 최소화하기 위해 사용 가능한 템플릿 목록을 짧게 유지하고 있습니다. 애플리케이션이 아닌 프레임워크와 같은 프로젝트를
생성하려면, `tuist init`을 시작점으로 사용한 다음에 생성한 프로젝트를 필요에 맞게 수정할 수 있습니다.
<!-- -->
:::

## 수동으로 프로젝트 생성 {#manually-creating-a-project}

또한 수동으로 프로젝트를 생성할 수 있습니다. 하지만 Tuist와 그 개념에 익숙할 때에만 이 방법을 사용하길 권장합니다. 먼저 프로젝트 구조를
위한 추가 디렉토리를 생성해야 합니다:

```bash
mkdir MyFramework
cd MyFramework
```

그런 다음에 Tuist를 설정하고 프로젝트의 루트 디렉토리를 식별하는데 사용하는 `Tuist.swift` 파일을 생성하고 프로젝트를 선언하는
`Project.swift` 파일도 생성합니다:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

::: warning
<!-- -->
Tuist는 `Tuist/` 디렉토리를 사용하여 프로젝트의 루트를 식별하고 그 위치를 기준으로 다른 매니페스트 파일을 탐색합니다. 이러한 파일
생성은 선호하는 편집기를 사용하는 것을 권장하며, 이후에는 `tuist edit` 명령어를 사용해 Xcode에서 프로젝트를 수정할 수 있습니다.
<!-- -->
:::
