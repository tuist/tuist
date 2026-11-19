---
{
  "title": "Начало работы",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Выберите подход Tuist, соответствующий текущему способу сборки вашего приложения: Xcode, генерируемые проекты Xcode, Gradle, Elixir, Rust, Bazel или Struo."
}
---
# Начало работы {#get-started}

Выберите путь, соответствующий тому, как ваше приложение собирается сегодня. Каждый из них подробно описывает, что нужно установить, как включить кэширование, аналитику и функции тестирования, а также как проверить настройку от начала до конца. Вы можете внедрять их по отдельности или комбинировать, если выпускаете обновления для нескольких платформ.

Большинство путей используют <.localized_link href="/guides/install-tuist">интерфейс командной строки Tuist</.localized_link>. Elixir использует пакет Hex, а Struo подключается через свой нативный провайдер Tuist; ни один из них не требует CLI Tuist для интеграции.

## Проект Xcode {#existing-xcode-project}

Сохраните существующий проект или рабочую область Xcode и добавляйте возможности Tuist по одной. Генерация проекта не требуется.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Сгенерированный проект Xcode {#generated-xcode-project}

Позвольте Tuist определять и генерировать ваш проект Xcode из манифестов Swift. Сгенерированные проекты сжимают сложность модульных проектов Xcode в лаконичное декларативное описание графа и являются строгим требованием для <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link> и <.localized_link href="/guides/features/selective-testing/generated-xcode-project">выборочного тестирования</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Проект Gradle {#gradle-project}

Подключите проект Gradle к удаленному кэшу Tuist, аналитике сборок и аналитике тестов через плагин Gradle `dev.tuist`.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Проект Elixir {#elixir-project}

Подключите проект Elixir к аналитике сборок Tuist, аналитике тестов, обнаружению нестабильных тестов и шардированию тестов через пакет Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Проект Rust {#rust-project}

Запускайте Cargo через CLI Tuist, чтобы отправлять отчеты о сборках и результатах отдельных тестов, включая doctests, и исследовать нестабильные тесты.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Проект Bazel {#bazel-project}

Настройте рабочее пространство Bazel на кэш API удаленного выполнения Tuist и сервис событий сборки (Build Event Service), чтобы делиться попаданиями в кэш и аналитикой с вашей командой и CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Проект Struo {#struo-project}

<a id="once-project"></a>

Подключите кешируемые скрипты и графы сборки Struo к Tuist для общего кэширования, живой аналитики сборок и тестов, хостинга шардирования тестов и превью приложений.

<.localized_link href="/guides/get-started/struo-project">Start with a Struo project →</.localized_link>
