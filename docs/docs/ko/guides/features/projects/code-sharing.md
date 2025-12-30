---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 코드 공유 {#code-sharing}

큰 프로젝트에서 사용할 때 Xcode의 불편한 점 중 하나는, `.xcconfig`를 통해서 Build Setttings를 설정하는 것 대신
프로젝트의 구성 요소를 재사용 할 수 없다는 것 입니다. 프로젝트 선언을 재사용할 수 있게 되는 것이 유용한 이유는 아래와 같습니다:

- 변경 사항이 한 곳에 적용에 적용되고 모든 프로젝트가 자동으로 변경되기 때문에 **유지 보수**가 쉬워 집니다.
- 모든 프로젝트가 따르는 **규칙**을 선언할 수 있게 됩니다.
- 프로젝트가 좀 더 **일관적**이게 되므로 비일관성 때문에 빌드가 망가질 가능성이 현저히 낮아집니다.
- 프로젝트 추가가 쉬운 작업이 되므로 기존 로직을 재사용 할 수 있게 됩니다.

Tuist에서는 **project description helpers** 덕분에 Manifest들에 코드를 공유하는 것이 가능합니다.

::: tip Tuist 고유 ASSET
<!-- -->
많은 회사들은 Project Description Helpers가 플랫폼 팀들이 자신들의 규칙을 코드화하고 자신들의 언어로 프로젝트를 설명하게
해주는 플랫폼이라고 생각해서 Tuist를 좋아합니다. because they see in project description helpers a
platform for platform teams to codify their own conventions and come up with
their own language for describing their projects. 예를 들어서, YAML 기반 프로젝트 생성기는 그들만의
YAML 기반 템플릿 솔루션을 생각해야 하거나, 그들의 빌드 도구를 사용하도록 강제 합니다.
<!-- -->
:::

## 프로젝트 설명 Helper {#project-description-helpers}

Project description helpers는 Manifest 파일들이 불러올 수 있는 `ProjectDescriptionHelpers`
모듈로 컴파일 되는 Swift 파일들 입니다. 이 모듈은 `Tuist/ProjectDescriptionHelpers` 디렉토리의 모든 파일을
가져와서 컴파일 됩니다.

여러분은 파일의 맨 위에 import 구문을 추가해서 이것들을 Manifest파일로 불러올 수 있습니다:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers`는 아래 Manifest들에서 사용 가능 합니다:
- `Project.swift`
- `Package.swift` (`#TUIST` 컴파일러 Flag 뒤에만 있는)
- `Workspace.swift`

## 예제 {#example}

아래 코드 스니펫은 `Project` 모델을 확장하여 static constructor를 추가하고, 이를 `Project.swift` 파일에서
사용하는 예시입니다:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

::: tip A 규칙 체결을 위한 도구
<!-- -->
우리가 함수를 통해서 Target 이름, Bundle Identifier, 폴더 구조에 대한 규칙을 정의하고 있는 방법에 대해 알아두세요.
<!-- -->
:::
