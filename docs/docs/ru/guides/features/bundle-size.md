---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Аналитика бандла {#bundle-size}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
<!-- -->
:::

По мере добавления новых функций размер бандла приложения продолжает расти. Хотя
часть этого роста неизбежна по мере добавления кода и ресурсов, существует
множество способов его минимизировать, например, убедившись, что ресурсы не
дублируются между бандлами, или удаляя неиспользуемые бинарные символы. Tuist
предоставляет инструменты и аналитику, которые помогают сохранять размер
приложения компактным, а также отслеживает его изменение со временем.

## Использование {#usage}

Для анализа бандла можно использовать команду `tuist inspect bundle`:

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

Команда `tuist inspect bundle` анализирует бандл и предоставляет ссылку на
подробный обзор, включающий сканирование его содержимого или разбивку по
модулям:

![Анализируемый бандл](/images/guides/features/bundle-size/analyzed-bundle.png)

## Непрерывная интеграция {#continuous-integration}

Чтобы отследить размер пакета с течением времени, вам нужно проанализировать
бандл на CI. Во-первых, вам нужно убедиться, что ваш CI
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

После настройки вы сможете увидеть, как изменяется размер вашего бандл с
течением времени:

![Граф размера
бандла](/images/guides/features/bundle-size/bundle-size-graph.png)

## Комментарии к pull/merge request {#pullmerge-request-comments}

::: warning ТРЕБУЕТСЯ ИНТЕГРАЦИЯ С GIT
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
