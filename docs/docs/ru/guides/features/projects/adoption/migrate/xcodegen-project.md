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
`tuist edit`, которая на лету генерирует Xcode-проект, который можно открыть и
сразу начать с ним работу. Это особенно удобно, когда нужно быстро внести
изменения в проект.

## `project.yaml` {#projectyaml}

Файл описания `project.yaml` из XcodeGen превращается в `Project.swift`. Кроме
того, вы можете использовать `Workspace.swift`, чтобы настраивать, как проекты
объединяются в рабочие пространства. Также можно создать проект `Project.swift`
с целями, которые ссылаются на цели из других проектов. В таких случаях Tuist
сгенерирует рабочее пространство Xcode, включающее все проекты.

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

::: tip ЯЗЫК XCODE
<!-- -->
И XcodeGen, и Tuist используют язык и концепции Xcode. Однако конфигурация Tuist
на основе Swift обеспечивает удобство работы с такими функциями Xcode, как
автодополнение, проверка типов и валидация.
<!-- -->
:::

## Шаблоны спецификаций {#spec-templates}

Одним из недостатков YAML как языка для конфигурации проектов является
отсутствие встроенной поддержки повторного использования кода между
YAML-файлами. Это распространённая потребность при описании проектов, которую
XcodeGen решает с помощью собственного решения под названием *"шаблоны"*. В
Tuist же повторное использование реализовано на уровне самого языка Swift –
через модуль
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>, который позволяет использовать общий код во всех
манифест-файлах проекта.

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
