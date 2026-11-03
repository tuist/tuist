---
{
  "title": "XcodeGen 프로젝트 마이그레이션",
  "titleTemplate": ":title · 마이그레이션 · 도입 · 프로젝트 · 기능 · 가이드 · Tuist",
  "description": "XcodeGen에서 Tuist로 프로젝트를 마이그레이션하는 방법을 알아보세요."
}
---
# XcodeGen 프로젝트 마이그레이션 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 YAML을 [구성 형식](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)으로 사용하여 Xcode 프로젝트를 정의하는 프로젝트 생성 도구입니다. 많은 조직이 **Xcode 프로젝트 작업 시 자주 발생하는 Git 충돌을 피하기 위해 이를 도입했습니다.** 그러나 빈번한 Git 충돌은 조직이 겪는 여러 문제 중 하나일 뿐입니다. Xcode는 개발자에게 수많은 복잡성과 암시적 구성을 노출시켜, 대규모 프로젝트의 유지보수와 최적화를 어렵게 만듭니다. XcodeGen은 Xcode 프로젝트를 생성하는 도구일 뿐 프로젝트 관리자가 아니기 때문에 설계상 이러한 부분에서 한계가 있습니다. Xcode 프로젝트 생성 이상의 도움을 주는 도구가 필요하다면 Tuist를 고려해 보세요.

> [!TIP]
> **YAML보다 Swift**
>
> 많은 조직이 Tuist를 프로젝트 생성 도구로 선호하는 또 다른 이유는 구성 형식으로 Swift를 사용하기 때문입니다. Swift는 개발자에게 친숙한 프로그래밍 언어이며, Xcode의 자동 완성, 타입 검사 및 검증 기능을 편리하게 사용할 수 있게 해줍니다.


다음은 XcodeGen에서 Tuist로 프로젝트를 마이그레이션하는 데 도움이 되는 고려 사항과 지침입니다.

## 프로젝트 생성 {#project-generation}

Tuist와 XcodeGen 모두 프로젝트 선언을 Xcode 프로젝트 및 워크스페이스로 변환하는 `generate` 명령을 제공합니다.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

차이는 편집 경험에 있습니다. Tuist에서는 `tuist edit` 명령을 실행하여 즉시 Xcode 프로젝트를 생성하고 열어 작업을 시작할 수 있습니다. 프로젝트에 빠른 변경 사항을 적용해야 할 때 특히 유용합니다.

## `project.yaml` {#projectyaml}

XcodeGen의 `project.yaml` 설명 파일은 `Project.swift`가 됩니다. 또한 워크스페이스 내 프로젝트 그룹화 방식을カスタ마이즈하기 위해 `Workspace.swift`를 사용할 수 있습니다. 다른 프로젝트의 타겟을 참조하는 타겟을 포함한 프로젝트 `Project.swift`도 만들 수 있습니다. 이 경우 Tuist는 모든 프로젝트를 포함하는 Xcode 워크스페이스를 생성합니다.

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
<!-- -->
:::

> [!TIP]
> **Xcode의 언어**
>
> XcodeGen과 Tuist 모두 Xcode의 언어와 개념을 따릅니다. 다만 Tuist의 Swift 기반 구성은 Xcode의 자동 완성, 타입 검사 및 검증 기능을 편리하게 사용할 수 있게 해줍니다.


## 스펙 템플릿 {#spec-templates}

프로젝트 구성 언어로서 YAML의 단점 중 하나는 기본적으로 YAML 파일 간 재사용성을 지원하지 않는다는 점입니다. 이는 프로젝트 설명 시 흔히 필요한 요구사항이며, XcodeGen은 이를 *"템플릿"* 이라는 자체 고유 솔루션으로 해결했습니다. Tuist에서는 재사용성이 언어 자체인 Swift에 내장되어 있으며, <.localized_link href="/guides/features/projects/code-sharing">프로젝트 설명 헬퍼</.localized_link>라는 Swift 모듈을 통해 모든 매니페스트 파일에서 코드를 재사용할 수 있습니다.

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
