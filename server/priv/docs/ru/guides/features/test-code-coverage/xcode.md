---
{
  "title": "Покрытие кода в Xcode",
  "titleTemplate": ":title · Покрытие кода · Возможности · Руководства · Tuist",
  "description": "Загружайте данные о покрытии кода проектов Xcode в Tuist и отслеживайте их по файлам и коммитам."
}
---
# Покрытие кода в Xcode {#xcode-code-coverage}

Покрытие кода показывает, какие строки вашего кода были выполнены тестами. Tuist загружает покрытие по строкам для каждого запуска тестов и объединяет результаты всех запусков одного коммита в единый показатель для проекта, каждой цели и каждого файла. На странице **Code Coverage** дашборда эти данные отображаются по коммитам и в виде тренда для каждой ветки.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Если вы генерируете проект с помощью Tuist, вместо этого следуйте <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">руководству по сгенерированным проектам</.localized_link>: оно учитывает код из бинарного кэша и переносит покрытие целей тестирования, которые пропускаются при выборочном тестировании.

## Настройка {#setup}

### Сбор покрытия {#collect-coverage}

Включите загрузку данных о покрытии в вашем файле `Tuist.swift`. По умолчанию эта опция отключена:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

Переменная окружения `TUIST_COVERAGE_UPLOAD` (`1` или `0`) имеет приоритет над настройкой, например, чтобы отключить загрузку в задачах, выполняющих pull-requests из форков.

Затем включите **Code Coverage** в действии тестирования вашей схемы (**Edit Scheme › Test › Options**) или передайте флаг `-enableCodeCoverage YES` при запуске и выполните тесты через `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist загружает собранное покрытие вместе с результатами тестов.

### Завершение каждого коммита в CI {#complete-each-commit}

Покрытие коммита часто формируется несколькими задачами: по одной на схему, шард или платформу. Tuist не может самостоятельно определить, когда последняя из них завершила отчет, поэтому укажите это явно. Как только все задачи тестирования для коммита завершатся, выполните следующую команду в задаче, зависящей от всех них:

```sh
tuist coverage complete
```

До завершения коммита его покрытие отображается как **In progress** и не учитывается в тренде ветки. В <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">руководстве по сгенерированным проектам</.localized_link> описан каждый статус.

## Пропущенные тесты {#skipped-tests}

Когда запуск пропускает тесты с помощью флага `-skip-testing`, измеряется меньшая часть кода, чем покрывают тесты коммита, и Tuist не может перенести результаты этих тестов из предыдущих запусков. Покрытие коммита помечается как **Incomplete**, если только другой запуск этого же коммита не выполнил их. Чтобы коммит считался завершенным, выполните все тесты хотя бы в одном запуске для каждого коммита.

Тесты, пропущенные карантином, вообще не входят в покрытие, поэтому они никогда не делают коммит **Incomplete**.

## Влияние на производительность {#performance-impact}

Сбор данных о покрытии добавляет накладные расходы, преимущественно после завершения тестов, пока Xcode формирует отчет о покрытии, а Tuist экспортирует данные. Сборка и выполнение тестов занимают примерно столько же времени, сколько и без сбора покрытия.

## Запрос данных о покрытии {#querying}

Команды `tuist coverage` читают те же данные, что отображаются на дашборде. Без указания `--commit` они показывают данные последнего завершенного коммита ветки `--branch` или вашей ветки по умолчанию:

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

Покрытие конкретного запуска тестов отображается в команде `tuist test show <test-run-id>`.

Все команды поддерживают флаг `--json` для использования в скриптах.
