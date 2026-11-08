---
{
  "title": "Сгенерированный проект с интеграцией пакетов на основе XcodeProj",
  "titleTemplate": ":title · Swift · Package Registries · Features · Guides · Tuist",
  "description": "Используйте реестр Tuist с интеграцией пакетов на основе XcodeProj в сгенерированных проектах."
}
---
# Сгенерированный проект с интеграцией пакетов на основе XcodeProj {#generated-project-with-xcodeproj-based-integration}

При использовании <.localized_link href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">интеграции на основе XcodeProj</.localized_link> вы можете использовать флаг `--replace-scm-with-registry`, чтобы разрешать зависимости из реестра, если они доступны. Добавьте его в `installOptions` в вашем файле `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Если вы хотите гарантировать использование реестра при каждом разрешении зависимостей, вам нужно обновить `dependencies` в вашем файле `Tuist/Package.swift`, чтобы использовать идентификатор реестра вместо URL.

<!-- @snippet: ./_registry-identifier -->
