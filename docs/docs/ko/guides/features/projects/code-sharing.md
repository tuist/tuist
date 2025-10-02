---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# 코드 공유 {#코드 공유}

대규모 프로젝트에서 Xcode를 사용할 때 불편한 점 중 하나는 `.xcconfig` 파일을 통해 빌드 설정 이외의 프로젝트 요소를 재사용할 수
없다는 점입니다. 프로젝트 정의를 재사용할 수 있으면 다음과 같은 이유로 유용합니다:

- 한 곳에서 변경 사항을 적용할 수 있고 모든 프로젝트에 변경 사항이 자동으로 적용되므로 **유지 관리(** )가 쉬워집니다.
- 이를 통해 새 프로젝트가 준수할 수 있는 **규칙** 을 정의할 수 있습니다.
- 프로젝트가 더 **일관성 있게** 따라서 불일치로 인해 빌드가 중단될 가능성이 훨씬 적습니다.
- 기존 로직을 재사용할 수 있기 때문에 새 프로젝트를 추가하는 것은 쉬운 작업이 됩니다.

튜이스트에서는 **프로젝트 설명 도우미** 라는 개념 덕분에 매니페스트 파일에서 코드를 재사용할 수 있습니다.

> [!팁] 튜이스트만의 자산 많은 조직이 프로젝트 설명 도우미를 좋아하는 이유는 플랫폼 팀이 자체 규칙을 코드화하고 프로젝트를 설명할 수 있는
> 자체 언어를 만들 수 있는 플랫폼이 있기 때문입니다. 예를 들어, YAML 기반 프로젝트 생성기는 자체적인 YAML 기반 템플릿 솔루션을
> 만들거나 조직이 도구를 구축하도록 강요해야 합니다.

## 프로젝트 설명 도우미 {#project-description-helpers}

프로젝트 설명 헬퍼는 매니페스트 파일이 가져올 수 있는 모듈( `ProjectDescriptionHelpers`)로 컴파일되는 Swift
파일입니다. 이 모듈은 `Tuist/ProjectDescriptionHelpers` 디렉터리에 있는 모든 파일을 수집하여 컴파일됩니다.

파일 상단에 가져오기 문을 추가하여 매니페스트 파일로 가져올 수 있습니다:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`프로젝트 설명 헬퍼` 는 다음 매니페스트에서 사용할 수 있습니다:
- `Project.swift`
- `Package.swift` ( `#TUIST` 컴파일러 플래그 뒤에만)
- `Workspace.swift`

## 예 {#예제}

아래 스니펫에는 `Project` 모델을 확장하여 정적 생성자를 추가하는 방법과 `Project.swift` 파일에서 이를 사용하는 방법에 대한
예시가 포함되어 있습니다:

::: 코드 그룹
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
:::

> [!팁] 규칙을 설정하는 도구 이 함수를 통해 대상 이름, 번들 식별자 및 폴더 구조에 대한 규칙을 정의하는 방법에 유의하세요.
