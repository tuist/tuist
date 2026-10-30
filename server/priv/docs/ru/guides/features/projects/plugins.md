---
{
  "title": "Плагины",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как создавать и использовать плагины в Tuist для расширения его функциональности."
}
---
# Плагины {#plugins}

Плагины — это инструмент для обмена и повторного использования артефактов Tuist в нескольких проектах. Поддерживаются следующие артефакты:

- <.localized_link href="/guides/features/projects/code-sharing">Вспомогательные средства описания проекта</.localized_link> для использования в нескольких проектах.
- <.localized_link href="/guides/features/projects/templates">Шаблоны</.localized_link> для использования в нескольких проектах.
- Задачи для нескольких проектов.
- <.localized_link href="/guides/features/projects/synthesized-files">Шаблон доступа к ресурсам</.localized_link> для использования в нескольких проектах

Обратите внимание, что плагины созданы как простой способ расширения функциональности Tuist. Поэтому есть **некоторые ограничения, которые следует учитывать**:

- Плагин не может зависеть от другого плагина.
- Плагин не может зависеть от сторонних Swift-пакетов
- Плагин не может использовать вспомогательные функции описания проекта из проекта, который использует этот плагин.

Если вам нужна большая гибкость, рассмотрите предложение новой функции для инструмента или создание собственного решения на основе фреймворка генерации Tuist, [`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Типы плагинов {#plugin-types}

### Плагин с вспомогательными функциями описания проекта {#project-description-helper-plugin}

Плагин с вспомогательными функциями описания проекта представляет собой каталог, содержащий манифест-файл `Plugin.swift`, в котором объявляется имя плагина, и каталог `ProjectDescriptionHelpers`, содержащий вспомогательные Swift-файлы.

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

### Плагин с шаблонами аксессоров ресурсов {#resource-accessor-templates-plugin}

Если вам нужно распространять <.localized_link href="/guides/features/projects/synthesized-files#resource-accessors">сгенерированные средства доступа к ресурсам</.localized_link>, вы можете использовать этот тип плагинов. Плагин представляет собой каталог, содержащий файл манифеста `Plugin.swift`, в котором объявляется имя плагина, и каталог `ResourceSynthesizers`, содержащий файлы шаблонов средств доступа к ресурсам.


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
> Плагины задач устарели. Ознакомьтесь с [этой статьей в блоге](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), если вы ищете решение для автоматизации вашего проекта.


Задачи — это исполняемые файлы, доступные через переменную окружения `$PATH`, которые можно вызывать с помощью команды `tuist`, если они следуют соглашению об именах `tuist-<task-name>`. В ранних версиях Tuist предоставлял некоторые базовые соглашения и инструменты в рамках `tuist plugin` для `build`, `run`, `test` и `archive` задач, представленных исполняемыми файлами в Swift-пакетах, но мы отказались от этой функции, так как она увеличивает нагрузку на поддержку и сложность инструмента.

Если вы использовали Tuist для распространения задач, мы рекомендуем создать собственное
- Вы можете продолжать использовать `ProjectAutomation.xcframework`, поставляемый с каждым релизом Tuist, чтобы получать доступ к графу проекта из вашей логики с помощью `let graph = try Tuist.graph()`. Команда использует системный процесс для запуска команды `tuist` и возвращает представление графа проекта в памяти.
- Для распространения задач мы рекомендуем включать универсальный бинарный файл, поддерживающий архитектуры `arm64` и `x86_64`, в релизы на GitHub и использовать [Mise](https://mise.jdx.dev) в качестве инструмента установки. Чтобы указать Mise, как устанавливать ваш инструмент, вам понадобится репозиторий плагинов. Вы можете использовать [репозиторий Tuist](https://github.com/asdf-community/asdf-tuist) в качестве примера.
- Если вы назовете свой инструмент `tuist-{xxx}` и пользователи смогут установить его, выполнив команду `mise install`, они смогут запускать его либо напрямую, либо через `tuist xxx`.

> [!NOTE]
> **Будущее ProjectAutomation**
>
> Мы планируем объединить модели `ProjectAutomation` и `XcodeGraph` в единый обратно совместимый фреймворк, который предоставит пользователю полный доступ к графу проекта. Кроме того, мы выделим логику генерации в новый слой `XcodeGraph`, который вы также сможете использовать из своего собственного CLI. Рассматривайте это как возможность создать свой собственный Tuist.


## Использование плагинов {#using-plugins}

Чтобы использовать плагин, вам нужно добавить его в манифест-файл вашего проекта [`Tuist.swift`](https://projectdescription.tuist.dev/documentation/projectdescription/tuist):

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Если вы хотите повторно использовать плагин в проектах, находящихся в разных репозиториях, вы можете отправить его в Git-репозиторий и сослаться на него в файле `Tuist.swift`:

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
> Как вы могли заметить, мы не предоставляем разрешение версий для плагинов. Мы рекомендуем использовать Git-теги или SHA-хэши для обеспечения воспроизводимости.


> [!TIP]
> **Плагины с вспомогательными функциями описания проекта**
>
> При использовании плагина с вспомогательными функциями описания проекта имя модуля, содержащего эти функции, совпадает с именем плагина
> ```swift
> import ProjectDescription
> import MyTuistPlugin
> let project = Project.app(name: "MyCoolApp", platform: .iOS)
> ```
