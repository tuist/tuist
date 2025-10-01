---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGen 프로젝트 마이그레이션 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)은 [구성
형식](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)으로
YAML을 사용하여 Xcode 프로젝트를 정의하는 프로젝트 생성 도구입니다. 많은 조직 **에서 Xcode 프로젝트로 작업할 때 발생하는 잦은
Git 충돌에서 벗어나기 위해 이 도구를 채택했습니다.** 하지만 잦은 Git 충돌은 조직이 겪는 많은 문제 중 하나일 뿐입니다. Xcode는
개발자가 프로젝트를 대규모로 유지 관리하고 최적화하기 어렵게 만드는 많은 복잡성과 암시적 구성에 노출되어 있습니다. XcodeGen은 프로젝트
관리자가 아니라 Xcode 프로젝트를 생성하는 도구이기 때문에 설계상 이러한 기능이 부족합니다. Xcode 프로젝트를 생성하는 것 이상으로
도움이 되는 도구가 필요하다면 Tuist를 고려해 볼 수 있습니다.

> [!팁] YAML보다 스위프트 많은 조직에서 프로젝트 생성 도구로 스위프트를 선호하는데, 이는 스위프트를 구성 형식으로 사용하기 때문입니다.
> Swift는 개발자에게 익숙한 프로그래밍 언어로, Xcode의 자동 완성, 유형 검사 및 유효성 검사 기능을 편리하게 사용할 수 있습니다.

다음은 프로젝트를 XcodeGen에서 Tuist로 마이그레이션하는 데 도움이 되는 몇 가지 고려 사항과 지침입니다.

## 프로젝트 생성 {#project-generation}

Tuist와 XcodeGen은 모두 프로젝트 선언을 Xcode 프로젝트 및 워크스페이스로 변환하는 `generate` 명령을 제공합니다.

::: 코드 그룹

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
:::

차이점은 편집 환경에 있습니다. 튜이스트에서는 `tuist edit` 명령을 실행하면 즉시 Xcode 프로젝트가 생성되어 바로 열어 작업을
시작할 수 있습니다. 이 기능은 프로젝트를 빠르게 변경하고 싶을 때 특히 유용합니다.

## `project.yaml` {#projectyaml}

XcodeGen의 `project.yaml` 설명 파일은 `Project.swift` 이 됩니다. 또한 프로젝트가 워크스페이스에서 그룹화되는
방식을 사용자 지정하는 방법으로 `Workspace.swift` 을 가질 수 있습니다. 다른 프로젝트의 대상을 참조하는
`Project.swift` 프로젝트를 가질 수도 있습니다. 이러한 경우 Tuist는 모든 프로젝트를 포함한 Xcode 워크스페이스를
생성합니다.

::: 코드 그룹

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

> [!TIP] XCODE의 언어 XcodeGen과 Tuist는 모두 Xcode의 언어와 개념을 수용합니다. 그러나 Tuist의 Swift 기반
> 구성은 Xcode의 자동 완성, 유형 검사 및 유효성 검사 기능을 편리하게 사용할 수 있도록 해줍니다.

## 사양 템플릿 {#spec-templates}

프로젝트 구성을 위한 언어로서 YAML의 단점 중 하나는 YAML 파일 간 재사용성을 기본적으로 지원하지 않는다는 것입니다. 이는 프로젝트를
설명할 때 흔히 발생하는 요구 사항으로, XcodeGen은 *"템플릿"* 이라는 자체 솔루션으로 이를 해결해야 했습니다. Tuist의 재사용
기능은 언어 자체인 Swift와
<LocalizedLink href="/guides/features/projects/code-sharing">프로젝트 설명
도우미</LocalizedLink>라는 Swift 모듈을 통해 모든 매니페스트 파일에서 코드를 재사용할 수 있게 해줍니다.

::: 코드 그룹
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
