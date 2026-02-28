---
{
  "title": "Docs",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist documentation site."
}
---
# Документация {#docs}

Источник:
[github.com/tuist/tuist/tree/main/documents](https://github.com/tuist/tuist/tree/main/docs)

## Для чего это нужно {#what-it-is-for}

На сайте docs размещена документация по продуктам и участникам Tuist. Он создан
с помощью VitePress.

## Как внести свой вклад {#how-to-contribute}

### Настройте локально {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Дополнительные сгенерированные данные {#optional-generated-data}

Мы вставляем некоторые сгенерированные данные в документацию:

- Справочные данные CLI: `mise run generate-cli-docs`
- Справочные данные манифеста проекта: `mise run generate-manifests-documents`

Эти действия не являются обязательными. Документация отображается и без них,
поэтому выполняйте их только в том случае, если вам нужно обновить
сгенерированный контент.
