---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Познавательная информация о пакетах {#bundle-size}

::: предупреждение РЕКВИЗИТЫ
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет и проект</LocalizedLink>
<!-- -->
:::

По мере того как вы добавляете в приложение все больше функций, размер пакета
приложения продолжает расти. Хотя некоторый рост размера пакета неизбежен,
поскольку вы поставляете больше кода и активов, есть много способов
минимизировать этот рост, например, обеспечить, чтобы ваши активы не
дублировались в пакетах, или удалить неиспользуемые двоичные символы. Tuist
предоставляет вам инструменты и знания, чтобы помочь вашему приложению
оставаться маленьким, и мы также отслеживаем его размер с течением времени.

## Использование {#usage}

Для анализа пакета можно использовать команду `tuist inspect bundle`:

::: code-group
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
<!-- -->
:::

Команда `tuist inspect bundle` анализирует пакет и предоставляет вам ссылку для
просмотра подробного обзора пакета, включая сканирование содержимого пакета или
разбивку по модулям:

![Анализируемый пучок](/images/guides/features/bundle-size/analyzed-bundle.png)

## Непрерывная интеграция {#continuous-integration}

Чтобы отследить размер пакета с течением времени, вам нужно проанализировать
пакет на CI. Во-первых, вам нужно убедиться, что ваш CI
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентифицирован</LocalizedLink>:

Пример рабочего процесса для GitHub Actions может выглядеть следующим образом:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

После настройки вы сможете увидеть, как изменяется размер вашего пакета с
течением времени:

![Граф размера пучка](/images/guides/features/bundle-size/bundle-size-graph.png)

## Комментарии к запросам на перетяжку/слияние {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Чтобы получить автоматические комментарии к запросам pull/merge, интегрируйте
ваш
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist-проект</LocalizedLink>
с
<LocalizedLink href="/guides/server/authentication">Git-платформой</LocalizedLink>.
<!-- -->
:::

Как только ваш проект Tuist будет связан с вашей Git-платформой, например
[GitHub](https://github.com), Tuist будет публиковать комментарий
непосредственно в ваших pull/merge запросах всякий раз, когда вы будете
выполнять `tuist inspect bundle`: ![GitHub app comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
