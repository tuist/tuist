---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Манифесты {#manifests}

По умолчанию Tuist использует файлы Swift в качестве основного способа
определения проектов и рабочих пространств и настройки процесса генерации. В
документации эти файлы упоминаются как **manifest files**.

Решение использовать Swift было навеяно [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), который также
использует Swift-файлы для определения пакетов. Благодаря использованию Swift мы
можем использовать компилятор для проверки корректности содержимого и повторного
использования кода в разных файлах манифеста, а Xcode - для первоклассного
редактирования благодаря подсветке синтаксиса, автозавершению и валидации.

> [!ПРИМЕЧАНИЕ] CACHING Поскольку файлы манифестов - это файлы Swift, которые
> необходимо компилировать, Tuist кэширует результаты компиляции, чтобы ускорить
> процесс разбора. Поэтому при первом запуске Tuist может потребоваться немного
> больше времени для генерации проекта. Последующие запуски будут проходить
> быстрее.

## Project.swift {#projectswift}

Манифест
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
объявляет проект Xcode. Проект создается в том же каталоге, где находится файл
манифеста, с именем, указанным в свойстве `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


> [!WARNING] ПЕРЕМЕННЫЕ В КОРНЕ Единственная переменная, которая должна
> находиться в корне манифеста, - это `let project = Project(...)`. Если вам
> нужно повторно использовать код в разных частях манифеста, вы можете
> использовать функции Swift.

## Workspace.swift {#workspaceswift}

По умолчанию Tuist генерирует [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces),
содержащий генерируемый проект и проекты его зависимостей. Если по каким-либо
причинам вы хотите настроить рабочее пространство, добавив в него дополнительные
проекты или включив файлы и группы, вы можете сделать это, определив
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>
манифест.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

> [!ПРИМЕЧАНИЕ] Tuist разрешит граф зависимостей и включит проекты зависимостей
> в рабочее пространство. Вам не нужно включать их вручную. Это необходимо для
> того, чтобы система сборки правильно разрешила зависимости.

### Мульти- или монопроект {#multi-or-monoproject}

Часто возникает вопрос, использовать ли один проект или несколько проектов в
рабочем пространстве. В мире без Tuist, где монопроектная настройка привела бы к
частым Git-конфликтам, использование рабочих пространств приветствуется. Однако,
поскольку мы не рекомендуем включать проекты Xcode, сгенерированные Tuist, в
Git-репозиторий, конфликты Git не являются проблемой. Поэтому решение об
использовании одного проекта или нескольких проектов в рабочем пространстве
остается за вами.

В проекте Tuist мы опираемся на монопроекты, потому что время генерации холода
быстрее (меньше файлов манифеста для компиляции) и мы используем
<LocalizedLink href="/guides/features/projects/code-sharing">помощники описания
проекта</LocalizedLink> в качестве единицы инкапсуляции. Однако вы можете
захотеть использовать проекты Xcode в качестве единицы инкапсуляции для
представления различных доменов вашего приложения, что более соответствует
рекомендуемой структуре проектов Xcode.

## Tuist.swift {#tuistswift}

Tuist предоставляет
<LocalizedLink href="/contributors/principles.html#default-to-conventions">чувствительные
настройки по умолчанию</LocalizedLink>, чтобы упростить конфигурацию проекта.
Однако вы можете настроить конфигурацию, определив
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
в корне проекта, который используется Tuist для определения корня проекта.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
