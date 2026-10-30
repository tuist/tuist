---
{
  "title": "새 프로젝트 생성",
  "titleTemplate": ":title · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "Tuist로 새 프로젝트를 생성하는 방법을 알아보세요."
}
---
# 새 프로젝트 생성 {#create-a-new-project}

Tuist로 새 프로젝트를 시작하는 가장 간단한 방법은 `tuist init` 명령어를 사용하는 것입니다. 이 명령어는 프로젝트를 설정하는 과정을 안내하는 상호작용형 CLI를 실행합니다. 프롬프트가 표시되면 "generated project" 생성 옵션을 선택하세요.

이후 `tuist edit`을 실행하여 <.localized_link href="/guides/features/projects/editing">프로젝트를 편집</.localized_link>할 수 있으며, Xcode에서 프로젝트를 열어 편집할 수 있습니다. 생성되는 파일 중 하나인 `Project.swift`에는 프로젝트 정의가 포함됩니다. Swift Package Manager에 익숙하다면, 이를 Xcode 프로젝트 용어를 사용한 `Package.swift`라고 생각하면 됩니다.

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

> [!NOTE]
> 유지보수 오버헤드를 최소화하기 위해 사용 가능한 템플릿 목록을 의도적으로 짧게 유지합니다. 애플리케이션이 아닌 프로젝트(예: 프레임워크)를 생성하려면 `tuist init`을 시작점으로 사용한 후, 필요에 맞게 생성된 프로젝트를 수정하면 됩니다.


## 프로젝트 수동 생성 {#manually-creating-a-project}

또는 프로젝트를 수동으로 생성할 수도 있습니다. Tuist와 그 개념에 이미 익숙한 경우에만 이 방법을 권장합니다. 먼저 프로젝트 구조를 위한 추가 디렉터리를 생성해야 합니다.

```bash
mkdir MyFramework
cd MyFramework
```

그런 다음 Tuist를 구성하고 프로젝트의 루트 디렉터리를 결정하는 데 사용되는 `Tuist.swift` 파일과 프로젝트가 선언되는 `Project.swift` 파일을 생성하세요.

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

> [!WARNING]
> Tuist는 `Tuist/` 디렉터리를 사용하여 프로젝트의 루트를 결정하며, 해당 위치에서 디렉터리를 검색하여 다른 매니페스트 파일을 찾습니다. 선호하는 편집기로 이러한 파일을 생성한 후, `tuist edit`을 사용하여 Xcode에서 프로젝트를 편집할 수 있습니다.
