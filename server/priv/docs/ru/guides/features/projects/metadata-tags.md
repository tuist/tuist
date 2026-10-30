---
{
  "title": "Метаданные тегов",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать метаданные тегов целей для организации и фокусировки на конкретных частях вашего проекта"
}
---
# Метаданные тегов {#metadata-tags}

По мере роста размера и сложности проектов работа со всей кодовой базой сразу может стать неэффективной. Tuist предоставляет **метаданные теги** как способ организации целей в логические группы и фокусировки на конкретных частях вашего проекта во время разработки.

## Что такое метаданные теги? {#what-are-metadata-tags}

Метаданные теги — это строковые метки, которые вы можете прикреплять к целям в вашем проекте. Они служат маркерами, позволяющими вам:

- **Группировать связанные цели** — помечайте цели, относящиеся к одной функции, команде или архитектурному слою
- **Фокусировать рабочее пространство** — генерируйте проекты, включающие только цели с определенными тегами
- **Оптимизировать рабочий процесс** — работайте над конкретными функциями без загрузки несвязанных частей вашей кодовой базы
- **Выбирать цели для сохранения в виде исходного кода** — выбирайте, какую группу целей вы хотите сохранить как исходный код при кэшировании

Теги определяются с помощью свойства `metadata` у целей и хранятся в виде массива строк.

## Определение метаданных тегов {#defining-metadata-tags}

Вы можете добавить теги к любой цели в манифесте вашего проекта:

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

## Фокусировка на целях с тегами {#focusing-on-tagged-targets}

После того как вы пометили свои цели, вы можете использовать команду `tuist generate`, чтобы создать сфокусированный проект, включающий только определенные цели:

### Фокусировка по тегу

Используйте префикс `tag:`, чтобы сгенерировать проект со всеми целями, соответствующими определенному тегу:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Фокусировка по имени

Вы также можете сфокусироваться на конкретных целях по имени:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Как работает фокусировка

Когда вы фокусируетесь на целях:

1. **Включенные цели** — цели, соответствующие вашему запросу, включаются в сгенерированный проект
2. **Зависимости** — все зависимости сфокусированных целей автоматически включаются
3. **Цели тестирования** — цели тестирования для сфокусированных целей включаются
4. **Исключение** — все остальные цели исключаются из рабочего пространства

Это означает, что вы получаете меньшее, более управляемое рабочее пространство, содержащее только то, что нужно для работы над вашей функцией.

## Соглашения об именах тегов {#tag-naming-conventions}

Хотя вы можете использовать любую строку в качестве тега, соблюдение последовательного соглашения об именах помогает держать ваши теги организованными:

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

Использование префиксов, таких как `feature:`, `team:` или `layer:`, упрощает понимание назначения каждого тега и избегание конфликтов имен.

## Системные теги {#system-tags}

Tuist использует префикс `tuist:` для системных тегов. Эти теги автоматически применяются Tuist и могут использоваться в профилях кэша для targeting определенных типов сгенерированного контента.

### Доступные системные теги

| Тег | Описание |
| --- | --- |
| `tuist:synthesized` | Применяется к синтезированным целям bundle, которые Tuist создает для обработки ресурсов в статических библиотеках и статических фреймворках. Эти bundle существуют по историческим причинам для предоставления API доступа к ресурсам. |

### Использование системных тегов с профилями кэша

Вы можете использовать системные теги в профилях кэша, чтобы включать или исключать синтезированные цели:

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

> [!TIP]
> **Синтезированные Bundle наследуют теги родителя**
>
> Синтезированные цели bundle наследуют все теги от своей родительской цели в дополнение к получению тега `tuist:synthesized`. Это означает, что если вы пометите статическую библиотеку тегом `feature:auth`, её синтезированный resource bundle будет иметь оба тега: `feature:auth` и `tuist:synthesized`.


## Использование тегов с помощниками описания проекта {#using-tags-with-helpers}

Вы можете использовать <.localized_link href="/guides/features/projects/code-sharing">помощники описания проекта</.localized_link>, чтобы стандартизировать применение тегов во всем вашем проекте:

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

Затем используйте его в ваших манифестах:

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

## Преимущества использования метаданных тегов {#benefits}

### Улучшение процесса разработки

Фокусируясь на конкретных частях вашего проекта, вы можете:

- **Уменьшить размер проекта Xcode** — работать с меньшими проектами, которые быстрее открываются и проще в навигации
- **Ускорить сборки** — собирать только то, что нужно для текущей работы
- **Повысить концентрацию** — избегать отвлечения на несвязанный код
- **Оптимизировать индексацию** — Xcode индексирует меньше кода, что ускоряет автодополнение

### Лучшая организация проекта

Теги предоставляют гибкий способ организации вашей кодовой базы:

- **Множество измерений** — помечайте цели по функционалу, команде, слою, платформе или любому другому признаку
- **Без структурных изменений** — добавляйте организационную структуру без изменения расположения директорий
- **Сквозные аспекты** — одна цель может принадлежать нескольким логическим группам

### Интеграция с кэшированием

Метаданные тегов无缝 работают с <.localized_link href="/guides/features/cache">возможностями кэширования Tuist</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Рекомендации {#best-practices}

1. **Начните с простого** — начните с одного измерения тегирования (например, функционал) и расширяйте по мере необходимости
2. **Будьте последовательны** — используйте одни и те же соглашения об именах во всех ваших манифестах
3. **Документируйте ваши теги** — ведите список доступных тегов и их значений в документации вашего проекта
4. **Используйте помощники** — применяйте помощники описания проекта для стандартизации применения тегов
5. **Периодически пересматривайте** — по мере развития вашего проекта пересматривайте и обновляйте стратегию тегирования

## Связанные возможности {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">Общий код</.localized_link> — используйте помощники описания проекта для стандартизации использования тегов
- <.localized_link href="/guides/features/cache">Кэш</.localized_link> — комбинируйте теги с кэшированием для оптимальной производительности сборки
- <.localized_link href="/guides/features/selective-testing">Выборочное тестирование</.localized_link> — запускайте тесты только для измененных целей
