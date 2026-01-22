---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Интеграция с GitHub {#github}

Репозитории Git являются центральным элементом подавляющего большинства
существующих программных проектов. Мы интегрируемся с GitHub, чтобы
предоставлять аналитическую информацию Tuist прямо в ваших запросах на
извлечение и избавить вас от необходимости выполнять некоторые настройки, такие
как синхронизация вашей ветки по умолчанию.

## Настройка {#setup}

Вам необходимо установить приложение Tuist GitHub в разделе «Интеграции» (` )
вашей организации в разделе «Интеграции» ( `): ![Изображение, показывающее
вкладку
«Интеграции»](/images/guides/integrations/gitforge/github/integrations.png)

После этого вы можете добавить связь между вашим репозиторием GitHub и проектом
Tuist:

![Изображение, демонстрирующее добавление подключения к
проекту](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Комментарии к pull/merge request {#pullmerge-request-comments}

Приложение GitHub публикует отчет о выполнении Tuist, который включает в себя
сводку PR, в том числе ссылки на последние
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">превью</LocalizedLink>
или
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">тесты</LocalizedLink>:

![Изображение, демонстрирующее комментарий к запросу на
извлечение](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
Комментарий публикуется только после
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентификации</LocalizedLink>
вашего CI.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Если у вас есть настраиваемый рабочий процесс, который запускается не при
фиксации PR, а, например, при комментировании в GitHub, вам может понадобиться
убедиться, что переменная `GITHUB_REF` установлена в одно из следующих значений:
`refs/pull/<pr_number>/merge` или
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

Вы можете запустить соответствующую команду, например `tuist share`, с префиксом
`GITHUB_REF` переменной среды: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
