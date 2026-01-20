---
{
  "title": "Generated project with the XcodeProj-based package integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a generated Xcode project with the XcodeProj-based package integration."
}
---
# Сгенерированный проект с интеграцией пакетов на основе XcodeProj {#generated-project-with-xcodeproj-based-integration}

При использовании интеграции на основе
<LocalizedLink href="/guides/features/projects/dependencies#tuists-xcodeprojbased-integration">XcodeProj</LocalizedLink>
вы можете использовать флаг ``--replace-scm-with-registry`` для разрешения
зависимостей из реестра, если они доступны. Добавьте его в `installOptions` в
ваш файл `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    project: .tuist(
        installOptions: .options(passthroughSwiftPackageManagerArguments: ["--replace-scm-with-registry"])
    )
)
```

Если вы хотите, чтобы реестр использовался каждый раз при разрешении
зависимостей, вам нужно обновить `зависимостей` в файле `Tuist/Package.swift`,
чтобы использовать идентификатор реестра вместо URL. Идентификатор реестра
всегда имеет вид `{organization}.{repository}`. Например, чтобы использовать
реестр для пакета `swift-composable-architecture`, сделайте следующее:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
