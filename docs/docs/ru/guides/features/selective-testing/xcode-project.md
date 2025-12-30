---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Проект Xcode {#xcode-project}

::: предупреждение РЕКВИЗИТЫ
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет и проект</LocalizedLink>
<!-- -->
:::

Вы можете запускать тесты ваших проектов Xcode выборочно через командную строку.
Для этого вы можете дополнить команду `xcodebuild` командой `tuist` - например,
`tuist xcodebuild test -scheme App`. Команда хэширует ваш проект и в случае
успеха сохраняет хэши, чтобы определить, что изменилось в последующих запусках.

В последующих запусках `tuist xcodebuild test` прозрачно использует хэши для
фильтрации тестов, чтобы запускать только те, которые изменились с момента
последнего успешного запуска теста.

Например, предположим следующий граф зависимостей:

- `FeatureA` имеет тесты `FeatureATests`, и зависит от `Core`
- `FeatureB` имеет тесты `FeatureBTests`, и зависит от `Core`
- `Ядро` имеет тесты `CoreTests`

`tuist xcodebuild test` будет вести себя именно так:

| Действие                           | Описание                                                                     | Внутреннее состояние                                                  |
| ---------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `tuist xcodebuild test` invocation | Запускает тесты из разделов `CoreTests`, `FeatureATests`, и `FeatureBTests.` | Хэши `FeatureATests`, `FeatureBTests` и `CoreTests` сохраняются.      |
| `ФункцияА` обновляется             | Разработчик изменяет код целевой программы                                   | Как и раньше                                                          |
| `tuist xcodebuild test` invocation | Запускает тесты в `FeatureATests`, потому что хэш изменился.                 | Новый хэш `FeatureATests` сохраняется.                                |
| `Обновлено ядро`                   | Разработчик изменяет код целевой программы                                   | Как и раньше                                                          |
| `tuist xcodebuild test` invocation | Запускает тесты из разделов `CoreTests`, `FeatureATests`, и `FeatureBTests.` | Новый хэш `FeatureATests` `FeatureBTests`, и `CoreTests` сохраняется. |

Чтобы использовать `tuist xcodebuild test` в вашем CI, следуйте инструкциям в
руководстве
<LocalizedLink href="/guides/integrations/continuous-integration">Continuous integration guide</LocalizedLink>.

Посмотрите следующее видео, чтобы увидеть выборочное тестирование в действии:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
