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

Вам нужно установить приложение Tuist GitHub на вкладке `Integrations` вашей
организации: ![Изображение, показывающее вкладку
интеграций](/images/guides/integrations/gitforge/github/integrations.png)

После этого вы можете добавить проектную связь между вашим репозиторием GitHub и
проектом Tuist:

![Изображение, показывающее добавление связи с
проектом](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Комментарии к запросам на перетяжку/слияние {#pull-merge-request-comments}

Приложение GitHub публикует отчет о выполнении Tuist, который содержит краткую
информацию о PR, включая ссылки на последние
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">превью</LocalizedLink>
или
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">тесты</LocalizedLink>:

![Изображение, показывающее комментарий к запросу на вытягивание]
(/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Комментарий будет опубликован только в том случае, если ваши CI-запуски
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентифицированы</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Если у вас есть собственный рабочий процесс, который запускается не на
PR-коммит, а, например, на комментарий GitHub, вам может понадобиться убедиться,
что переменная `GITHUB_REF` установлена либо на `refs/pull/<pr_number>/merge`,
либо на `refs/pull/<pr_number>/head`.</pr_number></pr_number>

Вы можете выполнить соответствующую команду, например `tuist share`, с префиксом
`GITHUB_REF` переменной окружения: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
