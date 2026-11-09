---
{
  "title": "Плагины",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать плагины в Tuist для расширения его функциональности."
}
---
# Плагины {#plugins}

Плагины — это инструмент для обмена и повторного использования артефактов Tuist в нескольких проектах. Поддерживаются следующие артефакты:

- <.localized_link href="/guides/features/projects/code-sharing">Хелперы описания проекта</.localized_link> для нескольких проектов.
- <.localized_link href="/guides/features/projects/templates">Шаблоны</.localized_link> для нескольких проектов.
- Задачи для нескольких проектов.
- Шаблон <.localized_link href="/guides/features/projects/synthesized-files">аксессора ресурсов</.localized_link> для нескольких проектов

Обратите внимание, что плагины разработаны как простой способ расширения функциональности Tuist. Поэтому есть **некоторые ограничения, которые следует учитывать**:

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних Swift-пакетов.
- Плагин не может использовать хелперы описания проекта из проекта, который использует этот плагин.

Если вам нужна большая гибкость, рассмотрите предложение новой функции для инструмента или создание собственного решения на основе фреймворка генерации Tuist, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Плагин хелперов описания проекта {#project-description-helper-plugin}

Плагин хелперов описания проекта представляет собой каталог, содержащий файл манифеста `Plugin.swift`, в котором объявляется имя плагина, и каталог `ProjectDescriptionHelpers`, содержащий вспомогательные Swift-файлы.

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

### Плагин шаблонов аксессоров ресурсов {#resource-accessor-templates-plugin}

Если вам нужно поделиться <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">синтезированными аксессорами ресурсов</.localized_link>, вы можете использовать этот тип плагина. Плагин представляет собой каталог, содержащий файл манифеста `Plugin.swift`, в котором объявляется имя плагина, и каталог `ResourceSynthesizers`, содержащий файлы шаблонов аксессоров ресурсов.


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

Имя шаблона — это версия типа ресурса в [camelCase](https://en.wikipedia.org/wiki/Camel_case):

| Тип ресурса | Имя файла шаблона |
| ------------- | ------------------ |
| Strings | Strings.stencil |
| Assets | Assets.stencil |
| Property Lists | Plists.stencil |
| Fonts | Fonts.stencil |
| Core Data | CoreData.stencil |
| Interface Builder | InterfaceBuilder.stencil |
| JSON | JSON.stencil |
| YAML | YAML.stencil |

При определении синтезаторов ресурсов в проекте вы можете указать имя плагина, чтобы использовать шаблоны из этого плагина:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Плагин задач <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

> [!WARNING]
> **Устарело**
>
> Плагины задач устарели. Ознакомьтесь с [этой записью в блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), если вы ищете решение для автоматизации вашего проекта.


Задачи — это исполняемые файлы, доступные через `$PATH`, которые можно вызывать командой `tuist`, если они следуют соглашению об именах `tuist-<task-name>`. В ранних версиях Tuist предоставлял некоторые слабые соглашения и инструменты под `tuist plugin` для `build`, `run`, `test` и `archive` задач, представленных исполняемыми файлами в Swift-пакетах, но мы отказались от этой функции, так как она увеличивает нагрузку на поддержку и сложность инструмента.

Если вы распространяли задачи как плагины, вместо этого собирайте их как отдельные исполняемые файлы:

- Вы можете продолжать использовать `ProjectAutomation.xcframework`, поставляемый с каждым релизом Tuist, чтобы получить доступ к графу проекта из вашей логики с помощью `let graph = try Tuist.graph()`. Он запускает `tuist` как подпроцесс и возвращает представление графа проекта в памяти.
- Для распространения задач мы рекомендуем публиковать универсальный бинарный файл, поддерживающий `arm64` и `x86_64`, в релизах GitHub и использовать [Mise](https://mise.jdx.dev) в качестве инструмента установки. Чтобы указать Mise, как установить ваш инструмент, вам понадобится репозиторий плагина. Вы можете использовать [Tuist's](https://github.com/asdf-community/asdf-tuist) в качестве примера.
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут установить его, выполнив `mise install`, они смогут запускать его либо напрямую, либо через `tuist xxx`.

> [!NOTE]
> **Будущее ProjectAutomation**
>
> Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единый обратно совместимый фреймворк, который предоставляет пользователю полный доступ к графу проекта. Кроме того, мы вынесем логику генерации в новый слой, `XcodeGraph`, который вы также сможете использовать из своего собственного CLI. Воспринимайте это как создание собственного Tuist.


## Использование плагинов {#using-plugins}

Чтобы использовать плагин, вам нужно добавить его в файл манифеста [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist) вашего проекта:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Если вы хотите повторно использовать плагин в проектах, находящихся в разных репозиториях, вы можете отправить свой плагин в Git-репозиторий и сослаться на него в файле `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

После добавления плагинов команда `tuist install` загрузит их в глобальный каталог кэша.

> [!NOTE]
> **Отсутствие разрешения версий**
>
> Как вы могли заметить, мы не предоставляем разрешение версий для плагинов. Мы рекомендуем использовать Git-теги или SHA-хеши для обеспечения воспроизводимости.


> [!TIP]
> **Плагины хелперов описания проекта**
>
> При использовании плагина хелперов описания проекта имя модуля, содержащего хелперы, совпадает с именем плагина
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
