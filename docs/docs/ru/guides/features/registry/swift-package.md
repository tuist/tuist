---
{
  "title": "Swift package",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in a Swift package."
}
---
# Пакет Swift {#swift-package}

Если вы работаете над пакетом Swift, вы можете использовать флаг
`--replace-scm-with-registry` для разрешения зависимостей из реестра, если они
доступны:

```bash
swift package --replace-scm-with-registry resolve
```

Если вы хотите, чтобы реестр использовался при каждом разрешении зависимостей,
вам нужно обновить раздел `dependencies`в файле `Package.swift`, указав
идентификатор реестра вместо URL. Идентификатор реестра всегда имеет формат
`{organization}.{repository}`. Например, чтобы использовать реестр для пакета
`swift-composable-architecture`, выполните следующие шаги:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
