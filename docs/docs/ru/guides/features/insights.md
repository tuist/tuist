---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Озарения {#insights}

> [!ВАЖНЫЕ] ТРЕБОВАНИЯ
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Туистский счет
>   и проект</LocalizedLink>

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

> [!ПРИМЕЧАНИЕ] Tuist Insights находится на ранней стадии разработки.

## Сборки {#builds}

В то время как у вас, вероятно, есть некоторые показатели производительности
рабочих процессов CI, вы можете не иметь такого же представления о локальной
среде разработки. Однако время локальной сборки - один из важнейших факторов,
влияющих на работу разработчиков.

Чтобы начать отслеживать время локальной сборки, вы можете воспользоваться
командой `tuist inspect build`, добавив ее в пост-акцию вашей схемы:

![Пост-акция для проверки
построек](/images/guides/features/insights/inspect-build-scheme-post-action.png)

> [!ПРИМЕЧАНИЕ] Мы рекомендуем установить параметр "Provide build settings from"
> на исполняемый файл или вашу основную цель сборки, чтобы Tuist мог отслеживать
> конфигурацию сборки.

> [!ПРИМЕЧАНИЕ] Если вы не используете
> <LocalizedLink href="/guides/features/projects">сгенерированные
> проекты</LocalizedLink>, действие post-scheme не выполняется в случае неудачи
> сборки.
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
eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

tuist inspect build
```


Ваши локальные сборки теперь отслеживаются, пока вы входите в свой аккаунт
Tuist. Теперь вы можете получить доступ к времени сборки на панели Tuist и
посмотреть, как оно изменяется с течением времени:


> [!СОВЕТ] Чтобы быстро получить доступ к приборной панели, выполните команду
> `tuist project show --web` из CLI.

![Приборная панель с информацией о
сборке](/images/guides/features/insights/builds-dashboard.png)

## Сгенерированные проекты {#generated-projects}

> [!ПРИМЕЧАНИЕ] Автоматически созданные схемы автоматически включают `tuist
> inspect build` post-action.
> 
> Если вы не заинтересованы в отслеживании информации о сборке в ваших
> автоматически генерируемых схемах, отключите их с помощью опции генерации
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

Если вы используете сгенерированные проекты, вы можете настроить
пользовательское
<LocalizedLink href="references/project-description/structs/buildaction#postactions">пост-действие
сборки</LocalizedLink> с помощью пользовательской схемы, например:

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
                    .executionAction(
                        name: "Inspect Build",
                        scriptText: """
                        eval \"$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)\"
                        tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            testAction: .testAction(targets: ["MyAppTests"]),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Если вы не используете Mise, ваш сценарий может быть упрощен до простого:

```swift
.postAction(
    name: "Inspect Build",
    script: "tuist inspect build",
    execution: .always
)
```

## Непрерывная интеграция {#continuous-integration}

Чтобы отслеживать время сборки также на CI, вам нужно убедиться, что ваш CI
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">аутентифицирован</LocalizedLink>.

Кроме того, вам потребуется:
- Используйте команду
  <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> при вызове действий `xcodebuild`.
- Добавьте `-resultBundlePath` к вызову `xcodebuild`.

Когда `xcodebuild` собирает ваш проект без `-resultBundlePath`, файл
`.xcactivitylog` не генерируется. Однако пост-акция `tuist inspect build`
требует, чтобы этот файл был создан для анализа вашей сборки.
