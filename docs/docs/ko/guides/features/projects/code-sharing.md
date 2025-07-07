---
title: Code sharing
titleTemplate: :title · Projects · Features · Guides · Tuist
description: manifest 파일 간의 코드 공유를 통해 중복을 줄이고 일관성을 유지하는 방법을 알아보세요
---

# Code sharing {#code-sharing}

Xcode를 대규모 프로젝트에서 사용할 때의 한계점 중 하나는 `.xcconfig` 파일을 통한 빌드 설정 외에는 프로젝트의 다른 요소들을 재사용할 수 없다는 점입니다. 프로젝트 정의를 재사용할 수 있으면 다음과 같은 장점이 있습니다:

- 변경 사항을 한 곳에서 적용하면 모든 프로젝트에 자동으로 반영되므로 **유지보수**가 수월해집니다.
- 새로운 프로젝트들이 따를 수 있는 규칙을 정의할 수 있습니다.
- 프로젝트가 더 `일관성`을 갖게 되어, 불일치로 인한 빌드 실패의 가능성이 줄어듭니다.
- 기존 로직을 재사용할 수 있어 새로운 프로젝트 추가가 쉬워집니다.

**project description helpers**를 통해 Tuist에서는 manifest 파일 간에 코드를 재사용할 수 있습니다.

> [!TIP] Tuist만의 독자적인 가치
> 많은 조직들이 Tuist를 선호하는 이유는 project description helpers가 플랫폼 팀에게 자신들만의 convention을 코드화하고, 프로젝트를 설명하는 독자적인 언어를 정의할 수 있는 기반을 제공하기 때문입니다. 예를 들어, YAML 기반 project generator들은 자체 YAML 기반 독점 템플릿 솔루션을 만들거나, 조직이 이를 기반으로 도구를 구축하도록 강요해야 합니다.

## Project description helpers {#project-description-helpers}

Project description helpers는 컴파일되어 manifest 파일에서 가져올 수 있는 `ProjectDescriptionHelpers` 모듈로 변환되는 Swift 파일입니다. 이 모듈은 `Tuist/ProjectDescriptionHelpers` 디렉토리에 있는 모든 파일을 모아 컴파일됩니다.

manifest 파일 맨 위에 import 문을 추가하여 이를 가져올 수 있습니다:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers`는 다음 manifest에서 사용할 수 있습니다:

- `Project.swift`
- `Package.swift` (`#TUIST` compiler flag 사용 시에만)
- `Workspace.swift`

## 예시 {#example}

아래 코드 스니펫은 `Proejct` 모델을 확장하여 static constructor를 추가하고, 이를 `Project.swift` 파일에서 사용하는 예시입니다:

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
                bundleId: "io.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "io.tuist.\(name)Tests",
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

> [!TIP] 컨벤션(CONVENTION)을 정립하는 도구
> 함수를 통해 target 이름, bundle identifier, 폴더 구조에 대한 컨벤션을 정의하는 방식을 주목하세요.
