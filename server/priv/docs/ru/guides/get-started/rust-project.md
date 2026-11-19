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
- CLI Tuist и учётная запись Tuist.

Tuist работает с вашим существующим проектом Cargo. Вам не нужно добавлять зависимость Rust или менять способ сборки проекта.

## Подключите проект

Установите <.localized_link href="/guides/install-tuist">CLI Tuist</.localized_link> и Rust. Создайте проект в панели управления, выбрав **Cargo (Rust)** в качестве системы сборки. Затем добавьте проект в корневой файл `Cargo.toml` рабочего пространства:

```toml
[workspace.metadata.tuist]
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Cargo игнорирует таблицы `metadata`, поэтому это не влияет на сборку проекта. Для одного крейта без таблицы `[workspace]` используйте вместо неё `[package.metadata.tuist]`. Таблица принимает те же настройки, что и файл `tuist.toml`, который можно использовать вместо неё, например если в репозитории есть проекты для других систем сборки. Если присутствуют оба варианта, приоритет у `tuist.toml`.

Войдите с помощью `tuist auth login`, затем выполняйте обычные команды Cargo через Tuist. В CI аутентифицируйтесь через OIDC-идентичность вашего провайдера CI или задайте `TUIST_TOKEN` как <.localized_link href="/guides/server/authentication#account-tokens">токен учётной записи</.localized_link>. Также можно задать `TUIST_PROJECT` вместо добавления файла конфигурации и `TUIST_URL`, если вы используете самостоятельно размещённый сервер.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Используйте те же аргументы, которые вы обычно передаёте Cargo, включая возможности, тулчейны и фильтры тестов. Cargo сохраняет свой обычный вывод и код выхода, даже если Tuist не может загрузить отчёт.

## Продолжайте писать Cargo

При включённых [обёртках команд mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) добавьте следующее в `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Выполните `mise reshim` после добавления обёртки. Затем можно использовать `cargo build`, `cargo check` и `cargo test` как обычно. Mise запускает их через Tuist за вас.

> [!TIP] Coding agents
> Это полезно при работе с агентами для написания кода: они могут продолжать выполнять `cargo build` и `cargo test`, не нуждаясь в напоминании добавить префикс `tuist`.

## Кэш компиляции

`tuist cargo build` автоматически кэширует подходящие компиляции, зависимости и запуски скриптов сборки локально и через удалённый кэш Kura. Дополнительная настройка инструментов или кэша не требуется. Кэш экспериментальный, протестирован на Mac с Apple Silicon и пока покрывает не все компиляции. Подробнее о поддерживаемых компиляциях, аутентификации и проверке повторного использования см. в разделе <.localized_link href="/guides/features/cache/rust">кэш Rust</.localized_link>.

## Аналитика сборок

Откройте раздел **Сборки** в панели управления, чтобы увидеть длительность сборок и сравнить локальные сборки со сборками в CI. Выберите сборку, чтобы найти крейты с самым долгим временем компиляции и изучить предупреждения и ошибки.

Время компилятора указано для крейтов, а не для отдельных исходных файлов. Подробнее о чтении отчёта о сборке см. в разделе <.localized_link href="/guides/features/build-insights/rust">Аналитика сборок для Rust</.localized_link>.

## Аналитика тестов

Запускайте тесты как обычно:

```sh
tuist cargo test --workspace
```

Откройте раздел **Тесты** в панели управления, чтобы увидеть пройденные, упавшие и проигнорированные тесты, включая doctests. Cargo сообщает длительность наборов тестов, но стабильный libtest не предоставляет время выполнения отдельных тестов.

Чтобы запустить только doctests:

```sh
tuist cargo test --doc
```

Подробнее см. в разделах <.localized_link href="/guides/features/test-insights/rust">Аналитика тестов для Rust</.localized_link> и <.localized_link href="/guides/features/test-insights/flaky-tests/rust">Нестабильные тесты в Rust</.localized_link>.

## Товарные знаки {#trademarks}

Rust и Cargo являются товарными знаками фонда Rust Foundation. Tuist не связан и не одобрен проектом Rust или фондом Rust Foundation. Логотип Rust в этих руководствах © Rust Foundation, используется по лицензии [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) и отображается одним цветом, соответствующим теме страницы.
