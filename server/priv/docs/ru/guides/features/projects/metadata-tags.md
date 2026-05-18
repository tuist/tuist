---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Теги метаданных {#metadata-tags}

По мере роста размера и сложности проектов работа со всей кодовой базой сразу
может стать неэффективной. Tuist предоставляет теги метаданных **** как способ
организовать цели в логические группы и сосредоточиться на определенных частях
проекта во время разработки.

## Что такое теги метаданных? {#what-are-metadata-tags}

Теги метаданных - это строковые метки, которые вы можете прикрепить к целям в
вашем проекте. Они служат в качестве маркеров, которые позволяют вам:

- **Группировать связанные цели** - пометить цели, принадлежащие к одной и той
  же функции, команде или архитектурному слою.
- **Фокусировка рабочего пространства** - генерируйте проекты, включающие только
  цели с определенными тегами.
- **Оптимизируйте рабочий процесс** - работайте над конкретными функциями, не
  загружая несвязанные части кодовой базы.
- **Выбрать цели для сохранения в качестве источников** - Выберите группу целей,
  которые вы хотите сохранить в качестве источников при кэшировании.

Теги определяются с помощью свойства `metadata` для целей и хранятся в виде
массива строк.

## Определение тегов метаданных {#defining-metadata-tags}

Вы можете добавить теги к любой цели в манифесте проекта:

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

## Фокусировка на отмеченных целях {#focusing-on-tagged-targets}

После маркировки целей можно использовать команду `tuist generate` для создания
сфокусированного проекта, включающего только определенные цели:

### Фокусировка по тегам

Используйте префикс `tag:`, чтобы создать проект со всеми целями,
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

Когда вы сосредотачиваетесь на цели:

1. **Включенные цели** - Цели, соответствующие вашему запросу, включены в
   сгенерированный проект.
2. **Зависимости** - автоматически включаются все зависимости от целей, на
   которые направлено внимание.
3. **Тестовые мишени** - включены тестовые мишени для сфокусированных целей.
4. **Исключение** - все остальные цели исключаются из рабочей области.

Это означает, что вы получаете более компактное и управляемое рабочее
пространство, содержащее только то, что вам нужно для работы над вашей функцией.

## Соглашения об именовании тегов {#tag-naming-conventions}

Хотя вы можете использовать любую строку в качестве тега, соблюдение
последовательного соглашения об именовании помогает сохранить упорядоченность
тегов:

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

Использование таких префиксов, как `feature:`, `team:`, или `layer:`, облегчает
понимание назначения каждого тега и позволяет избежать конфликтов при
именовании.

## Использование тегов с помощниками для описания проектов {#using-tags-with-helpers}

Вы можете использовать
<LocalizedLink href="/guides/features/projects/code-sharing">помощники описания проекта</LocalizedLink>, чтобы стандартизировать применение тегов в вашем
проекте:

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

Сосредоточившись на конкретных частях проекта, вы сможете:

- **Уменьшите размер проекта Xcode** - работайте с небольшими проектами, которые
  быстрее открывать и перемещаться по ним.
- **Ускорьте сборку** - создавайте только то, что нужно для текущей работы.
- **Улучшите концентрацию** - не отвлекайтесь на несвязанный код.
- **Оптимизация индексации** - Xcode индексирует меньше кода, что ускоряет
  автозаполнение.

### Лучшая организация проекта

Теги обеспечивают гибкий способ организации кодовой базы:

- **Множество измерений** - отмечайте цели по функциям, командам, слоям,
  платформам или любым другим измерениям.
- **Без структурных изменений** - Добавьте организационную структуру без
  изменения макета каталога
- **Сквозные проблемы** - Одна цель может относиться к нескольким логическим
  группам.

### Интеграция с кэшированием

Теги метаданных легко сочетаются с функциями кэширования
<LocalizedLink href="/guides/features/cache">Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Лучшие практики {#best-practices}

1. **Начните с простого** - начните с одного измерения маркировки (например,
   особенности) и расширяйте его по мере необходимости.
2. **Будьте последовательны** - Используйте одинаковые соглашения об именовании
   во всех ваших манифестах.
3. **Документируйте свои теги** - Сохраняйте список доступных тегов и их
   значения в документации вашего проекта.
4. **Используйте помощники** - Используйте помощники для описания проекта, чтобы
   стандартизировать применение тегов.
5. **Периодически просматривайте** - По мере развития проекта пересматривайте и
   обновляйте стратегию маркировки.

## Сопутствующие функции {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Совместное использование кода</LocalizedLink> - Используйте помощники для описания
  проектов, чтобы стандартизировать использование тегов
- <LocalizedLink href="/guides/features/cache">Кэш</LocalizedLink> - Объедините
  теги с кэшированием для оптимальной производительности сборки
- <LocalizedLink href="/guides/features/selective-testing">Выборочное тестирование</LocalizedLink> - Выполняйте тесты только для измененных целей
