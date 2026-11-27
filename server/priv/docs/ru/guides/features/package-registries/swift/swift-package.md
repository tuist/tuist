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

Чтобы гарантировать использование реестра при каждом разрешении зависимостей, нужно обновить `dependencies` в файле `Package.swift`, заменив URL на идентификатор реестра.

<!-- @snippet: ./_registry-identifier -->
