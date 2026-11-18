---
{
  "title": "Начало работы",
  "titleTemplate": ":title · Руководства · Tuist",
  "description": "Выберите подход Tuist, соответствующий текущему способу сборки вашего приложения: Xcode, сгенерированные проекты Xcode, Gradle, Elixir, Rust, Bazel или Once."
}
---
# Начало работы {#get-started}

Выберите путь, соответствующий тому, как ваше приложение собирается сейчас. Каждый из них описывает, что нужно установить, как включить кэширование, аналитику и возможности тестирования, а также как проверить настройку от начала до конца. Вы можете внедрять их по отдельности или комбинировать, если выпускаете обновления для нескольких платформ.

Большинство путей используют <.localized_link href="/guides/install-tuist">интерфейс командной строки Tuist</.localized_link>. Elixir использует пакет Hex, а Once подключается через свой нативный провайдер Tuist; ни один из них не требует CLI Tuist для интеграции.

## Проект Xcode {#existing-xcode-project}

Сохраните существующий проект или рабочее пространство Xcode и добавляйте возможности Tuist по одной. Генерация проекта не требуется.

<.localized_link href="/guides/get-started/existing-xcode-project">Start with an Xcode project →</.localized_link>

## Генерируемый проект Xcode {#generated-xcode-project}

Позвольте Tuist определять и генерировать ваш проект Xcode из манифестов Swift. Генерируемые проекты сводят сложность модульных проектов Xcode к лаконичному декларативному описанию графа и являются строгим требованием для <.localized_link href="/guides/features/cache/module-cache">кэша модулей</.localized_link> и <.localized_link href="/guides/features/selective-testing/generated-xcode-project">выборочного тестирования</.localized_link>.

<.localized_link href="/guides/get-started/generated-xcode-project">Start with a generated project →</.localized_link>

## Проект Gradle {#gradle-project}

Подключите проект Gradle к удалённому кэшу Tuist, аналитике сборок и аналитике тестов через плагин Gradle `dev.tuist`.

<.localized_link href="/guides/get-started/gradle-project">Start with a Gradle project →</.localized_link>

## Проект Elixir {#elixir-project}

Подключите проект Elixir к аналитике сборок и тестов Tuist, обнаружению нестабильных тестов и шардированию тестов через пакет Hex `tuist_ex`.

<.localized_link href="/guides/get-started/elixir-project">Start with an Elixir project →</.localized_link>

## Проект Rust {#rust-project}

Запускайте Cargo через CLI Tuist, чтобы отправлять данные о сборках и результатах отдельных тестов, включая doctests, и исследовать нестабильные тесты.

<.localized_link href="/guides/get-started/rust-project">Start with a Rust project →</.localized_link>

## Проект Bazel {#bazel-project}

Направьте рабочее пространство Bazel на кэш Remote Execution API и сервис Build Event Service от Tuist, чтобы делиться попаданиями в кэш и аналитикой между вашей командой и CI.

<.localized_link href="/guides/get-started/bazel-project">Start with a Bazel project →</.localized_link>

## Проект Once {#once-project}

Подключите кешируемые скрипты и графы сборки Once к Tuist для общего кэширования, оперативной аналитики сборок и тестов, хостинга шардирования тестов и предварительного просмотра приложений.

<.localized_link href="/guides/get-started/once-project">Start with a Once project →</.localized_link>
