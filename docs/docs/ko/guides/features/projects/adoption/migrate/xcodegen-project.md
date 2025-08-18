---
{
  "title": "Migrate an XcodeGen project자동",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Develop · Guides · Tuist",
  "description": "XcodeGen에서 Tuist로 프로젝트를 마이그레이션 하는 방법을 배웁니다."
}
---
# Migrate an XcodeGen project {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 Xcode 프로젝트를 정의하기 위해 [구성 포맷](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)으로 YAML을 사용하는 프로젝트 생성 툴입니다. 많은 조직에서 **Xcode 프로젝트로 작업하면 빈번하게 발생하는 Git 충돌을 벗어나기 위해 채택했습니다.** 그러나 Git 충돌은 조직에서 경험하는 많은 문제 중 하나에 불과합니다. Xcode는 개발자에게 많은 복잡성과 암시적 구성을 노출시켜서 대규모 프로젝트를 유지하고 최적화 하기 어렵게 만듭니다. XcodeGen은 프로젝트 관리 도구가 아닌 Xcode 프로젝트를 생성하는 툴이므로 설계상 부족한 점이 있습니다. Xcode 프로젝트 생성하는 것 이상의 툴이 필요하다면 Tuist를 고려해 보시기 바랍니다.

> [!TIP] SWIFT OVER YAML\
> 많은 조직에서 구성 포맷으로 Swift를 사용하기 때문에 프로젝트 생성 툴로 Tuist를 선호합니다. Swift는 개발자에게 친숙한 프로그래밍 언어이며 Xcode의 자동 완성, 타입 검사, 그리고 기능 검증을 편리하게 사용할 수 있습니다.

다음은 XcodeGen에서 Tuist로 프로젝트를 마이그레이션 하는데 도움이 되는 몇 가지 고려사항과 지침입니다.

## 프로젝트 생성 {#project-generation}

Tuist와 XcodeGen은 프로젝트 선언을 Xcode 프로젝트와 워크스페이스로 변환하는 `generate` 명령어를 제공합니다.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```

:::

차이점은 편집에 있습니다. Tuist를 사용하면 Xcode 프로젝트를 생성하고 열어서 작업을 시작할 수 있는 `tuist edit` 명령어를 수행할 수 있습니다. 이 기능은 프로젝트를 빠르게 변경할 때 유용합니다.

## `project.yaml` {#projectyaml}

XcodeGen의 `project.yaml` 파일이 `Project.swift` 파일이 됩니다. 게다가 프로젝트를 워크스페이스에서 그룹화하는 방식을 사용자 정의할 수 있는 `Workspace.swift`를 가질 수 있습니다. 다른 프로젝트의 타겟을 참조하는 타겟을 가지는 `Project.swift`를 가질 수도 있습니다. 이런 경우 Tuist는 모든 프로젝트를 포함하는 Xcode Workspace를 생성합니다.

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```

:::

> [!TIP] XCODE의 언어
> XcodeGen과 Tuist 모두 Xcode의 언어와 개념을 수용합니다. 그러나 Tuist의 Swift 기반 구성은 Xcode의 자동 완성, 타입 검사, 그리고 기능 검증을 쉽게 사용하도록 제공합니다.

## 스펙 템플릿 {#spec-templates}

프로젝트 구성으로 YAML 언어의 단점 중 하나는 YAML 파일은 재사용을 지원하지 않습니다. 이것은 프로젝트를 설명할 때 흔히 존재하는 것으로 XcodeGen은 \*"templates"\*이라는 자체 솔루션으로 이를 해결해야 했습니다. Tuist의 재사용성은 Swift 언어 자체에 내장되어 있으며, <0>project description helpers</0>라는 Swift 모듈을 통해 모든 매니페스트 파일에서 재사용할 수 있습니다.

::: code-group

```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```

```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
