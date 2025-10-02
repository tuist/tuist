---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# 새 프로젝트 만들기 {#create-a-new-project}

튜이스트에서 새 프로젝트를 시작하는 가장 간단한 방법은 `tuist init` 명령을 사용하는 것입니다. 이 명령은 프로젝트 설정 과정을
안내하는 대화형 CLI를 시작합니다. 메시지가 표시되면 "생성된 프로젝트" 생성 옵션을 선택해야 합니다.

그런 다음
<LocalizedLink href="/guides/features/projects/editing">프로젝트</LocalizedLink>를
실행하여 `tuist edit` 을 실행하면 Xcode에서 프로젝트를 편집할 수 있는 프로젝트가 열립니다. 생성되는 파일 중 하나는 프로젝트의
정의가 포함된 `Project.swift` 파일입니다. Swift 패키지 관리자에 익숙한 경우 `Package.swift` 에 Xcode
프로젝트 용어를 추가한 것으로 생각하면 됩니다.

::: 코드 그룹
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
:::

> [참고] 유지 관리 오버헤드를 최소화하기 위해 사용 가능한 템플릿 목록을 의도적으로 짧게 유지합니다. 애플리케이션이 아닌 프로젝트(예:
> 프레임워크)를 만들려면 `tuist init` 을 시작점으로 사용한 다음 필요에 맞게 생성된 프로젝트를 수정할 수 있습니다.

## 수동으로 프로젝트 만들기 {#manually-creating-a-project}

또는 프로젝트를 수동으로 생성할 수도 있습니다. 이 방법은 이미 Tuist와 그 개념에 익숙한 경우에만 사용하는 것이 좋습니다. 가장 먼저 해야
할 일은 프로젝트 구조를 위한 추가 디렉터리를 만드는 것입니다:

```bash
mkdir MyFramework
cd MyFramework
```

그런 다음 Tuist를 구성하고 프로젝트의 루트 디렉터리를 결정하는 데 사용되는 `Tuist.swift` 파일과 프로젝트가 선언될
`Project.swift` 파일을 만듭니다:

::: 코드 그룹
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
:::

> [중요] 튜이스트는 `튜이스트/` 디렉터리를 사용하여 프로젝트의 루트를 확인하고, 거기에서 디렉터리를 글로브하는 다른 매니페스트 파일을
> 찾습니다. 선택한 편집기로 해당 파일을 생성하는 것이 좋으며, 그 시점부터 `tuist edit` 을 사용하여 Xcode로 프로젝트를 편집할
> 수 있습니다.
