---
{
  "title": "Начало работы",
  "titleTemplate": ":title · Начало работы · Руководства · Tuist",
  "description": "Выберите подход Tuist, соответствующий текущему способу сборки вашего приложения: Xcode, генерируемые проекты Xcode, Gradle, Elixir, Rust или Bazel."
}
---
# Начало работы {#get-started}

Выберите путь, соответствующий тому, как ваше приложение собирается сегодня. В каждом разделе описано, что нужно установить, как включить кэширование, аналитику и возможности тестирования, а также как проверить настройку от начала до конца. Вы можете внедрять их по отдельности или комбинировать, если выпускаете обновления для нескольких платформ.

## Проект Xcode {#existing-xcode-project}

Сохраните существующий проект или рабочее пространство Xcode и добавляйте возможности Tuist по одной. Генерация проекта не требуется.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Сгенерированный проект Xcode {#generated-xcode-project}

Позвольте Tuist определить и сгенерировать ваш проект Xcode из манифестов Swift. Сгенерированные проекты сводят сложность модульных проектов Xcode к лаконичному декларативному описанию графа и являются строгим требованием для <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link> и <.localized_link href="/guides/features/selective-testing/generated-xcode-project">выборочного тестирования</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Проект Gradle {#gradle-project}

Подключите проект Gradle к удалённому кэшу Tuist, аналитике сборок и аналитике тестов через плагин Gradle `dev.tuist`.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Проект Elixir {#elixir-project}

Подключите проект Elixir к аналитике сборок Tuist, аналитике тестов, обнаружению нестабильных тестов и шардированию тестов через пакет Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Проект Rust {#rust-project}

Запускайте Cargo через CLI Tuist, чтобы отправлять данные о сборках и результатах отдельных тестов, включая doctests, и исследовать нестабильные тесты.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Проект Bazel {#bazel-project}

Направьте рабочее пространство Bazel на кэш Remote Execution API и сервис Build Event Service от Tuist, чтобы делиться попаданиями в кэш и аналитикой между вашей командой и CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

Прежде чем приступать к любому из этих вариантов, <.localized_link href="/guides/install-tuist">установите интерфейс командной строки Tuist</.localized_link>. Проекты Elixir — исключение: им достаточно пакета Hex.
