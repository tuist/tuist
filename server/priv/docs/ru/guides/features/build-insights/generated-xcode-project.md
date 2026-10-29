---
{
  "title": "Generated Xcode project",
  "titleTemplate": ":title · Build insights · Features · Guides · Tuist",
  "description": "Track build analytics for a Tuist-generated Xcode project on the Tuist dashboard."
}
---
# Сгенерированный проект Xcode {#generated-xcode-project-build-insights}

> [!NOTE]
> Автосгенерированные схемы автоматически включают пост-действие `tuist inspect build`.

>
> Если вы не хотите отслеживать аналитику сборки в сгенерированных схемах, отключите эту функцию с помощью [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Если вы используете сгенерированные проекты с пользовательскими схемами, вам нужно добавить пост-действие самостоятельно. Для [Mise](https://mise.jdx.dev/):

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

Если вы не используете Mise, вам нужно убедиться, что `tuist` доступен в окружении схемы, так как пост-действия Xcode не наследуют `PATH` вашей оболочки. Для установок через [Homebrew](https://brew.sh/):

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

## Аналитика сборки в CI {#continuous-integration}

Чтобы отслеживать аналитику сборки в CI, убедитесь, что CI <.localized_link href="/guides/integrations/continuous-integration#authentication">аутентифицирован</.localized_link>.

Для CI на основе xcodebuild вам необходимо:
- Использовать <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> при вызове действий `xcodebuild`.
- Добавить `-resultBundlePath` в вашу команду `xcodebuild`.

Без `-resultBundlePath` необходимые журналы активности и пакеты результатов не генерируются, и `tuist inspect build` не может проанализировать сборку.

## Метрики машины {#machine-metrics}

Аналитика сборки может включать метрики производительности на уровне машины (ЦП, память, сеть и использование диска), собираемые во время сборки. Чтобы включить это, настройте легкий фоновый демон, который непрерывно собирает системные метрики:

```bash
tuist setup insights
```

Это запускает локальный демон, который собирает метрики в фоновом режиме. Данные автоматически подбираются `tuist inspect build` и загружаются вместе с отчетом о сборке.

> [!TIP]
> **Ci**
>
> Выполните `tuist setup insights` на ваших машинах CI перед сборкой, чтобы также собирать метрики машины там.

Чтобы прекратить сбор метрик машины, выполните:

```bash
tuist teardown insights
```

Это выгружает LaunchAgent демона, удаляет его plist и удаляет собранные метрики и логи демона из `~/.local/state`, поэтому ничего не остается работать в фоновом режиме.


## Пользовательские метаданные {#custom-metadata}

Вы можете прикреплять метаданные к сборкам с помощью переменных окружения для улучшения фильтрации.

### Переменные окружения

| Переменная | Формат | Описание |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Разделено запятыми | Несколько тегов в одной переменной. |
| `TUIST_BUILD_VALUE_*` | Одно значение | Пара ключ-значение, где суффикс является ключом. |

### Примеры

Установите эти значения в CI или вашей оболочке перед запуском сборки:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
