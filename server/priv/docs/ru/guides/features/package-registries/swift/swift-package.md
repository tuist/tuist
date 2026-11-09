---
{
  "title": "Swift-пакет",
  "titleTemplate": ":title · Swift · Реестры пакетов · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать реестр Tuist в Swift-пакете."
}
---
# Swift-пакет {#swift-package}

Если вы работаете над Swift-пакетом, вы можете использовать флаг `--replace-scm-with-registry`, чтобы разрешать зависимости из реестра, если они доступны:

```bash
swift package --replace-scm-with-registry resolve
```

Если вы хотите гарантировать использование реестра при каждом разрешении зависимостей, вам нужно обновить `dependencies` в файле `Package.swift`, указав идентификатор реестра вместо URL.

<!-- @snippet: ./_registry-identifier -->
