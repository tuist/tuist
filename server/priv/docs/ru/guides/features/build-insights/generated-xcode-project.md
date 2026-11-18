---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Аналитика сборок · Возможности · Руководства · Tuist",
  "description": "Отслеживайте аналитику сборок для проекта Xcode, созданного с помощью Tuist, в панели управления Tuist."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project-build-insights}

> [!NOTE]
> Автоматически созданные схемы по умолчанию включают пост-действие `tuist inspect build`.
>
> Если вы не хотите отслеживать аналитику сборок в сгенерированных схемах, отключите эту функцию с помощью [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Если вы используете сгенерированные проекты с пользовательскими схемами, необходимо добавить пост-действие самостоятельно. Для [Mise](https://mise.jdx.dev/):

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
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                runPostActionsOnFailure: true
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Если вы не используете Mise, убедитесь, что `tuist` доступен в окружении схемы, так как пост-действия Xcode не наследуют переменную `PATH` вашей оболочки. Для установок через [Homebrew](https://brew.sh/):

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            tuist inspect build
            """,
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
)
```

<!-- @snippet: ./_xcode-ci -->

<!-- @snippet: ./_xcode-network-trusted -->

<!-- @snippet: ./_xcode-machine-metrics -->

<!-- @snippet: ./_xcode-actor-claim -->

<!-- @snippet: ./_xcode-custom-metadata -->
