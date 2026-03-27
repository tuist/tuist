---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGen 프로젝트 마이그레이션 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen)는 Xcode 프로젝트들을 정의하기 위해 YAML를
[환경설정
형식](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)으로
사용하는 프로젝트 생성 도구 입니다. 많은 조직들이 **적용합니다 Xcode 프로젝트로 작업할 때 발생하는 잦은 Git 병합 충돌에서 벗어나기
위해** 하지만, 잦은 Git 충돌은 그들이 경험하는 많은 문제 중 하나일 뿐 입니다. Xcode는 유지보수와 확장을 위한 프로젝트 최적화를
어렵게 만드는 많은 복잡하고 불명확한 환경 설정을 개발자들에게 보여줍니다. XcodeGen는 그런 문제에 집중되어 있지만, 프로젝트 관리자가
아닌 그저 Xcode 프로젝트를 생성하는 도구일 뿐 입니다. 만약 여러분이 Xcode 프로젝트 생성 이상의 기능이 필요하다면 Tuist를 검토해
보세요.

::: tip YAML대신 SWIFT
<!-- -->
많은 조직들이 Swift로 환경 설정을 할 수 있기 때문에 Tuist를 프로젝트 생성 도구로써 선호 합니다. Swift는 개발자들에게 친숙하고
Xcode가 제공하는 자동 완성, 타입 검사, 기능의 유효성 검사 등의 편의성을 사용 할 수 있는 프로그래밍 언어 입니다.
<!-- -->
:::

프로젝트를 XcodeGen에서 Tuist로 전환할 때 고려해야 할 것들과 준수 사항.

## 프로젝트 생성 {#project-generation}

Tuist와 XcodeGen둘 다 프로젝트 선언을 Xcode 프로젝트와 Workspace로 변환하는 `generate` 명령을 제공 합니다.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

차이점은 수정할 때 나타납니다. Tuist에서는 열어서 작업할 수 있는 Xcode 프로젝트를 생성하는 `tuist edit` 명령을 실행할 수
있는데 특히 프로젝트를 빠르게 수정하고 싶을 때 유용합니다.

## `project.yaml` {#projectyaml}

XcodeGen의 `project.yaml` 설명 파일은 `Project.swift`로 바뀌고 여러분은 어떻게 프로젝트들을 그룹화 할지 설정할
수 있는 `Workspace.swift`를 가집니다. 또한 다른 프로젝트들의 Target들을 참조하는 Target을 가진 프로젝트인
`Project.swift`도 가집니다. . 이런 경우, Tuist 는 모든 프로젝트를 포함해 Xcode Workspace를 생성할 것 입니다.

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

::: tip XCODE의 언어
<!-- -->
XcodeGen과 Tuist, 둘 다 Xcode의 언어와 개념들을 수용하지만. Tuist의 Swift기반 설정은 Xcode의 자동 완성,
Type 검사, 기능에 대한 유효성 검사를 사용하게 해주는 편의성을 제공합니다.
<!-- -->
:::

## 규격 양식 {#spec-templates}

YAML를 프로젝트 환경 설정으로 사용하는 것의 단점 중 하나는 YAML의 재사용을 지원하지 않는 것 입니다. 이것은 XcodeGen이
프로젝트를 설명할 때 발생하는 일반적인 요구 사항인데, XcodeGen에서는 *"templates"* 라는 자체 솔루션을 통해 해결해야
했습니다. Tuist의 재사용성은 Swift 언어 자체에 만들어져 있고 모든 Manifest 파일들에서 설정 코드를 재 사용 할 수 있게 해주는
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>라는 이름의 Swift 모듈을 통해 이루어 집니다.

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
