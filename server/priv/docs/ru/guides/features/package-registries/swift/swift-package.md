---
{
  "title": "Пакет Swift",
  "titleTemplate": ":title · Swift · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать реестр Tuist в пакете Swift."
}
---
# Пакет Swift {#swift-package}

Если вы работаете с пакетом Swift, вы можете использовать флаг `--replace-scm-with-registry`, чтобы разрешать зависимости из реестра, если они доступны:

```bash
swift package --replace-scm-with-registry resolve
```

Если вы хотите убедиться, что реестр используется каждый раз при разрешении зависимостей, вам нужно обновить `dependencies` в файле `Package.swift`, указав идентификатор реестра вместо URL. Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например, чтобы использовать реестр для пакета `swift-composable-architecture`, выполните следующие действия:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
