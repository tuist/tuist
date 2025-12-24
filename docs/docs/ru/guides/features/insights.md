---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Озарения {#insights}

::: предупреждение РЕКВИЗИТЫ
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет и проект</LocalizedLink>
<!-- -->
:::

Работа над крупными проектами не должна казаться рутиной. На самом деле, она
должна быть такой же приятной, как и работа над проектом, который вы начали
всего две недели назад. Одна из причин, по которой это не так, заключается в
том, что по мере роста проекта страдает опыт разработчиков. Время сборки
увеличивается, а тесты становятся медленными и нестабильными. Зачастую на эти
проблемы легко не обращать внимания, пока они не становятся невыносимыми -
однако в этот момент их сложно решить. Tuist Insights предоставляет вам
инструменты для мониторинга состояния проекта и поддержания продуктивной среды
разработчиков по мере масштабирования проекта.

Другими словами, Tuist Insights поможет вам ответить на такие вопросы, как:
- Значительно ли увеличилось время сборки за последнюю неделю?
- Стали ли мои тесты работать медленнее? Какие именно?

::: info
<!-- -->
Tuist Insights находится на ранней стадии разработки.
<!-- -->
:::

## Сборки {#builds}

В то время как у вас, вероятно, есть некоторые показатели производительности
рабочих процессов CI, вы можете не иметь такого же представления о локальной
среде разработки. Однако время локальной сборки - один из важнейших факторов,
влияющих на работу разработчиков.

Чтобы начать отслеживать время локальной сборки, вы можете воспользоваться
командой `tuist inspect build`, добавив ее в пост-акцию вашей схемы:

![Пост-акция для проверки
построек](/images/guides/features/insights/inspect-build-scheme-post-action.png)

::: info
<!-- -->
Мы рекомендуем установить параметр "Provide build settings from" на исполняемый
файл или вашу основную цель сборки, чтобы Tuist мог отслеживать конфигурацию
сборки.
<!-- -->
:::

::: info
<!-- -->
Если вы не используете
<LocalizedLink href="/guides/features/projects">генерируемые проекты</LocalizedLink>, действие post-scheme не выполняется в случае неудачи
сборки.
<!-- -->
:::
> 
> Недокументированная функция в Xcode позволяет выполнить его даже в этом
> случае. Установите атрибут `runPostActionsOnFailure` в значение `YES` в
> `BuildAction вашей схемы` в соответствующем `файле project.pbxproj` следующим
> образом:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

Если вы используете [Mise](https://mise.jdx.dev/), ваш сценарий должен будет
активировать `tuist` в пост-активном окружении:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
```

::: наконечник MISE & PROJECT PATHS
<!-- -->
Переменная окружения `PATH` не наследуется пост-экшеном схемы, поэтому вам
придется использовать абсолютный путь Mise, который зависит от того, как вы
установили Mise. Кроме того, не забудьте унаследовать настройки сборки от цели в
вашем проекте, чтобы вы могли запускать Mise из каталога, на который указывает
$SRCROOT.
<!-- -->
:::


Ваши локальные сборки теперь отслеживаются, пока вы входите в свою учетную
запись Tuist. Теперь вы можете получить доступ к времени сборки на панели Tuist
и посмотреть, как оно изменяется с течением времени:


::: tip
<!-- -->
Чтобы быстро получить доступ к приборной панели, выполните команду `tuist
project show --web` из CLI.
<!-- -->
:::

![Приборная панель с информацией о
сборке](/images/guides/features/insights/builds-dashboard.png)

## Тесты {#tests}

Помимо отслеживания сборок, вы также можете контролировать свои тесты. Тестовые
инсайты помогут вам выявить медленные тесты или быстро разобраться в неудачных
прогонах CI.

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

::: наконечник MISE & PROJECT PATHS
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
Автоматически сгенерированные схемы автоматически включают пост-действия `tuist
inspect build` и `tuist inspect test`.
<!-- -->
:::
> 
> Если вам неинтересно отслеживать понимание в автогенерируемых схемах,
> отключите их с помощью опций генерации
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> и
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
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
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
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
),
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
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> при вызове действий `xcodebuild`.
- Добавьте `-resultBundlePath` к вызову `xcodebuild`.

Когда `xcodebuild` собирает или тестирует ваш проект без `-resultBundlePath`,
необходимые файлы журнала активности и пакета результатов не создаются.
Пост-операции `tuist inspect build` и `tuist inspect test` требуют эти файлы для
анализа ваших сборок и тестов.
