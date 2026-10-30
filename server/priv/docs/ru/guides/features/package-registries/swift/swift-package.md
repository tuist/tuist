---
{
  "title": "Swift-пакет",
  "titleTemplate": ":title · Swift · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать реестр Tuist в Swift-пакете."
}
---
# Пакет Swift {#swift-package}

Если вы работаете с пакетом Swift, можете использовать флаг `--replace-scm-with-registry`, чтобы разрешать зависимости из реестра, если они доступны:

```bash
swift package --replace-scm-with-registry resolve
```

Чтобы гарантировать использование реестра при каждом разрешении зависимостей, обновите `dependencies` в файле `Package.swift`, заменив URL на идентификатор реестра. Идентификатор реестра всегда имеет вид `{organization}.{repository}`. Например, чтобы использовать реестр для пакета `swift-composable-architecture`, выполните следующие действия:
```diff
dependencies: [
-   .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "0.1.0")
+   .package(id: "pointfreeco.swift-composable-architecture", from: "0.1.0")
]
```
