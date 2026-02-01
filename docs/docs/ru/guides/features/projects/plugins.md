---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Плагины {#plugins}

Плагины — это инструмент для обмена и повторного использования артефактов Tuist
в нескольких проектах. Поддерживаются следующие артефакты:

- <LocalizedLink href="/guides/features/projects/code-sharing">Помощники по
  описанию проекта</LocalizedLink> в нескольких проектах.
- <LocalizedLink href="/guides/features/projects/templates">Шаблоны</LocalizedLink>
  в нескольких проектах.
- Задачи по нескольким проектам.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Шаблон
  доступа к ресурсам</LocalizedLink> в нескольких проектах

Обратите внимание, что плагины предназначены для простого расширения
функциональности Tuist. Поэтому существуют некоторые ограничения, которые
необходимо учитывать **** :

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних Swift packages.
- Плагин не может использовать помощники описания проекта из проекта, который
  использует плагин.

Если вам нужна большая гибкость, рассмотрите возможность предложить функцию для
инструмента или создать собственное решение на основе фреймворка Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Вспомогательный плагин для описания проекта {#project-description-helper-plugin}

Плагин-помощник для описания проекта представлен каталогом, содержащим файл
манифеста `Plugin.swift`, в котором объявляется имя плагина, и каталог
`ProjectDescriptionHelpers`, содержащий файлы Swift-помощников.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### Плагин шаблонов доступа к ресурсам {#resource-accessor-templates-plugin}

Если вам нужно поделиться
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">синтезированными
средствами доступа к ресурсам</LocalizedLink>, вы можете использовать этот тип
плагина. Плагин представлен каталогом, содержащим файл манифеста `Plugin.swift`,
в котором объявляется имя плагина, и каталог `ResourceSynthesizers`, содержащий
файлы шаблонов средств доступа к ресурсам.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

Название шаблона — это версия типа ресурса в формате [camel
case](https://en.wikipedia.org/wiki/Camel_case):

| Тип ресурса              | Имя файла шаблона          |
| ------------------------ | -------------------------- |
| Струны                   | `Строки.трафарет`          |
| Ресурсы                  | `Активы.трафарет`          |
| Списки свойств           | `Plists.stencil`           |
| Шрифты                   | `Шрифты.трафарет`          |
| Основные данные          | `CoreData.stencil`         |
| Интерфейсный конструктор | `InterfaceBuilder.stencil` |
| JSON                     | `JSON.stencil`             |
| YAML                     | `YAML.stencil`             |

При определении синтезаторов ресурсов в проекте вы можете указать имя плагина,
чтобы использовать шаблоны из плагина:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Плагин задачи <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Плагины задач устарели. Ознакомьтесь с [этой записью в
блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), если вы
ищете решение для автоматизации вашего проекта.
<!-- -->
:::

Задачи — это `$PATH`-exposed исполняемые файлы, которые можно вызвать с помощью
`tuist` команды, если они соответствуют соглашению об именовании
`tuist-<task-name>`. В более ранних версиях Tuist предоставлял некоторые слабые
соглашения и инструменты под `tuist plugin` для `build`, `run`, `test` и
`archive` задач, представленных исполняемыми файлами в Swift packages, но мы
отказались от этой функции, поскольку она увеличивает нагрузку на обслуживание и
сложность инструмента.</task-name>

Если вы использовали Tuist для распределения задач, мы рекомендуем создать ваш
- Вы можете продолжать использовать `ProjectAutomation.xcframework`,
  распространяемый с каждым выпуском Tuist, чтобы получить доступ к графу
  проекта из вашей логики с помощью `let graph = try Tuist.graph()`. Команда
  использует системный процесс для запуска `tuist` и возвращает представление
  графа проекта в памяти.
- Для распределения задач мы рекомендуем включить в релизы GitHub бинарный файл,
  поддерживающий `arm64` и `x86_64`, и использовать [Mise](https://mise.jdx.dev)
  в качестве инструмента установки. Чтобы проинструктировать Mise о том, как
  установить ваш инструмент, вам понадобится репозиторий плагинов. Вы можете
  использовать [Tuist's](https://github.com/asdf-community/asdf-tuist) в
  качестве справочного материала.
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут
  установить его, запустив `mise install`, они смогут запустить его либо
  напрямую, либо через `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единую
обратно совместимую структуру, которая раскрывает пользователю всю полноту графа
проекта. Более того, мы извлечем логику генерации в новый слой, `XcodeGraph`,
который вы также сможете использовать из своего собственного CLI. Считайте это
созданием своего собственного Tuist.
<!-- -->
:::

## Использование плагинов {#using-plugins}

Чтобы использовать плагин, вам необходимо добавить его в файл манифеста
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
вашего проекта:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Если вы хотите повторно использовать плагин в разных проектах, которые находятся
в разных репозиториях, вы можете отправить свой плагин в репозиторий Git и
сослаться на него в файле `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

После добавления плагинов команда `tuist install` загрузит плагины в глобальный
кэш-каталог.

::: info NO VERSION RESOLUTION
<!-- -->
Как вы, возможно, заметили, мы не предоставляем разрешение версий для плагинов.
Мы рекомендуем использовать теги Git или SHA для обеспечения воспроизводимости.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
При использовании плагина помощников описания проекта, название модуля,
содержащего помощников, является названием плагина.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
