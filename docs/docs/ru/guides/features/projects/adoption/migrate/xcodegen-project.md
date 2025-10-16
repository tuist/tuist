---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Миграция проекта XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) – это инструмент для генерации
проектов, который использует YAML как [формат
конфигурации](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
для описания Xcode-проектов. Многие организации **перешли на него, пытаясь
избавиться от частых конфликтов в Git, возникающих при работе с
Xcode-проектами**. Однако частые конфликты в Git – лишь одна из множества
проблем, с которыми сталкиваются команды. Xcode открывает разработчикам
множество нюансов и неявных конфигураций, которые усложняют сопровождение и
оптимизацию проектов в масштабах организации. XcodeGen в этом плане ограничен по
своей природе, поскольку является инструментом генерации Xcode-проектов, а не
менеджером проектов. Если вам нужен инструмент, который выходит за рамки простой
генерации Xcode-проектов, стоит рассмотреть Tuist.

::: tip SWIFT ВМЕСТО YAML
<!-- -->
Многие организации также предпочитают Tuist в качестве инструмента генерации
проектов, поскольку он использует Swift в качестве формата конфигурации. Swift –
это язык программирования, знакомый разработчикам, который предоставляет им
такие удобства, как автодополнение, проверка типов и валидация в Xcode.
<!-- -->
:::

Ниже приведены некоторые соображения и рекомендации, которые помогут вам
перенести ваши проекты из XcodeGen в Tuist.

## Генерация проекта {#project-generation}

И Tuist, и XcodeGen предоставляют команду `generate`, которая преобразует
описание вашего проекта в проекты и рабочие пространства Xcode.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Разница заключается в опыте редактирования. В Tuist вы можете выполнить команду
`tuist edit`, которая на лету генерирует проект Xcode, который можно открыть и
сразу начать с ним работу. Это особенно удобно, когда нужно быстро внести
изменения в проект.

## `project.yaml` {#projectyaml}

XcodeGen's `project.yaml` description file becomes `Project.swift`. Moreover,
you can have `Workspace.swift` as a way to customize how projects are grouped in
workspaces. You can also have a project `Project.swift` with targets that
reference targets from other projects. In those cases, Tuist will generate an
Xcode Workspace including all the projects.

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

::: tip XCODE'S LANGUAGE
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
