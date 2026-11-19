---
{
  "title": "Покрытие кода в Xcode",
  "titleTemplate": ":title · Покрытие кода · Возможности · Руководства · Tuist",
  "description": "Загружайте данные о покрытии кода проектов Xcode в Tuist и отслеживайте их по файлам и коммитам."
}
---
# Покрытие кода в Xcode {#xcode-code-coverage}

Покрытие кода показывает, какие строки вашего кода выполнялись тестами. Tuist загружает покрытие по строкам для каждого запуска тестов и объединяет запуски одного коммита в одну метрику для проекта, каждой цели и каждого файла. На странице **Code Coverage** в дашборде эти данные отображаются по коммитам и в виде тренда для каждой ветки.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Если вы генерируете проект с помощью Tuist, вместо этого следуйте <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">руководству по сгенерированным проектам</.localized_link>: оно измеряет код, полученный из бинарного кэша, и переносит покрытие тех целей тестирования, которые пропускаются при выборочном тестировании.

## Настройка {#setup}

### Сбор покрытия {#collect-coverage}

Включите загрузку данных о покрытии в вашем `Tuist.swift`. По умолчанию эта функция отключена:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

Переменная окружения `TUIST_COVERAGE_UPLOAD` (`1` или `0`) имеет приоритет над настройкой, например, чтобы отключить загрузку в задачах, выполняющих pull-запросы из форков.

Затем включите **Code Coverage** в действии тестирования вашей схемы (**Edit Scheme › Test › Options**) или передайте флаг `-enableCodeCoverage YES` при запуске и выполните тесты через `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist загружает данные о покрытии, собранные во время запуска, вместе с результатами тестов.

### Завершение каждого коммита в CI {#complete-each-commit}

Покрытие коммита часто формируется из нескольких задач: по одной на схему, шард или платформу. Tuist не может самостоятельно определить, когда отчиталась последняя из них, поэтому укажите это явно. Как только все задачи тестирования для коммита завершатся, выполните эту команду в задаче, зависящей от всех них:

```sh
tuist coverage complete
```

Пока коммит не завершён, его покрытие отображается как **In progress** и не учитывается в тренде ветки. В <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">руководстве по сгенерированным проектам</.localized_link> описан каждый статус.

## Пропущенные тесты {#skipped-tests}

Когда запуск пропускает тесты с помощью `-skip-testing`, он измеряет меньше, чем покрывают тесты всего коммита, и Tuist не может перенести результаты этих тестов из предыдущего запуска. Покрытие коммита будет **Incomplete**, если другой запуск этого коммита не выполнил их. Чтобы коммит считался завершённым, выполняйте все тесты хотя бы в одном запуске для каждого коммита.

Тесты, пропущенные карантинными правилами, вообще не входят в покрытие, поэтому они никогда не делают коммит **Incomplete**.

## Влияние на производительность {#performance-impact}

Сбор данных о покрытии добавляет накладные расходы, преимущественно после завершения тестов, пока Xcode формирует отчёт о покрытии, а Tuist экспортирует данные. Сборка и выполнение тестов занимают примерно столько же времени, сколько и без сбора покрытия.

## Получение данных о покрытии {#querying}

Команды `tuist coverage` читают те же данные, что отображаются в дашборде. Без указания `--commit` они считывают последний завершённый коммит из `--branch` или из вашей ветки по умолчанию:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

Покрытие конкретного запуска тестов отображается в `tuist test show <test-run-id>`.

Все команды поддерживают флаг `--json` для использования в скриптах.
