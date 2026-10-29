---
{
  "title": "Xcode Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Xcode test analytics to identify slow and flaky tests with Tuist Test Insights."
}
---
# Аналитика тестов Xcode {#xcode-test-insights}

Tuist Test Insights предоставляет аналитику тестов Xcode для мониторинга состояния вашего набора тестов, выявляя медленные тесты или помогая быстро понять причины сбоев в CI. По мере роста набора тестов становится всё сложнее замечать такие тенденции, как постепенное замедление тестов или периодические сбои. Tuist Test Insights обеспечивает необходимую видимость для поддержания быстрого и надёжного набора тестов.

С помощью Test Insights вы можете ответить на такие вопросы, как:
- Стали ли мои тесты медленнее? Какие именно?
- Какие тесты нестабильны и требуют внимания?
- Почему мой запуск CI завершился ошибкой?

## Настройка {#setup}

Чтобы начать отслеживать свои тесты, вы можете использовать команду `tuist inspect test`, добавив её в пост-действие теста вашей схемы:

![Пост-действие для анализа тестов](/images/guides/features/build-insights/inspect-test-scheme-post-action.png)

Если вы используете [Mise](https://mise.jdx.dev/), ваш скрипт должен активировать `tuist` в среде пост-действия:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

> [!TIP]
> **Mise и пути к проекту**
>
> Переменная окружения `PATH` не наследуется пост-действием схемы, поэтому вам нужно использовать абсолютный путь к Mise, который зависит от способа установки Mise. Кроме того, не забудьте наследовать настройки сборки из цели вашего проекта, чтобы иметь возможность запускать Mise из директории, на которую указывает $SRCROOT.

Ваши запуски тестов теперь отслеживаются, пока вы вошли в свой аккаунт Tuist. Вы можете получить доступ к аналитике тестов в панели управления Tuist и видеть, как они изменяются со временем:

![Панель управления с аналитикой тестов](/images/guides/features/build-insights/tests-dashboard.png)

Помимо общих тенденций, вы также можете подробно изучить каждый отдельный тест, например, при отладке сбоев или медленных тестов в CI:

![Детали теста](/images/guides/features/build-insights/test-detail.png)

## Сгенерированные проекты {#generated-projects}

> [!NOTE]
> Автосгенерированные схемы автоматически включают пост-действие `tuist inspect test`.

>
> Если вы не заинтересованы в отслеживании аналитики тестов в автосгенерированных схемах, отключите их, используя опцию генерации [testInsightsDisabled](https://projectdescription.tuist.dev/documentation/projectdescription/tuist).

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

Для отслеживания аналитики тестов в CI вам необходимо убедиться, что ваш CI <.localized_link href="/guides/integrations/continuous-integration#authentication">аутентифицирован</.localized_link>.

Кроме того, вам нужно будет либо:
- Использовать команду <.localized_link href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</.localized_link> при вызове действий `xcodebuild`.
- Добавить `-resultBundlePath` к вашему вызову `xcodebuild`.

Когда `xcodebuild` тестирует ваш проект без `-resultBundlePath`, необходимые файлы пакетов результатов не генерируются. Пост-действию `tuist inspect test` требуются эти файлы для анализа ваших тестов.

### История Git {#git-history}

В CI Tuist также загружает историю коммитов 체크아웃a: SHA коммитов, их родителей, даты коммитов и ветку, в которой выполнялся запуск, а также базовую ветку pull request'а. Содержимое файлов, сообщения коммитов или авторы не загружаются. Это позволяет Tuist определить, какие коммиты попали в вашу основную ветку, например, те, которые тестировала очередь слияний. Tuist считывает историю, которая уже есть в 체크아웃е, а если в 체크아웃е нет базовой ветки, запрашивает у удалённого репозитория его последний коммит (`git ls-remote`). Вне контекста покрытия кода история не загружается.

| Переменная | Эффект |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | Не считывает и не загружает никакую историю Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Считывает только 체크아웃, не обращаясь к удалённому репозиторию. |
