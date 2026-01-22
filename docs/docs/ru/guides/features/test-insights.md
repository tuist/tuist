---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# Тестовые выводы {#test-insights}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
<!-- -->
:::

Аналитика тестов помогает вам отслеживать работоспособность набора тестов,
выявляя медленные тесты или быстро понимая причины неудачных запусков CI. По
мере роста набора тестов становится все труднее обнаруживать такие тенденции,
как постепенное замедление тестов или периодические сбои. Tuist Test Insights
предоставляет вам необходимую информацию для поддержания быстрого и надежного
набора тестов.

С помощью Test Insights вы можете ответить на такие вопросы, как:
- Стали ли мои тесты работать медленнее? Какие именно?
- Какие тесты являются нестабильными и требуют внимания?
- Почему мой CI не сработал?

## Настройка {#setup}

Чтобы начать отслеживать свои тесты, вы можете воспользоваться командой `tuist
inspect test`, добавив ее в пост-акцию тестирования вашей схемы:

![Пост-акция по проверке
тестов](/images/guides/features/insights/inspect-test-scheme-post-action.png)

Если вы используете [Mise](https://mise.jdx.dev/), ваш сценарий должен будет
активировать `tuist` в пост-активном окружении:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE и пути проекта
<!-- -->
Переменная окружения `PATH` не наследуется пост-экшеном схемы, поэтому вам
придется использовать абсолютный путь Mise, который зависит от того, как вы
установили Mise. Кроме того, не забудьте унаследовать настройки сборки от цели в
вашем проекте, чтобы вы могли запускать Mise из каталога, на который указывает
$SRCROOT.
<!-- -->
:::

Проведение тестов теперь отслеживается до тех пор, пока вы входите в свою
учетную запись Tuist. Вы можете получить доступ к результатам тестирования на
приборной панели Tuist и увидеть, как они меняются со временем:

![Дашборд с аналитикой
тестов](/images/guides/features/insights/tests-dashboard.png)

Помимо общих тенденций, вы также можете глубоко погрузиться в каждый отдельный
тест, например, при отладке сбоев или медленных тестов на CI:

![Подробности теста](/images/guides/features/insights/test-detail.png)

## Сгенерированные проекты {#generated-projects}

::: info
<!-- -->
Автоматически сгенерированные схемы автоматически включают в себя `tuist inspect
test` post-action.
<!-- -->
:::
> 
> Если вы не заинтересованы в отслеживании результатов тестирования в
> автоматически сгенерированных схемах, отключите их с помощью опции генерации
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>.

Если вы используете сгенерированные проекты с пользовательскими схемами, вы
можете настроить пост-действия как для сборки, так и для тестирования:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Если вы не используете Mise, ваши сценарии могут быть упрощены до:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## Непрерывная интеграция {#continuous-integration}

Чтобы отслеживать результаты сборки и тестирования на CI, вам нужно убедиться,
что ваш CI
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентифицирован</LocalizedLink>.

Кроме того, вам потребуется:
- Используйте команду
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> при вызове действий `xcodebuild`.
- Добавьте `-resultBundlePath` к вызову `xcodebuild`.

Когда `xcodebuild` тестирует ваш проект без `-resultBundlePath`, необходимые
файлы пакета результатов не генерируются. `tuist inspect test` post-action
требует эти файлы для анализа ваших тестов.
