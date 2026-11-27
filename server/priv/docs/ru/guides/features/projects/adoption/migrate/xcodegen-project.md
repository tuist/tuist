---
{
  "title": "Миграция проекта XcodeGen",
  "titleTemplate": ":title · Миграция · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как перенести ваши проекты из XcodeGen в Tuist."
}
---
# Миграция проекта XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) — это инструмент генерации проектов, который использует YAML в качестве [формата конфигурации](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) для описания проектов Xcode. Многие организации **внедрили его, пытаясь избежать частых конфликтов в Git, возникающих при работе с проектами Xcode.** Однако частые конфликты в Git — лишь одна из многих проблем, с которыми сталкиваются организации. Xcode предоставляет разработчикам множество сложных и неявных настроек, что затрудняет поддержку и оптимизацию проектов на масштабе. XcodeGen изначально не решает эти задачи, поскольку он генерирует проекты Xcode, а не управляет ими. Если вам нужен инструмент, который помогает не только генерировать проекты Xcode, стоит рассмотреть Tuist. Мигрировать для использования Tuist не обязательно: статья [XcodeGen vs Tuist](https://tuist.dev/compare/xcodegen) объясняет, какие возможности, такие как кэш Xcode и аналитика сборок, работают с проектом XcodeGen и когда миграция оправдана.

> [!TIP]
> **Swift вместо YAML**
>
> Многие организации также предпочитают Tuist в качестве инструмента генерации проектов, потому что он использует Swift в качестве формата конфигурации. Swift — это язык программирования, знакомый разработчикам, который обеспечивает удобство использования функций автодополнения, проверки типов и валидации в Xcode.


Ниже приведены рекомендации и соображения, которые помогут вам перенести проекты с XcodeGen на Tuist.

## Генерация проекта {#project-generation}

И Tuist, и XcodeGen предоставляют команду `generate`, которая преобразует декларацию вашего проекта в проекты и рабочие области Xcode.

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

Файл описания `project.yaml` в XcodeGen становится файлом `Project.swift`. Кроме того, вы можете использовать `Workspace.swift`, чтобы настроить группировку проектов в рабочих областях. Также можно создать файл проекта `Project.swift` с целями, которые ссылается на цели из других проектов. В таких случаях Tuist сгенерирует рабочую область Xcode, включающую все проекты.

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
> И XcodeGen, и Tuist используют язык и концепции Xcode. Однако конфигурация Tuist на основе Swift обеспечивает удобство использования функций автодополнения, проверки типов и валидации в Xcode.


## Шаблоны спецификаций {#spec-templates}

Один из недостатков YAML как языка для конфигурации проектов заключается в том, что он не поддерживает повторное использование кода между файлами YAML «из коробки». Это частая потребность при описании проектов, которую XcodeGen решал с помощью собственного проприетарного решения под названием *«шаблоны»*. В Tuist возможность повторного использования встроена в сам язык Swift и реализуется через модуль Swift под названием <.localized_link href="/guides/features/projects/code-sharing">project description helpers</.localized_link>, который позволяет повторно использовать код во всех файлах манифестов.

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
import ProjectDescriptionHelpers

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature"))
```
:::
