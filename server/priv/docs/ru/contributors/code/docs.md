---
{
  "title": "Документация",
  "titleTemplate": ":title · Код · Участники · Tuist",
  "description": "Внесите свой вклад в сайт документации Tuist."
}
---
# Документация {#docs}

Источник: [github.com/tuist/tuist/tree/main/docs](https://github.com/tuist/tuist/tree/main/docs)

## Для чего это нужно {#what-it-is-for}

Сайт документации содержит документацию по продукту Tuist и информацию для контрибьюторов. Он построен на VitePress.

## Как внести вклад {#how-to-contribute}

### Локальная настройка {#set-up-locally}

```bash
cd docs
mise install
mise run dev
```

### Опциональные генерируемые данные {#optional-generated-data}

Мы включаем некоторые сгенерированные данные в документацию:

- Данные справки CLI: `mise run generate-cli-docs`

Это необязательно. Документация отображается без них, поэтому запускайте их только тогда, когда нужно обновить сгенерированный контент.

Справка API ProjectDescription размещена отдельно как сайт DocC по адресу [projectdescription.tuist.dev](https://projectdescription.tuist.dev). Чтобы собрать её локально, выполните `mise run docs:project-description` из корня репозитория.
