---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Манифесты {#manifests}

Tuist по умолчанию использует Swift файлы в качестве основного способа
определения проектов и рабочих пространств, а также настройки процесса
генерации. В документации эти файлы называются **манифест файлами**.

Решение использовать Swift было вдохновлено менеджером пакетов [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), который также
использует Swift файлы для описания пакетов. Благодаря использованию Swift мы
можем использовать компилятор для валидации содержимого и повторного
использования кода в различных манифест файлах, а также Xcode для предоставления
первоклассного опыта редактирования благодаря подсветке синтаксиса,
автодополнению и валидации.

::: info КЭШИРОВАНИЕ
<!-- -->
Поскольку манифест файлы представляют собой файлы Swift, которые необходимо
скомпилировать, Tuist кэширует результаты компиляции, чтобы ускорить процесс
анализа. Поэтому вы заметите, что при первом запуске Tuist генерация проекта
может занять немного больше времени. Последующие запуски будут быстрее.
<!-- -->
:::

## Project.swift {#projectswift}

Манифест
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
объявляет проект Xcode. Проект создается в той же директории, где находится
манифест файл, с именем, указанным в параметре `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: warning КОРНЕВЫЕ ПЕРЕМЕННЫЕ
<!-- -->
Единственная переменная, которая должна находиться в корне манифеста – это `let
project = Project(...)`. Если вам необходимо переиспользовать код в различных
частях манифеста, вы можете воспользоваться функциями Swift.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

По умолчанию Tuist генерирует [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
содержащий создаваемый проект и проекты его зависимостей. Если по какой-либо
причине вы хотите настроить рабочее пространство для добавления дополнительных
проектов или включения файлов и групп, вы можете сделать это, определив манифест
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>.

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

::: info
<!-- -->
Tuist создаст граф зависимостей и включит проекты зависимостей в рабочее
пространство. Вам не нужно добавлять их вручную. Это необходимо для того, чтобы
система сборки правильно разрешила зависимости.
<!-- -->
:::

### Мульти или монопроект {#multi-or-monoproject}

Часто возникает вопрос, следует ли использовать один или несколько проектов в
рабочем пространстве. В мире без Tuist, где настройка монопроекта приводит к
частым конфликтам Git, поэтому использование рабочих пространств приветствуется.
Однако, поскольку мы не рекомендуем включать проекты Xcode, созданные Tuist, в
репозиторий Git, конфликты Git не являются проблемой. Поэтому решение об
использовании одного или нескольких проектов в рабочем пространстве остается за
вами.

В проекте Tuist мы опираемся на монопроекты, поскольку время холодной генерации
меньше (компилируется меньше манифест файлов), и мы используем
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> как единицу инкапсуляции. Однако, вы можете использовать
проекты Xcode в качестве единицы инкапсуляции для представления различных
доменов вашего приложения, что более точно соответствует рекомендуемой структуре
проекта Xcode.

## Tuist.swift {#tuistswift}

Tuist предоставляет
<LocalizedLink href="/contributors/principles.html#default-to-conventions">целесообразные значения по умолчанию</LocalizedLink> для упрощения конфигурации проекта.
Однако, вы можете настроить конфигурацию, определив
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
в корне проекта, который будет использоваться Tuist для определения корня
проекта.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
