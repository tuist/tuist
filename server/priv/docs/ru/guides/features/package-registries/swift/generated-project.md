---
{
  "title": "Сгенерированный проект с интеграцией пакетов Xcode",
  "titleTemplate": ":title · Swift · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать реестр Tuist в сгенерированном проекте Xcode с интеграцией пакетов Xcode."
}
---
# Сгенерированный проект с интеграцией пакетов Xcode {#generated-project-with-xcode-based-integration}

Если вы используете <.localized_link href="/guides/features/projects/dependencies#xcodes-default-integration">стандартную интеграцию Xcode</.localized_link> пакетов с проектами Tuist, при добавлении пакета нужно использовать идентификатор реестра вместо URL-адреса:
```swift
import ProjectDescription

let project = Project(
    name: "MyProject",
    packages: [
        // Source control resolution
        // .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0")
        // Registry resolution
        .package(id: "pointfreeco.swift-composable-architecture", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
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
> Не обязательно добавлять каждый пакет по его идентификатору в реестре. Запуск `tuist registry setup` после генерации проекта также настраивает Xcode на разрешение пакетов, объявленных с URL-адресом системы контроля версий, из реестра, чего `registryEnabled` само по себе не делает. См. <.localized_link href="/guides/features/package-registries/swift/xcode-project#resolving-source-control-packages">Разрешение пакетов из системы контроля версий</.localized_link>.
