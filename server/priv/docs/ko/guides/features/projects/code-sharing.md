---
{
  "title": "코드 공유",
  "titleTemplate": ":title · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "매니페스트 파일 간에 코드를 공유하여 중복을 줄이고 일관성을 유지하는 방법을 알아보세요"
}
---
# 코드 공유 {#code-sharing}

대규모 프로젝트에서 Xcode를 사용할 때의 불편함 중 하나는 빌드 설정 외에 프로젝트 요소를 `.xcconfig` 파일을 통해 재사용할 수 없다는 점입니다. 프로젝트 정의를 재사용할 수 있는 것은 다음과 같은 이유로 유용합니다:

- 변경을 한 곳에서 적용하면 모든 프로젝트에 자동으로 반영되므로 **유지보수**가 쉬워집니다.
- 새 프로젝트가 준수할 수 있는 **규칙**을 정의할 수 있습니다.
- 프로젝트가 더 **일관성 있게** 구성되므로, 불일치로 인한 빌드 실패 가능성이 크게 줄어듭니다.
- 기존 로직을 재사용할 수 있어 새 프로젝트를 추가하는 작업이 쉬워집니다.

Tuist에서는 **프로젝트 설명 헬퍼** 개념 덕분에 매니페스트 파일 간에 코드를 재사용할 수 있습니다.

> [!TIP]
> **Tuist만의 고유한 강점**
>
> 많은 조직이 Tuist를 선호하는 이유는 프로젝트 설명 헬퍼를 통해 플랫폼 팀이 자체 규칙을 코드화하고 프로젝트를 설명하는 자체 언어를 만들 수 있는 플랫폼으로 보기 때문입니다. 예를 들어 YAML 기반 프로젝트 생성기는 자체 YAML 기반 독점 템플릿 솔루션을 개발하거나, 조직이 해당 도구를 기반으로 구축하도록 강제해야 합니다.


## 프로젝트 설명 헬퍼 {#project-description-helpers}

프로젝트 설명 헬퍼는 매니페스트 파일에서 가져올 수 있는 모듈인 `ProjectDescriptionHelpers`로 컴파일되는 Swift 파일입니다. 이 모듈은 `Tuist/ProjectDescriptionHelpers` 디렉터리의 모든 파일을 모아 컴파일됩니다.

파일 상단에 import 문을 추가하여 매니페스트 파일로 가져올 수 있습니다:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers`는 다음 매니페스트에서 사용할 수 있습니다:
- `Project.swift`
- `Package.swift` (`#TUIST` 컴파일러 플래그 사용 시에만)
- `Workspace.swift`

## 예제 {#example}

아래 스니펫은 `Project` 모델을 확장하여 정적 생성자를 추가하고, 이를 `Project.swift` 파일에서 사용하는 방법을 보여줍니다:

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

> [!TIP]
> **규칙을 정립하는 도구**
>
> 함수를 통해 타겟 이름, 번들 식별자, 폴더 구조에 대한 규칙을 정의하는 방식을 확인하세요.
