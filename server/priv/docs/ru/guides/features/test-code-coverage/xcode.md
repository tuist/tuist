---
{
  "title": "Покрытие кода в Xcode",
  "titleTemplate": ":title · Покрытие кода · Возможности · Руководства · Tuist",
  "description": "Загружайте данные о покрытии кода проектов Xcode в Tuist и отслеживайте их по файлам и коммитам."
}
---
# Покрытие кода в Xcode {#xcode-code-coverage}

Покрытие кода показывает, какие строки вашего кода выполнили тесты. Tuist загружает покрытие по строкам каждого запуска тестов и сводит запуски одного коммита в одну метрику для проекта, каждой цели и каждого файла. На странице **Покрытие кода** в дашборде оно отображается по коммитам и как тренд для каждой ветки.

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> Если вы генерируете проект с помощью Tuist, следуйте <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">руководству по сгенерированным проектам</.localized_link>: оно измеряет код из бинарного кеша и переносит покрытие тех целей тестирования, которые пропускает выборочное тестирование.

## Настройка {#setup}

### Сбор покрытия {#collect-coverage}

Включите загрузку покрытия в вашем `Tuist.swift`. По умолчанию она отключена:

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

Переменная окружения `TUIST_COVERAGE_UPLOAD` (`1` или `0`) имеет приоритет над настройкой, например чтобы отключить загрузку в задачах, выполняющих пул-реквесты из форков.

Затем включите **Покрытие кода** в действии тестирования вашей схемы (**Edit Scheme › Test › Options**) или передайте `-enableCodeCoverage YES` при запуске и выполните тесты через `tuist xcodebuild test`:

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist загружает покрытие, собранное во время запуска, вместе с результатами тестов.

### Завершение каждого коммита в CI {#complete-each-commit}

Покрытие коммита часто формируется из нескольких задач: по одной на схему, шард или платформу. Tuist не может определить, когда последняя из них завершила отчёт, поэтому укажите это явно. Когда все тестовые задачи для коммита завершатся, выполните эту команду в задаче, зависящей от всех них:

```sh
tuist coverage complete
```

Команда считывает коммит из `HEAD` 체크아웃a — коммит, на котором выполнялись ваши тесты; передайте `--commit <sha>`, чтобы указать другой. Пока коммит не завершён, его покрытие отображается как **В процессе** и не учитывается в тренде ветки. Каждый статус описан в <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">руководстве по сгенерированным проектам</.localized_link>.

## Пропущенные тесты {#skipped-tests}

Когда запуск пропускает тесты с помощью `-skip-testing`, он измеряет меньше, чем покрывают тесты коммита, и Tuist не может перенести эти тесты из предыдущего запуска. Покрытие коммита будет **Неполным**, если только другой запуск этого коммита не выполнил их. Чтобы коммит оставался завершённым, выполняйте каждый тест хотя бы в одном запуске на коммит.

Тесты, пропущенные карантином, вообще не входят в покрытие, поэтому они никогда не делают коммит **Неполным**.

## Влияние на производительность {#performance-impact}

Сбор покрытия добавляет накладные расходы, в основном после завершения тестов, пока Xcode записывает отчёт о покрытии, а Tuist экспортирует данные. Сборка и выполнение тестов занимают примерно столько же времени, сколько и без покрытия.

## Запросы покрытия {#querying}

Команды `tuist coverage` читают данные, отображаемые в дашборде. Без `--commit` они читают последний завершённый коммит из `--branch` или из вашей ветки по умолчанию:

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

Все команды поддерживают `--json` для скриптов.
