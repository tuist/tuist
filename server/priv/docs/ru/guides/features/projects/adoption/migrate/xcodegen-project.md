---
{
  "title": "Миграция проекта с XcodeGen",
  "titleTemplate": ":title · Миграция · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как перенести проекты с XcodeGen на Tuist."
}
---
# Миграция проекта XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) — это инструмент генерации проектов, который использует YAML в качестве [формата конфигурации](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) для определения проектов Xcode. Многие организации **выбрали его, пытаясь избежать частых конфликтов в Git, возникающих при работе с проектами Xcode.** Однако частые конфликты в Git — лишь одна из многих проблем, с которыми сталкиваются организации. Xcode предоставляет разработчикам множество сложных и неявных настроек, что затрудняет поддержку и оптимизацию проектов на масштабе. XcodeGen не решает эти проблемы по своей природе, поскольку это инструмент для генерации проектов Xcode, а не менеджер проектов. Если вам нужен инструмент, который помогает не только генерировать проекты Xcode, стоит рассмотреть Tuist.

> [!TIP]
> **Swift вместо YAML**
>
> Многие организации также предпочитают Tuist в качестве инструмента генерации проектов, потому что он использует Swift в качестве формата конфигурации. Swift — это язык программирования, знакомый разработчикам, который предоставляет им удобство использования функций автодополнения, проверки типов и валидации в Xcode.


Ниже приведены некоторые рекомендации и соображения, которые помогут вам перенести ваши проекты с XcodeGen на Tuist.

## Генерация проекта {#project-generation}

И Tuist, и XcodeGen предоставляют команду `generate`, которая преобразует объявление вашего проекта в проекты и рабочие области Xcode.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Разница заключается в опыте редактирования. В Tuist вы можете выполнить команду `tuist edit`, которая на лету генерирует проект Xcode, который можно открыть и начать с ним работать. Это особенно полезно, когда нужно быстро внести изменения в проект.

## `project.yaml` {#projectyaml}

Файл описания `project.yaml` в XcodeGen становится `Project.swift`. Кроме того, вы можете использовать `Workspace.swift`, чтобы настроить группировку проектов в рабочих областях. Также можно иметь файл проекта `Project.swift` с целями, которые ссылается на цели из других проектов. В таких случаях Tuist сгенерирует рабочую область Xcode, включающую все проекты.

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
> **Язык Xcode**
>
> И XcodeGen, и Tuist используют язык и концепции Xcode. Однако конфигурация Tuist на основе Swift предоставляет вам удобство использования функций автодополнения, проверки типов и валидации в Xcode.


## Шаблоны спецификаций {#spec-templates}

Один из недостатков YAML как языка для конфигурации проектов заключается в том, что он не поддерживает повторное использование кода между файлами YAML «из коробки». Это распространенная потребность при описании проектов, которую XcodeGen пришлось решать с помощью собственного проприетарного решения под названием *«шаблоны»*. В Tuist возможность повторного использования встроена в сам язык Swift и реализуется через модуль Swift под названием <.localized_link href="/guides/features/projects/code-sharing">помощники описания проекта</.localized_link>, которые позволяют повторно использовать код во всех файлах манифеста.

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
