---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# XcodeGen 프로젝트 마이그레이션 {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) is a project-generation tool
that uses YAML as [a configuration
format](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
to define Xcode projects. Many organizations **adopted it trying to escape from
the frequent Git conflicts that arise when working with Xcode projects.**
However, frequent Git conflicts is just one of the many problems that
organizations experience. Xcode exposes developers with a lot of intricacies and
implicit configurations that make it hard to maintain and optimize projects at
scale. XcodeGen falls short there by design because it's a tool that generates
Xcode projects, not a project manager. If you need a tool that helps you beyond
generating Xcode projects, you might want to consider Tuist.

::: tip YAML대신 SWIFT
<!-- -->
많은 조직들이 Swift로 환경 설정을 할 수 있기 때문에 Tuist를 프로젝트 생성 도구로써 선호 합니다. Swift는 개발자들에게 친숙하고
Xcode가 제공하는 자동 완성, 타입 검사, 기능의 유효성 검사 등의 편의성을 사용 할 수 있는 프로그래밍 언어 입니다.
<!-- -->
:::

What follows are some considerations and guidelines to help you migrate your
projects from XcodeGen to Tuist.

## 프로젝트 생성 {#project-generation}

Both Tuist and XcodeGen provide a `generate` command that turns your project
declaration into Xcode projects and workspaces.

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
Both XcodeGen and Tuist embrace Xcode's language and concepts. However, Tuist's
Swift-based configuration provides you with the convenience of using Xcode's
autocompletion, type-checking, and validation features.
<!-- -->
:::

## Spec templates {#spec-templates}

One of the disadvantages of YAML as a language for project configuration is that
it doesn't support reusability across YAML files out of the box. This is a
common need when describing projects, which XcodeGen had to solve with their own
propietary solution named *"templates"*. With Tuist's re-usability is built into
the language itself, Swift, and through a Swift module named
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink>, which allow reusing code across all your manifest
files.

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
