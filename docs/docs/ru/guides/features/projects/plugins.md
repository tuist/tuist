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
  описанию проектов</LocalizedLink> для нескольких проектов.
- <LocalizedLink href="/guides/features/projects/templates">Шаблоны</LocalizedLink>
  в нескольких проектах.
- Задачи по нескольким проектам.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Шаблон
  Resource accessor</LocalizedLink> для нескольких проектов

Обратите внимание, что плагины разработаны как простой способ расширения
функциональности Tuist. Поэтому существуют **некоторые ограничения, которые
следует учитывать**:

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних Swift packages
- Плагин не может использовать хелперы описания проекта из проекта, который
  использует данный плагин.

Если вам нужна большая гибкость, подумайте о том, чтобы предложить функцию для
инструмента или создать собственное решение на основе фреймворка генерации
Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Вспомогательный плагин для описания проекта {#project-description-helper-plugin}

Вспомогательный плагин для описания проекта представлен каталогом, содержащим
файл манифеста `Plugin.swift`, в котором объявлено имя плагина, и каталогом
`ProjectDescriptionHelpers`, содержащим вспомогательные файлы Swift.

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

Если вам нужно предоставить общий доступ к
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">синтезированным
аксессорам ресурсов</LocalizedLink>, вы можете использовать этот тип плагина.
Плагин представлен каталогом, содержащим файл манифеста `Plugin.swift`, в
котором объявлено имя плагина, и каталогом `ResourceSynthesizers`, содержащим
файлы шаблонов аксессоров ресурсов.


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

Название шаблона представляет собой версию типа ресурса, написанную в стиле
[camel case](https://en.wikipedia.org/wiki/Camel_case):

| Тип ресурса       | Имя файла шаблона          |
| ----------------- | -------------------------- |
| Струны            | `Строки.трафарет`          |
| Ресурсы           | `Активы.трафарет`          |
| Списки свойств    | `Plists.stencil`           |
| Шрифты            | `Шрифты.трафарет`          |
| Основные данные   | `CoreData.stencil`         |
| Interface Builder | `InterfaceBuilder.stencil` |
| JSON              | `JSON.stencil`             |
| YAML              | `YAML.stencil`             |

При определении синтезаторов ресурсов в проекте вы можете указать имя плагина,
чтобы использовать шаблоны из этого плагина:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Плагин задачи <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Плагины задач больше не поддерживаются. Ознакомьтесь с [этой записью в
блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), если вы
ищете решение для автоматизации вашего проекта.
<!-- -->
:::

Задачи — это `$PATH`-exposed исполняемые файлы, которые можно вызвать с помощью
команды `tuist`, если они следуют соглашению об именовании `tuist-<task-name>`.
В более ранних версиях Tuist предоставлял некоторые слабые соглашения и
инструменты в рамках `tuist plugin` для `build`, `run`, `test` и `archive`
задач, представленных исполняемыми файлами в Swift packages, но мы отказались от
этой функции, поскольку она увеличивает нагрузку на обслуживание и сложность
инструмента.</task-name>

Если вы использовали Tuist для распределения задач, мы рекомендуем создать ваш
- Вы можете продолжать использовать `ProjectAutomation.xcframework`,
  распространяемый с каждым выпуском Tuist, чтобы получить доступ к графу
  проекта из вашей логики с помощью `let graph = try Tuist.graph()`. Команда
  использует системный процесс для запуска команды `tuist` и возвращает
  представление графа проекта в памяти.
- Для распределения задач мы рекомендуем включать в релизы GitHub бинарный файл,
  поддерживающий `arm64` и `x86_64`, а также использовать
  [Mise](https://mise.jdx.dev) в качестве инструмента установки. Чтобы
  проинструктировать Mise о том, как установить ваш инструмент, вам понадобится
  репозиторий плагинов. В качестве примера можно использовать
  [Tuist's](https://github.com/asdf-community/asdf-tuist).
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут
  установить его, выполнив команду `mise install`, они смогут запустить его либо
  напрямую, либо через `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единый
обратно совместимый фреймворк, который предоставляет пользователю доступ ко
всему графу проекта. Кроме того, мы вынесем логику генерации в новый уровень,
`XcodeGraph`, который вы также сможете использовать из своего собственного CLI.
Считайте это созданием своего собственного Tuist.
<!-- -->
:::

## Использование плагинов {#using-plugins}

Чтобы использовать плагин, вам нужно добавить его в файл манифеста
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

`Если вы хотите повторно использовать плагин в проектах, расположенных в разных
репозиториях, вы можете загрузить свой плагин в репозиторий Git и указать на
него в файле` Tuist.swift:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

После добавления плагинов команда ` `tuist install` ` загрузит плагины в
глобальный каталог кэша.

::: info NO VERSION RESOLUTION
<!-- -->
Как вы, возможно, заметили, мы не предоставляем определение версии для плагинов.
Мы рекомендуем использовать теги Git или SHA для обеспечения воспроизводимости.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
При использовании плагина-помощника для описания проекта имя модуля, содержащего
помощники, является именем плагина
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
