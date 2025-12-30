---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Плагины {#plugins}

Плагины - это инструмент для совместного и повторного использования артефактов
Tuist в нескольких проектах. Поддерживаются следующие артефакты:

- <LocalizedLink href="/guides/features/projects/code-sharing">Помощники по описанию проектов</LocalizedLink> в нескольких проектах.
- <LocalizedLink href="/guides/features/projects/templates">Шаблоны</LocalizedLink>
  для нескольких проектов.
- Выполнение задач в рамках нескольких проектов.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Шаблон ресурса accessor</LocalizedLink> для нескольких проектов

Обратите внимание, что плагины - это простой способ расширить функциональность
Tuist. Поэтому есть **некоторые ограничения, которые следует учитывать**:

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних пакетов Swift
- Плагин не может использовать хелперы описания проекта из проекта, в котором
  используется плагин.

Если вам нужна большая гибкость, предложите свою функцию для инструмента или
создайте собственное решение на основе генераторной схемы Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Вспомогательный плагин для описания проекта {#project-description-helper-plugin}

Плагин-помощник для описания проекта представлен директорией, содержащей файл
манифеста `Plugin.swift`, в котором объявлено имя плагина, и директорию
`ProjectDescriptionHelpers`, содержащую файлы-помощники Swift.

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

Если вам необходимо совместно использовать
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">синтезированные аксессоры ресурсов</LocalizedLink>, вы можете использовать этот тип плагина.
Плагин представлен директорией, содержащей файл манифеста `Plugin.swift`, в
котором объявляется имя плагина, и директорию `ResourceSynthesizers`, содержащую
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

Имя шаблона - это [camel case](https://en.wikipedia.org/wiki/Camel_case) версия
типа ресурса:

| Тип ресурса             | Имя файла шаблона          |
| ----------------------- | -------------------------- |
| Струны                  | `Строки.трафарет`          |
| Активы                  | `Активы.трафарет`          |
| Списки недвижимости     | `Plists.stencil`           |
| Шрифты                  | `Шрифты.трафарет`          |
| Основные данные         | `CoreData.stencil`         |
| Построитель интерфейсов | `InterfaceBuilder.stencil` |
| JSON                    | `JSON.stencil`             |
| YAML                    | `YAML.stencil`             |

При определении синтезаторов ресурсов в проекте можно указать имя плагина, чтобы
использовать шаблоны из этого плагина:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Плагин задачи <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Плагины задач устарели. Ознакомьтесь с [этой записью в
блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), если вы
ищете решение для автоматизации своего проекта.
<!-- -->
:::

Задачи - это `$PATH`-экспонируемые исполняемые файлы, которые вызываются
командой `tuist`, если они следуют соглашению об именовании `tuist-<task-name>`.
В предыдущих версиях Tuist предоставлял некоторые слабые соглашения и
инструменты под `tuist plugin` для `build`, `run`, `test` и `archive` задач,
представленных исполняемыми файлами в Swift-пакетах, но мы отказались от этой
возможности, поскольку она увеличивает нагрузку на поддержку и сложность
инструмента.

Если вы использовали Tuist для распределения задач, мы рекомендуем создать свой
- Вы можете продолжать использовать `ProjectAutomation.xcframework`,
  распространяемый с каждым выпуском Tuist, чтобы иметь доступ к графу проекта
  из вашей логики с помощью `let graph = try Tuist.graph()`. Команда использует
  системный процесс для выполнения команды `tuist` и возвращает представление
  графа проекта в памяти.
- Для распространения задач мы рекомендуем включать жирные бинарники,
  поддерживающие `arm64` и `x86_64`, в релизы на GitHub и использовать
  [Mise](https://mise.jdx.dev) в качестве инструмента установки. Чтобы указать
  Mise, как установить ваш инструмент, вам понадобится репозиторий плагинов. Вы
  можете использовать [Tuist's](https://github.com/asdf-community/asdf-tuist) в
  качестве ссылки.
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут
  установить его, выполнив команду `mise install`, они смогут запускать его,
  вызывая напрямую или через `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единый
обратно совместимый фреймворк, который откроет пользователю всю полноту графа
проекта. Более того, мы выделим логику генерации в новый слой, `XcodeGraph`,
который вы также сможете использовать из своего собственного CLI. Считайте, что
вы создали свой собственный Tuist.
<!-- -->
:::

## Использование плагинов {#using-plugins}

Чтобы использовать плагин, вам нужно добавить его в файл манифеста вашего
проекта
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Если вы хотите повторно использовать плагин в проектах, которые находятся в
разных репозиториях, вы можете поместить свой плагин в Git-репозиторий и
ссылаться на него в файле `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

После добавления плагинов `tuist install` соберет плагины в глобальный каталог
кэша.

::: info NO VERSION RESOLUTION
<!-- -->
Как вы могли заметить, мы не предоставляем разрешение версий для плагинов. Мы
рекомендуем использовать Git-теги или SHA для обеспечения воспроизводимости.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
При использовании плагина-помощника для описания проекта имя модуля, в котором
содержатся помощники, является именем плагина
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
