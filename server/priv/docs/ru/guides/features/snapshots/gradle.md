---
{
  "title": "Gradle",
  "titleTemplate": ":title · Снимки · Возможности · Руководства · Tuist",
  "description": "Делайте снимки каждого превью Compose или загружайте записи Paparazzi и Roborazzi с помощью плагина Tuist для Gradle."
}
---
# Снимки Gradle {#gradle-snapshots}

> [!IMPORTANT]
> **Требования**
>
> - Снимки включены для вашей учетной записи. Сейчас доступ предоставляется только по приглашению: [свяжитесь с нами](mailto:contact@tuist.dev) или напишите нам в [Slack-сообществе](https://slack.tuist.dev), чтобы запросить доступ.
> - <.localized_link href="/guides/install-gradle-plugin">Плагин Tuist для Gradle</.localized_link>.
> - [Paparazzi](https://github.com/cashapp/paparazzi) или [Roborazzi](https://github.com/takahirom/roborazzi) в модулях, для которых вы делаете снимки.

Плагин Tuist для Gradle загружает изображения, которые записывают Paparazzi и Roborazzi, а Tuist сравнивает их с <.localized_link href="/guides/features/snapshots#how-it-works">базовой версией</.localized_link>. В модулях, использующих Paparazzi, плагин также генерирует тест, который отображает каждый Compose `@Preview`, поэтому вам не нужно писать тесты снимков вручную.

## Настройка {#set-up}

Включите снимки в вашем `settings.gradle.kts`:

```kotlin
tuist {
    snapshots {
        enabled = true
        set = "android-phone" // Defaults to the Gradle project's path.
    }
}
```

## Запуск {#run}

В CI `./gradlew test` отображает превью и загружает их, а сборка завершается ошибкой, если они изменились и никто не утвердил изменения. Локальные запуски ничего не загружают, потому что это привело бы к загрузке незафиксированных изменений. Передайте `-Ptuist.snapshots=false`, чтобы отключить загрузку в CI.

Задачи записи Paparazzi и Roborazzi, такие как `recordPaparazziDebug`, всегда выполняют загрузку, когда снимки включены.

## Опции {#options}

Блок `snapshots` принимает следующие опции:

- `enabled`: загружаются ли снимки. По умолчанию `false`.
- `set`: набор, в пределах которого сравниваются сборки. По умолчанию используется путь проекта Gradle.
- `directory`: каталог с изображениями для загрузки относительно проекта Gradle. По умолчанию используется каталог, куда записывает сгенерированный тест превью или библиотека снимков.
- `failOnChanges`: завершается ли сборка ошибкой при изменениях, которые никто не утвердил. По умолчанию `true`.
- `diffThreshold`: доля пикселей от 0 до 1, которая может отличаться, прежде чем изображение будет считаться измененным. По умолчанию `0`.
- `previews { generateTests }`: генерируется ли тест превью Compose. По умолчанию `true`.
- `previews { packageTrees }`: пакеты, сканируемые на наличие превью. По умолчанию используется пространство имен Android.
- `previews { includePrivatePreviews }`: отображаются ли также приватные функции `@Preview`. По умолчанию `false`.
- `previews { theme }`: тема Android, в которой отображаются превью. По умолчанию используется тема Paparazzi.
