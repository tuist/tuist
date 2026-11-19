---
{
  "title": "Проект на Rust",
  "titleTemplate": ":title · Начало работы · Руководства · Tuist",
  "description": "Подключите проект на Rust к Tuist, чтобы отслеживать сборки и тесты, включая doctests, и находить нестабильные тесты."
}
---
# Проект на Rust {#rust-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/rust-project
```

:::

## Предварительные требования

- Проект на Rust, собранный с помощью Cargo.
- CLI Tuist и учетная запись Tuist.

Tuist работает с вашим существующим проектом Cargo. Вам не нужно добавлять зависимость Rust или изменять способ сборки проекта.

## Подключение проекта

Установите <.localized_link href="/guides/install-tuist">Tuist CLI</.localized_link> и Rust. Создайте проект в панели управления, выбрав **Cargo (Rust)** в качестве системы сборки. Затем добавьте проект в корневой файл `Cargo.toml` рабочего пространства:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo игнорирует таблицы `metadata`, поэтому это не влияет на сборку вашего проекта. Для одного крейта без таблицы `[workspace]` используйте вместо нее `[package.metadata.tuist]`. Таблица принимает те же настройки, что и файл `tuist.toml`, который можно использовать вместо нее, например, если в репозитории есть проекты для других систем сборки. Если существуют оба варианта, приоритет имеет `tuist.toml`.

Выполните вход с помощью `tuist auth login`, затем запускайте обычные команды Cargo через Tuist. В CI аутентифицируйтесь через OIDC-идентичность вашего провайдера CI или установите для `TUIST_TOKEN` значение <.localized_link href="/guides/server/authentication#account-tokens">токена учетной записи</.localized_link>. Вы также можете установить `TUIST_PROJECT` вместо добавления файла конфигурации и `TUIST_URL`, если используете самостоятельно размещенный сервер.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Используйте те же аргументы, которые вы обычно передаете в Cargo, включая возможности, тулчейны и фильтры тестов. Cargo сохраняет свой обычный вывод и код выхода, даже если Tuist не может загрузить отчет.

## Продолжайте использовать Cargo

При включенных [обертках команд mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) добавьте следующее в `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Выполните `mise reshim` после добавления обертки. После этого вы можете использовать `cargo build`, `cargo check` и `cargo test` как обычно. Mise будет запускать их через Tuist за вас.

> [!TIP] Coding agents
> Это полезно при работе с агентами написания кода: они могут продолжать выполнять `cargo build` и `cargo test`, не нуждаясь в напоминании добавить префикс `tuist`.

## Кэш компиляции

`tuist cargo build` автоматически кэширует подходящие компиляции, зависимости и запуски скриптов сборки локально и через удаленный кэш Kura. Дополнительная настройка инструментов или кэша не требуется. Кэш является экспериментальным, проверен на Mac с процессорами Apple silicon и пока не охватывает все компиляции. Подробнее о поддерживаемых компиляциях, аутентификации и проверке повторного использования см. в разделе <.localized_link href="/guides/features/cache/rust">кэш Rust</.localized_link>.

## Аналитика сборок

Откройте раздел **Сборки** в панели управления, чтобы увидеть длительность ваших сборок и сравнить локальные сборки со сборками в CI. Выберите сборку, чтобы найти крейты, компиляция которых заняла больше всего времени, и изучить предупреждения и ошибки.

Время компиляции указывается для крейтов, а не для отдельных исходных файлов. Подробнее о чтении отчета о сборке см. в разделе <.localized_link href="/guides/features/build-insights/rust">Аналитика сборок Rust</.localized_link>.

## Аналитика тестов

Запускайте тесты как обычно:

```sh
tuist cargo test --workspace
```

Откройте раздел **Тесты** в панели управления, чтобы увидеть пройденные, неуспешные и проигнорированные тесты, включая doctests. Cargo сообщает длительность наборов тестов, но стабильная версия libtest не предоставляет время выполнения отдельных тестов.

Чтобы запустить только doctests:

```sh
tuist cargo test --doc
```

Подробнее см. в разделах <.localized_link href="/guides/features/test-insights/rust">Аналитика тестов Rust</.localized_link> и <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Нестабильные тесты в Rust</.localized_link>.

## Товарные знаки {#trademarks}

Rust и Cargo являются товарными знаками фонда Rust Foundation. Tuist не связан с проектом Rust или фондом Rust Foundation и не одобрен ими. Логотип Rust в этих руководствах © фонд Rust Foundation, используется по лицензии [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) и отображается одним цветом, соответствующим теме страницы.
