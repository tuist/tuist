---
{
  "title": "Теги метаданных",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать теги метаданных целей для организации и фокусировки на конкретных частях вашего проекта"
}
---
# Метки метаданных {#metadata-tags}

По мере роста размера и сложности проектов работа со всей кодовой базой сразу может стать неэффективной. Tuist предоставляет **метки метаданных** как способ организации целей в логические группы и фокусировки на конкретных частях вашего проекта во время разработки.

## Что такое метки метаданных? {#what-are-metadata-tags}

Метки метаданных — это строковые ярлыки, которые можно прикреплять к целям в вашем проекте. Они служат маркерами, позволяющими:

- **Группировать связанные цели** — помечайте цели, относящиеся к одной функции, команде или архитектурному слою
- **Фокусировать рабочее пространство** — генерировать проекты, включающие только цели с определёнными метками
- **Оптимизировать рабочий процесс** — работать над конкретными функциями без загрузки несвязанных частей кодовой базы
- **Выбирать цели для хранения в виде исходного кода** — выбирать, какую группу целей вы хотите хранить в виде исходного кода при кэшировании

Метки определяются с помощью свойства `metadata` у целей и хранятся в виде массива строк.

## Определение меток метаданных {#defining-metadata-tags}

Вы можете добавить метки к любой цели в манифесте вашего проекта:

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

## Фокусировка на целях с метками {#focusing-on-tagged-targets}

После того как вы пометили свои цели, вы можете использовать команду `tuist generate` для создания сфокусированного проекта, включающего только определённые цели:

### Фокусировка по метке

Используйте префикс `tag:`, чтобы сгенерировать проект со всеми целями, соответствующими определённой метке:

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

При фокусировке на целях:

1. **Включённые цели** — цели, соответствующие вашему запросу, включаются в сгенерированный проект
2. **Зависимости** — все зависимости сфокусированных целей автоматически включаются
3. **Цели тестов** — цели тестов для сфокусированных целей включаются
4. **Исключение** — все остальные цели исключаются из рабочего пространства

Это означает, что вы получаете меньшее и более удобное в управлении рабочее пространство, содержащее только то, что нужно для работы над вашей функцией.

## Соглашения об именовании меток {#tag-naming-conventions}

Хотя вы можете использовать любую строку в качестве метки, соблюдение единого соглашения об именовании помогает поддерживать порядок в ваших метках:

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

Использование префиксов, таких как `feature:`, `team:` или `layer:`, упрощает понимание назначения каждой метки и помогает избежать конфликтов имён.

## Системные метки {#system-tags}

Tuist использует префикс `tuist:` для системных меток. Эти метки автоматически применяются Tuist и могут использоваться в профилях кэша для выбора определённых типов сгенерированного контента.

### Доступные системные метки

| Метка | Описание |
| --- | --- |
| `tuist:synthesized` | Применяется к синтезированным целям bundle, которые Tuist создаёт для обработки ресурсов в статических библиотеках и статических фреймворках. Эти bundle существуют по историческим причинам для предоставления API доступа к ресурсам. |

### Использование системных меток с профилями кэша

Вы можете использовать системные метки в профилях кэша, чтобы включать или исключать синтезированные цели:

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
> **Синтезированные bundle наследуют родительские метки**
>
> Цели синтезированных bundle наследуют все метки от своей родительской цели в дополнение к получению метки `tuist:synthesized`. Это означает, что если вы пометите статическую библиотеку меткой `feature:auth`, её синтезированный resource bundle будет иметь обе метки: `feature:auth` и `tuist:synthesized`.


## Использование меток с помощниками описания проекта {#using-tags-with-helpers}

Вы можете использовать <.localized_link href="/guides/features/projects/code-sharing">помощники описания проекта</.localized_link>, чтобы стандартизировать применение меток во всём проекте:

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

Затем используйте их в своих манифестах:

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

## Преимущества использования метаданных-меток {#benefits}

### Улучшение опыта разработки

Фокусируясь на конкретных частях вашего проекта, вы можете:

- **Уменьшить размер проекта Xcode** — работать с меньшими проектами, которые быстрее открываются и легче навигировать
- **Ускорить сборки** — собирать только то, что нужно для текущей работы
- **Повысить концентрацию** — избегать отвлечения на несвязанный код
- **Оптимизировать индексацию** — Xcode индексирует меньше кода, что ускоряет автодополнение

### Лучшая организация проекта

Метки предоставляют гибкий способ организации вашей кодовой базы:

- **Несколько измерений** — помечайте цели по функции, команде, слою, платформе или любому другому измерению
- **Без структурных изменений** — добавляйте организационную структуру без изменения расположения директорий
- **Сквозные задачи** — одна цель может принадлежать нескольким логическим группам

### Интеграция с кэшированием

Метаданные-метки seamlessly работают с <.localized_link href="/guides/features/cache">возможностями кэширования Tuist</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Рекомендации {#best-practices}

1. **Начните с простого** — начните с одного измерения тегирования (например, функции) и расширяйте по мере необходимости
2. **Будьте последовательны** — используйте одни и те же соглашения об именовании во всех ваших манифестах
3. **Документируйте ваши метки** — ведите список доступных меток и их значений в документации вашего проекта
4. **Используйте помощники** — применяйте помощники описания проекта для стандартизации применения меток
5. **Периодически пересматривайте** — по мере развития вашего проекта пересматривайте и обновляйте стратегию тегирования

## Связанные возможности {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">Общий код</.localized_link> — используйте помощники описания проекта для стандартизации использования меток
- <.localized_link href="/guides/features/cache">Кэш</.localized_link> — комбинируйте метки с кэшированием для оптимальной производительности сборки
- <.localized_link href="/guides/features/selective-testing">Выборочное тестирование</.localized_link> — запускайте тесты только для изменённых целей
