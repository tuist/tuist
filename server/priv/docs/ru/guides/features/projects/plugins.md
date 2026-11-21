---
{
  "title": "Плагины",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать плагины в Tuist для расширения его функциональности."
}
---
# Плагины {#plugins}

Плагины — это инструмент для совместного использования и повторного применения артефактов Tuist в нескольких проектах. Поддерживаются следующие артефакты:

- <.localized_link href="/guides/features/projects/code-sharing">Вспомогательные средства описания проекта</.localized_link> в нескольких проектах.
- <.localized_link href="/guides/features/projects/templates">Шаблоны</.localized_link> в нескольких проектах.
- Задачи в нескольких проектах.
- Шаблон <.localized_link href="/guides/features/projects/synthesized-files">доступа к ресурсам</.localized_link> в нескольких проектах

Обратите внимание, что плагины разработаны как простой способ расширения функциональности Tuist. Поэтому есть **некоторые ограничения, которые следует учитывать**:

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних пакетов Swift
- Плагин не может использовать вспомогательные средства описания проекта из проекта, который использует этот плагин.

Если вам нужна большая гибкость, рассмотрите предложение новой функции для инструмента или создание собственного решения на основе фреймворка генерации Tuist, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/cli/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Плагин вспомогательных средств описания проекта {#project-description-helper-plugin}

Плагин вспомогательных средств описания проекта представлен каталогом, содержащим файл манифеста `Plugin.swift`, который объявляет имя плагина, и каталог `ProjectDescriptionHelpers`, содержащий вспомогательные файлы Swift.

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

Если вам нужно совместно использовать <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">синтезированные средства доступа к ресурсам</.localized_link>, вы можете использовать этот тип плагина. Плагин представлен каталогом, содержащим файл манифеста `Plugin.swift`, который объявляет имя плагина, и каталог `ResourceSynthesizers`, содержащий файлы шаблонов доступа к ресурсам.


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

Имя шаблона — это версия типа ресурса в [camel case](https://en.wikipedia.org/wiki/Camel_case):

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
> Плагины задач устарели. Если вы ищете решение для автоматизации вашего проекта, ознакомьтесь с [этой записью в блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).


Задачи — это исполняемые файлы, доступные через переменную `$PATH`, которые можно вызывать командой `tuist`, если они следуют соглашению об именах `tuist-<task-name>`. В ранних версиях Tuist предоставлял некоторые слабые соглашения и инструменты под `tuist plugin` для задач `build`, `run`, `test` и `archive`, представленных исполняемыми файлами в пакетах Swift, но мы отказались от этой функции, так как она увеличивает нагрузку на поддержку и сложность инструмента.

Если вы распространяли задачи как плагины, вместо этого собирайте их как автономные исполняемые файлы:

- Вы можете продолжать использовать `ProjectAutomation.xcframework`, поставляемый с каждым релизом Tuist, чтобы получить доступ к графу проекта из вашей логики с помощью `let graph = try Tuist.graph()`. Он запускает `tuist` как подпроцесс и возвращает представление графа проекта в памяти.
- Для распространения задач мы рекомендуем публиковать универсальный бинарный файл, поддерживающий `arm64` и `x86_64`, в релизах GitHub, и использовать [Mise](https://mise.jdx.dev) в качестве инструмента установки. Чтобы указать Mise, как установить ваш инструмент, вам понадобится репозиторий плагина. Вы можете использовать [Tuist's](https://github.com/asdf-community/asdf-tuist) в качестве примера.
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут установить его, запустив `mise install`, они смогут запускать его либо напрямую, либо через `tuist xxx`.

> [!NOTE]
> **Будущее ProjectAutomation**
>
> Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единый обратно совместимый фреймворк, который предоставит пользователю полный доступ к графу проекта. Кроме того, мы выделим логику генерации в новый слой, `XcodeGraph`, который вы также сможете использовать из своего собственного CLI. Воспринимайте это как создание собственного Tuist.


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
> Как вы могли заметить, мы не предоставляем разрешение версий для плагинов. Мы рекомендуем использовать теги Git или SHA для обеспечения воспроизводимости.


> [!TIP]
> **Плагины вспомогательных средств описания проекта**
>
> При использовании плагина вспомогательных средств описания проекта имя модуля, содержащего эти средства, совпадает с именем плагина
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
