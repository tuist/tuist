---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Пакеты Swift {#swift-packages}

Если вы работаете над пакетом Swift, вы можете использовать флаг
`--replace-scm-with-registry` для разрешения зависимостей из реестра, если они
доступны:

```bash
swift package --replace-scm-with-registry resolve
```

Если вы хотите, чтобы реестр использовался каждый раз при разрешении
зависимостей, вам нужно обновить `зависимостей` в файле `Package.swift`, чтобы
использовать идентификатор реестра вместо URL. Идентификатор реестра всегда
имеет вид `{organization}.{repository}`. Например, чтобы использовать реестр для
пакета `swift-composable-architecture`, сделайте следующее:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
