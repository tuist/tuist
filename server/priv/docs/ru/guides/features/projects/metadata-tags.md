---
{
  "title": "Метки метаданных",
  "titleTemplate": ":title · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать метки метаданных целей для организации и фокусировки на конкретных частях вашего проекта"
}
---
# Метки метаданных {#metadata-tags}

По мере роста размера и сложности проектов работа со всей кодовой базой сразу может стать неэффективной. Tuist предоставляет **метки метаданных** как способ организации таргетов в логические группы и фокусировки на конкретных частях вашего проекта во время разработки.

## Что такое метки метаданных? {#what-are-metadata-tags}

Метки метаданных — это строковые ярлыки, которые можно прикреплять к таргетам в вашем проекте. Они служат маркерами, позволяющими:

- **Группировать связанные таргеты** — помечайте таргеты, относящиеся к одной функции, команде или архитектурному слою
- **Фокусировать рабочее пространство** — генерируйте проекты, включающие только таргеты с определёнными метками
- **Оптимизировать рабочий процесс** — работайте над конкретными функциями без загрузки несвязанных частей кодовой базы
- **Выбирать таргеты для хранения в виде исходного кода** — выбирайте, какую группу таргетов вы хотите хранить в виде исходного кода при кэшировании

Метки определяются с помощью свойства `metadata` у таргетов и хранятся в виде массива строк.

## Определение меток метаданных {#defining-metadata-tags}

Вы можете добавить метки к любому таргету в манифесте вашего проекта:

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

## Фокусировка на помеченных таргетах {#focusing-on-tagged-targets}

После того как вы пометили свои таргеты, вы можете использовать команду `tuist generate`, чтобы создать сфокусированный проект, включающий только определённые таргеты:

### Фокусировка по метке

Используйте префикс `tag:`, чтобы сгенерировать проект со всеми таргетами, соответствующими определённой метке:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Фокусировка по имени

Вы также можете сфокусироваться на конкретных таргетах по имени:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Как работает фокусировка

При фокусировке на таргетах:

1. **Включённые таргеты** — таргеты, соответствующие вашему запросу, включаются в сгенерированный проект
2. **Зависимости** — все зависимости сфокусированных таргетов автоматически включаются
3. **Тестовые таргеты** — тестовые таргеты для сфокусированных таргетов включаются
4. **Исключение** — все остальные таргеты исключаются из рабочего пространства

Это означает, что вы получаете меньшее, более управляемое рабочее пространство, содержащее только то, что нужно для работы над вашей функцией.

## Соглашения об именах меток {#tag-naming-conventions}

Хотя вы можете использовать любую строку в качестве метки, следование единому соглашению об именах помогает поддерживать порядок в ваших метках:

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

Использование префиксов, таких как `feature:`, `team:` или `layer:`, упрощает понимание назначения каждой метки и избегание конфликтов имён.

## Системные метки {#system-tags}

Tuist использует префикс `tuist:` для системных меток. Эти метки автоматически применяются Tuist и могут использоваться в профилях кэша для выбора определённых типов сгенерированного контента.

### Доступные системные метки

| Метка | Описание |
| --- | --- |
| `tuist:synthesized` | Применяется к синтезированным таргетам пакетов, которые Tuist создаёт для обработки ресурсов в статических библиотеках и статических фреймворках. Эти пакеты существуют по историческим причинам для предоставления API доступа к ресурсам. |

### Использование системных меток с профилями кэша

Вы можете использовать системные метки в профилях кэша, чтобы включать или исключать синтезированные таргеты:

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
> **Синтезированные пакеты наследуют метки родительского таргета**
>
> Синтезированные таргеты пакетов наследуют все метки от своего родительского таргета в дополнение к получению метки `tuist:synthesized`. Это означает, что если вы пометите статическую библиотеку меткой `feature:auth`, её синтезированный пакет ресурсов будет иметь обе метки: `feature:auth` и `tuist:synthesized`.


## Использование меток с хелперами описания проекта {#using-tags-with-helpers}

Вы можете использовать <.localized_link href="/guides/features/projects/code-sharing">хелперы описания проекта</.localized_link>, чтобы стандартизировать применение меток в вашем проекте:

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

Затем используйте их в ваших манифестах:

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

### Улучшенный опыт разработки

Фокусируясь на конкретных частях вашего проекта, вы можете:

- **Уменьшить размер проекта Xcode** — работать с меньшими проектами, которые быстрее открываются и проще в навигации
- **Ускорить сборки** — собирать только то, что нужно для текущей работы
- **Повысить концентрацию** — избегать отвлечения на несвязанный код
- **Оптимизировать индексацию** — Xcode индексирует меньше кода, что ускоряет автодополнение

### Лучшая организация проекта

Метки предоставляют гибкий способ организации вашей кодовой базы:

- **Несколько измерений** — помечайте таргеты по функции, команде, слою, платформе или любому другому измерению
- **Без структурных изменений** — добавляйте организационную структуру без изменения расположения директорий
- **Сквозные задачи** — один таргет может принадлежать нескольким логическим группам

### Интеграция с кэшированием

Метаданные-метки бесшовно работают с <.localized_link href="/guides/features/cache">возможностями кэширования Tuist</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Рекомендации {#best-practices}

1. **Начните с простого** — начните с одного измерения тегирования (например, функции) и расширяйте по мере необходимости
2. **Будьте последовательны** — используйте одни и те же соглашения об именах во всех ваших манифестах
3. **Документируйте ваши метки** — ведите список доступных меток и их значений в документации вашего проекта
4. **Используйте хелперы** — применяйте хелперы описания проекта для стандартизации применения меток
5. **Периодически пересматривайте** — по мере развития проекта пересматривайте и обновляйте вашу стратегию тегирования

## Связанные возможности {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">Общий код</.localized_link> — используйте хелперы описания проекта для стандартизации использования меток
- <.localized_link href="/guides/features/cache">Кэш</.localized_link> — комбинируйте метки с кэшированием для оптимальной производительности сборки
- <.localized_link href="/guides/features/selective-testing">Выборочное тестирование</.localized_link> — запускайте тесты только для изменённых таргетов
