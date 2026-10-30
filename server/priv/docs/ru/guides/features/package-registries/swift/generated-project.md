---
{
  "title": "Сгенерированный проект с интеграцией пакетов Xcode",
  "titleTemplate": ":title · Swift · Package Registries · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать реестр Tuist в сгенерированном проекте Xcode с интеграцией пакетов Xcode."
}
---
# Сгенерированный проект с интеграцией пакетов Xcode {#generated-project-with-xcode-based-integration}

Если вы используете <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">стандартную интеграцию Xcode</.localized_link> для работы с пакетами в проектах Tuist, при добавлении пакета нужно использовать идентификатор реестра вместо URL:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "App",
            product: .app,
            bundleId: "dev.tuist.App",
            dependencies: [
                .package(product: "ComposableArchitecture"),
            ]
        )
    ]
)
```

> [!TIP]
> Не обязательно указывать каждый пакет по его идентификатору в реестре. Запуск `tuist registry setup` после генерации проекта также настраивает Xcode на разрешение пакетов, объявленных через URL системы контроля версий, из реестра — этого не делает сам по себе `registryEnabled`. См. <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Разрешение пакетов из системы контроля версий</.localized_link>.
