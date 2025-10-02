---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Интеграция с GitHub {#github}

Git-репозитории являются центральным элементом подавляющего большинства
программных проектов. Мы интегрируемся с GitHub, чтобы предоставлять информацию
о Tuist прямо в ваших запросах на внесение изменений и избавить вас от некоторых
настроек, таких как синхронизация ветки по умолчанию.

## Настройка {#setup}

Установите приложение [Tuist GitHub app](https://github.com/marketplace/tuist).
После установки вам нужно будет сообщить Tuist URL вашего репозитория, например:

```sh
tuist project update tuist/tuist --repository-url https://github.com/tuist/tuist
```
