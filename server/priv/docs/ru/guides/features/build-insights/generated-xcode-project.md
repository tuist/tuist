---
{
  "title": "Сгенерированный проект Xcode",
  "titleTemplate": ":title · Аналитика сборок · Возможности · Руководства · Tuist",
  "description": "Отслеживайте аналитику сборок для проекта Xcode, сгенерированного в Tuist, на панели управления Tuist."
}
---
# Сгенерированный Xcode-проект {#generated-xcode-project-build-insights}

> [!NOTE]
> Автосгенерированные схемы автоматически включают пост-действие `tuist inspect build`.

>
> Если вы не хотите отслеживать аналитику сборок в сгенерированных схемах, отключите её с помощью [buildInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

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

Если вы не используете Mise, нужно убедиться, что `tuist` доступен в окружении схемы, поскольку пост-действия Xcode не наследуют `PATH` вашей оболочки. Для установок через [Homebrew](https://brew.sh/):

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

## Аналитика сборок в CI {#continuous-integration}

Чтобы отслеживать аналитику сборок в CI, убедитесь, что CI <.localized_link href="/guides/integrations/continuous-integration#authentication">аутентифицирован</.localized_link>.

Для CI на базе xcodebuild необходимо:
- Используйте <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> при вызове действий `xcodebuild`.
- Добавьте `-resultBundlePath` к вашей команде `xcodebuild`.

Без `-resultBundlePath` не генерируются необходимые журналы активности и пакеты результатов, поэтому `tuist inspect build` не сможет проанализировать сборку.

## Метрики машины {#machine-metrics}

Аналитика сборок может включать метрики производительности на уровне машины (ЦП, память, сеть и использование диска), собираемые во время сборки. Чтобы включить это, настройте лёгкий фоновый демон, который непрерывно собирает системные метрики:

```bash
tuist setup insights
```

Это запускает локальный демон, который собирает метрики в фоне. Данные автоматически подхватываются `tuist inspect build` и загружаются вместе с отчётом о сборке.

> [!TIP]
> **Ci**
>
> Выполните `tuist setup insights` на ваших CI-машинах перед сборкой, чтобы также собирать машинные метрики там.

Чтобы прекратить сбор машинных метрик, выполните:

```bash
tuist teardown insights
```

Это выгружает LaunchAgent демона, удаляет его plist и стирает собранные метрики и логи демона из `~/.local/state`, так что в фоне ничего не остаётся работать.


## Пользовательские метаданные {#custom-metadata}

Вы можете прикреплять метаданные к сборкам через переменные окружения, чтобы улучшить фильтрацию.

### Переменные окружения

| Переменная | Формат | Описание |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Разделённые запятыми | Несколько тегов в одной переменной. |
| `TUIST_BUILD_VALUE_*` | Одно значение | Пара ключ-значение, где суффикс является ключом. |

### Примеры

Установите эти значения в CI или в вашей оболочке перед запуском сборки:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
