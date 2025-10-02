---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Перенос проекта XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) - это инструмент генерации
проектов, который использует YAML в качестве [формата
конфигурации](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
для определения проектов Xcode. Многие организации **взяли его на вооружение,
пытаясь избавиться от частых конфликтов Git, возникающих при работе с проектами
Xcode.** Однако частые конфликты в Git - это лишь одна из многих проблем, с
которыми сталкиваются организации. Xcode открывает разработчикам множество
тонкостей и неявных конфигураций, которые затрудняют поддержку и оптимизацию
проектов в масштабе. XcodeGen не справляется с этой задачей, потому что это
инструмент, который генерирует проекты Xcode, а не менеджер проектов. Если вам
нужен инструмент, который поможет вам не только генерировать проекты Xcode, вам
стоит обратить внимание на Tuist.

> [!СОВЕТ] SWIFT OVER YAML Многие организации предпочитают Tuist в качестве
> инструмента для создания проектов еще и потому, что он использует Swift в
> качестве формата конфигурации. Swift - это язык программирования, с которым
> разработчики хорошо знакомы и который позволяет им использовать функции
> автодополнения, проверки типов и валидации Xcode.

Ниже приведены некоторые соображения и рекомендации, которые помогут вам
перенести проекты из XcodeGen в Tuist.

## Генерация проекта {#project-generation}

И Tuist, и XcodeGen предоставляют команду `generate`, которая превращает
декларацию вашего проекта в проекты и рабочие пространства Xcode.

::: кодовая группа

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
:::

Разница заключается в возможности редактирования. В Tuist вы можете выполнить
команду `tuist edit`, которая на лету сгенерирует проект Xcode, который можно
открыть и начать работать. Это особенно удобно, когда нужно быстро внести
изменения в проект.

## `project.yaml` {#projectyaml}

Файл описания XcodeGen `project.yaml` становится `Project.swift`. Более того, вы
можете иметь `Workspace.swift` как способ настройки того, как проекты
группируются в рабочих пространствах. Вы также можете иметь проект
`Project.swift` с целями, которые ссылаются на цели из других проектов. В этих
случаях Tuist сгенерирует рабочее пространство Xcode, включающее все проекты.

::: кодовая группа

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

> [ЯЗЫК XCODE И XcodeGen, и Tuist используют язык и концепции Xcode. Однако
> конфигурация Tuist, основанная на Swift, обеспечивает удобство использования
> функций автозавершения, проверки типов и валидации Xcode.

## Шаблоны спецификаций {#spec-templates}

Одним из недостатков YAML как языка для конфигурирования проектов является то,
что он не поддерживает повторное использование YAML-файлов из коробки. Это
частая потребность при описании проектов, которую XcodeGen пришлось решать с
помощью собственного решения под названием *"templates"*. В Tuist'е возможность
повторного использования встроена в сам язык Swift, а также в модуль Swift под
названием <LocalizedLink href="/guides/features/projects/code-sharing">project
description helpers</LocalizedLink>, который позволяет повторно использовать код
во всех ваших файлах манифеста.

::: кодовая группа
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
