---
{
  "title": "Аналитика тестов Xcode",
  "titleTemplate": ":title · Аналитика тестов · Возможности · Руководства · Tuist",
  "description": "Отслеживайте аналитику тестов Xcode, чтобы выявлять медленные и нестабильные тесты с помощью Tuist Test Insights."
}
---
# Аналитика тестов Xcode {#xcode-test-insights}

Tuist Test Insights предоставляет аналитику тестов Xcode для мониторинга состояния вашего набора тестов: выявляет медленные тесты и помогает быстро понять причины сбоев запусков в CI. По мере роста набора тестов становится всё сложнее замечать тенденции, например постепенное замедление тестов или периодические сбои. Tuist Test Insights даёт необходимую видимость, чтобы поддерживать быстрый и надёжный набор тестов.

С помощью Test Insights вы можете ответить на такие вопросы:
- Стали ли мои тесты медленнее? Какие именно?
- Какие тесты нестабильны и требуют внимания?
- Почему мой запуск в CI завершился ошибкой?

## Настройка {#setup}

Чтобы начать отслеживать тесты, используйте команду `tuist inspect test`, добавив её в пост-действие теста вашей схемы:

![Пост-действие для инспекции тестов](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

Если вы используете [Mise](https://mise.jdx.dev/), ваш скрипт должен активировать `tuist` в окружении пост-действия:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise и пути проекта**
>
> Переменная окружения `PATH` не наследуется пост-действием схемы, поэтому нужно использовать абсолютный путь к Mise, который зависит от способа установки Mise. Кроме того, не забудьте унаследовать настройки сборки из цели вашего проекта, чтобы можно было запустить Mise из директории, на которую указывает $SRCROOT.

Ваши запуски тестов теперь отслеживаются, пока вы вошли в учётную запись Tuist. Вы можете просматривать аналитику тестов в панели управления Tuist и видеть, как она меняется со временем:

![Панель управления с аналитикой тестов](/images/guides/features/build-insights/tests-dashboard.png)

Помимо общих тенденций, вы также можете детально изучить каждый отдельный тест, например при отладке сбоев или медленных тестов в CI:

![Детали теста](/images/guides/features/build-insights/test-detail.png)

## Сгенерированные проекты {#generated-projects}

> [!NOTE]
> Автосгенерированные схемы автоматически включают пост-действие `tuist inspect test`.

>
> Если вам не нужно отслеживать аналитику тестов в автосгенерированных схемах, отключите её с помощью опции генерации [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

Если вы используете сгенерированные проекты с пользовательскими схемами, вы можете настроить пост-действия для аналитики тестов:

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

Если вы не используете Mise, ваши скрипты можно упростить до:

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

Чтобы отслеживать аналитику тестов в CI, убедитесь, что ваш CI <.localized_link href="/guides/integrations/continuous-integration#authentication">аутентифицирован</.localized_link>.

Кроме того, вам потребуется либо:
- Использовать команду <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> при вызове действий `xcodebuild`.
- Добавить `-resultBundlePath` к вызову `xcodebuild`.

Когда `xcodebuild` тестирует ваш проект без `-resultBundlePath`, необходимые файлы результирующего бандла не создаются. Пост-действию `tuist inspect test` эти файлы нужны для анализа ваших тестов.

### История Git {#git-history}

В CI Tuist также загружает историю коммитов 체크아웃a: SHA коммитов, их родительские коммиты, даты коммитов и ветку, в которой выполнялся запуск, а также базовую ветку pull request'а. Содержимое файлов, сообщения коммитов и авторы не загружаются. Это позволяет Tuist определить, какие коммиты попали в вашу основную ветку, например те, которые проверяла очередь слияний. Tuist читает историю, уже имеющуюся в 체크아웃е, а если в нём нет базовой ветки, запрашивает у удалённого репозитория последний коммит (`git ls-remote`). Вне задач покрытия кода история не загружается.

| Переменная | Эффект |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Не читает и не загружает историю Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Читает только текущий чеккаут, не обращаясь к удалённому репозиторию. |
