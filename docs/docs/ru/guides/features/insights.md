---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# Создавайте аналитические данные {#build-insights}

::: warning ТРЕБОВАНИЯ
<!-- -->
- <LocalizedLink href="/guides/server/accounts-and-projects"> Аккаунт Tuist и
  проект</LocalizedLink>
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
- Мои сборки на CI работают медленнее, чем при локальной разработке?

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
<LocalizedLink href="/guides/features/projects">генерируемые
проекты</LocalizedLink>, действие post-scheme не выполняется в случае неудачи
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

::: tip MISE и пути проекта
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

## Сгенерированные проекты {#generated-projects}

::: info
<!-- -->
Автоматически сгенерированные схемы автоматически включают в себя `tuist inspect
build` post-action.
<!-- -->
:::
> 
> Если вы не заинтересованы в отслеживании аналитических данных в автоматически
> сгенерированных схемах, отключите их с помощью параметра генерации
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

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

Когда `xcodebuild` собирает ваш проект без `-resultBundlePath`, необходимые
файлы журнала активности и пакета результатов не генерируются. Постобработка
`tuist inspect build` требует эти файлы для анализа ваших сборок.
