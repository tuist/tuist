---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Теги метаданных {#metadata-tags}

По мере роста размера и сложности проектов работа со всей кодовой базой сразу
может стать неэффективной. Tuist предоставляет метаданные теги **** , которые
позволяют организовывать цели в логические группы и сосредоточиться на
конкретных частях вашего проекта во время разработки.

## Что такое теги метаданных? {#what-are-metadata-tags}

Теги метаданных — это строковые метки, которые можно прикреплять к целям в
проекте. Они служат в качестве маркеров, которые позволяют:

- **Группируйте связанные цели** - Помечайте цели, которые относятся к одной и
  той же функции, команде или архитектурному уровню
- **Сфокусируйте свое рабочее пространство** - Создавайте проекты, которые
  включают только цели с определенными тегами
- **Оптимизируйте свой рабочий процесс** - Работайте над конкретными функциями,
  не загружая не связанные с ними части кодовой базы
- **Выберите цели, которые необходимо сохранить в качестве источников** -
  Выберите группу целей, которые необходимо сохранить в качестве источников при
  кэшировании

Теги определяются с помощью свойства метаданных `` на целях и хранятся в виде
массива строк.

## Определение тегов метаданных {#defining-metadata-tags}

Вы можете добавлять теги к любому объекту в манифесте вашего проекта:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## Сосредоточьтесь на помеченных целях {#focusing-on-tagged-targets}

После того, как вы пометили свои цели, вы можете использовать команду `tuist
generate` для создания сфокусированного проекта, который включает только
определенные цели:

### Фокус по тегу

Используйте тег `:` prefix для создания проекта со всеми целями,
соответствующими определенному тегу:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Фокус по имени

Вы также можете сосредоточиться на конкретных целях по имени:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Как работает фокус

Когда вы сосредотачиваетесь на целях:

1. **Включенные цели** - Цели, соответствующие вашему запросу, включены в
   сгенерированный проект.
2. **Зависимости** - Все зависимости целей, на которых сосредоточено внимание,
   включаются автоматически.
3. **Цели тестирования** - Цели тестирования для целей, на которых сосредоточено
   внимание, включены
4. **Исключение** - Все остальные цели исключаются из рабочей области.

Это означает, что вы получаете более компактное и удобное рабочее пространство,
содержащее только то, что вам нужно для работы над вашей функцией.

## Соглашения об именовании тегов {#tag-naming-conventions}

Хотя в качестве тега можно использовать любую строку, соблюдение единых правил
именования поможет вам организовать теги:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

Использование префиксов, таких как `feature:`, `team:` или `layer:`, облегчает
понимание назначения каждого тега и позволяет избежать конфликтов имен.

## Системные теги {#system-tags}

Tuist использует префикс `tuist:` для тегов, управляемых системой. Эти теги
автоматически применяются Tuist и могут использоваться в профилях кэша для
таргетинга на определенные типы генерируемого контента.

### Доступные системные теги

| Теги                | Описание                                                                                                                                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `tuist:synthesized` | Применяется к синтезированным целевым пакетам, которые Tuist создает для обработки ресурсов в статических библиотеках и статических фреймворках. Эти пакеты существуют по историческим причинам, чтобы предоставлять API для доступа к ресурсам. |

### Использование системных тегов с профилями кэша

Вы можете использовать системные теги в профилях кэша, чтобы включить или
исключить синтезированные цели:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
Синтезированные пакеты целей наследуют все теги от родительской цели в
дополнение к получению тега `tuist:synthesized`. Это означает, что если вы
помечаете статическую библиотеку тегом `feature:auth`, ее синтезированный пакет
ресурсов будет иметь теги `feature:auth` и `tuist:synthesized`.
<!-- -->
:::

## Использование тегов с помощниками описания проекта {#using-tags-with-helpers}

Вы можете использовать
<LocalizedLink href="/guides/features/projects/code-sharing">помощники по
описанию проекта</LocalizedLink>, чтобы стандартизировать применение тегов в
вашем проекте:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

Затем используйте его в своих манифестах:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## Преимущества использования тегов метаданных {#benefits}

### Улучшенный опыт разработки

Сосредоточившись на конкретных частях вашего проекта, вы можете:

- **Уменьшите размер проекта Xcode** - Работайте с меньшими по размеру
  проектами, которые быстрее открываются и в которых проще ориентироваться.
- **Ускорьте сборку** - Собирайте только то, что необходимо для текущей работы
- **Улучшите фокус** - Избегайте отвлекающих факторов, не связанных с кодом
- **Оптимизируйте индексирование** - Xcode индексирует меньше кода, что ускоряет
  автозаполнение

### Лучшая организация проекта

Теги предоставляют гибкий способ организации вашей кодовой базы:

- **Многомерность** - Помечайте цели по функциям, командам, слоям, платформам
  или любым другим параметрам.
- **Без структурных изменений** - Добавьте организационную структуру, не изменяя
  структуру каталогов
- **Пересекающиеся проблемы** - Одна цель может принадлежать нескольким
  логическим группам

### Интеграция с кэшированием

Теги метаданных беспрепятственно работают с
<LocalizedLink href="/guides/features/cache">функциями кэширования
Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Лучшие практики {#best-practices}

1. **Начните с простого** - Начните с одного измерения тегирования (например,
   функции) и расширяйте его по мере необходимости.
2. **Будьте последовательны** - Используйте одинаковые соглашения об именовании
   во всех ваших манифестах
3. **Документируйте свои теги** - Ведите список доступных тегов и их значений в
   документации вашего проекта
4. **Используйте помощники** - Используйте помощники по описанию проекта для
   стандартизации применения тегов
5. **Периодически пересматривайте** - По мере развития вашего проекта
   пересматривайте и обновляйте свою стратегию тегирования.

## Связанные функции {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Совместное
  использование кода</LocalizedLink> - Используйте помощники по описанию проекта
  для стандартизации использования тегов
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> -
  Объединяйте теги с кэшированием для оптимальной производительности сборки
- <LocalizedLink href="/guides/features/selective-testing">Выборочное
  тестирование</LocalizedLink> - Запускайте тесты только для измененных целей.
