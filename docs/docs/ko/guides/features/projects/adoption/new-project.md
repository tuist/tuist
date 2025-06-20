---
title: Create a new project
titleTemplate: :title · Adoption · Projects · Develop · Guides · Tuist
description: Tuist로 새로운 프로젝트를 어떻게 생성하는지 배웁니다.
---

# Create a new project {#create-a-new-project}

Tuist로 새로운 프로젝트를 시작하는 가장 간단한 방법은 `tuist init` 명령어를 사용하는 것입니다. 이 명령어는 프로젝트 설정을 도와주는 CLI를 실행합니다. 안내에 따라 진행할 때, 반드시 "generated project"를 생성하는 옵션을 선택해야 합니다.

생성된 파일 중 하나 인 `Project.swift` 는 프로젝트의 정의를 포함하고 있습니다. Swift Package Manager에 익숙하다면 Xcode 프로젝트에서 사용하는 `Package.swift`라고 생각하면 됩니다. `tuist edit`을 수행하여 <LocalizedLink href="/guides/develop/projects/editing">프로젝트를 수정</LocalizedLink>할 수 있으며, 해당 프로젝트를 수정할 수 있게 Xcode가 열립니다.

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
            bundleId: "io.tuist.MyApp",
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
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

:::

> [!NOTE]\
> 유지 보수를 최소화 하기 위해 템플릿은 가능한 짧게 유지합니다. 프레임워크와 같이 애플리케이션이 아닌 프로젝트를 생성하고 싶으면, `tuist init`을 사용하여 생성된 프로젝트를 필요에 따라 수정할 수 있습니다.

## 수동으로 프로젝트 생성 {#manually-creating-a-project}

수동으로도 프로젝트를 생성할 수 있습니다. Tuist와 그 개념에 익숙한 경우에만 해당 내용을 수행하도록 추천합니다. 먼저, 프로젝트 구조에 대한 디렉토리를 생성해야 합니다:

```bash
mkdir MyFramework
cd MyFramework
```

그런 다음에 Tuist 구성과 프로젝트의 루트 디렉토리를 결정하는 `Tuist.swift` 파일과 프로젝트를 선언하는 `Project.swift` 파일을 생성합니다:

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
            bundleId: "io.tuist.MyFramework",
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

:::

> [!IMPORTANT]\
> Tuist는 `Tuist/` 디렉토리를 사용하여 프로젝트의 루트를 결정하고, 그 디렉토리에서 다른 매니페스트 파일을 찾습니다. 원하는 편집기로 해당 파일을 생성하고, `tuist edit`를 사용하여 Xcode로 프로젝트를 수정할 수 있습니다.
