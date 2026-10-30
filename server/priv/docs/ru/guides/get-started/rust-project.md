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

Tuist работает с вашим существующим проектом Cargo. Вам не нужно добавлять зависимость Rust или изменять способ сборки проекта.

## Подключение проекта

Установите <.localized_link href="/guides/install-tuist">CLI Tuist</.localized_link> и Rust. Создайте проект в дашборде, выбрав **Cargo (Rust)** в качестве системы сборки. Добавьте `tuist.toml` в корень вашего репозитория:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Войдите с помощью `tuist auth login`, затем выполняйте обычные команды Cargo через Tuist. В CI установите для `TUIST_TOKEN` токен проекта. Вы также можете задать `TUIST_PROJECT` вместо добавления файла конфигурации и `TUIST_URL`, если используете самостоятельно размещённый сервер.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Используйте те же аргументы, которые вы обычно передаёте Cargo, включая возможности, тулчейны и фильтры тестов. Cargo сохраняет свой обычный вывод и код завершения, даже если Tuist не может загрузить отчёт.

## Продолжайте использовать Cargo

При включённых [обёртках команд mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) добавьте это в `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Выполните `mise reshim` после добавления обёртки. Затем вы сможете использовать `cargo build`, `cargo check` и `cargo test` как обычно. Mise будет запускать их через Tuist за вас.

> [!TIP] Coding agents
> Это полезно при работе с агентами написания кода: они могут продолжать выполнять `cargo build` и `cargo test`, не вспоминая о необходимости добавления префикса `tuist`.

## Кэш компиляции

`tuist cargo build` автоматически кэширует подходящие листовые библиотеки из реестра локально и через удалённый кэш Kura. Дополнительная настройка инструментов или кэша не требуется. Кэш находится в экспериментальной стадии и пока не покрывает все компиляции или повторное использование при разных путях checkout. См. <.localized_link href="/guides/features/cache/rust">кэш Rust</.localized_link> для получения информации о поддерживаемых компиляциях, аутентификации и проверке повторного использования.

## Аналитика сборок

Откройте раздел **Сборки** в дашборде, чтобы увидеть длительность ваших сборок и сравнить локальные сборки со сборками в CI. Выберите сборку, чтобы найти крейты, компиляция которых заняла больше всего времени, и изучить предупреждения и ошибки.

Время компиляции указывается для крейтов, а не для отдельных исходных файлов. Подробнее о чтении отчёта о сборке см. в <.localized_link href="/guides/features/build-insights/rust">аналитике сборок Rust</.localized_link>.

## Аналитика тестов

Запускайте тесты как обычно:

```sh
tuist cargo test --workspace
```

Откройте раздел **Тесты** в дашборде, чтобы увидеть пройденные, проваленные и проигнорированные тесты, включая doctests. Cargo сообщает длительность наборов тестов, но стабильный libtest не предоставляет время выполнения отдельных тестов.

Чтобы запустить только doctests:

```sh
tuist cargo test --doc
```

Подробнее см. в <.localized_link href="/guides/features/test-insights/rust">аналитике тестов Rust</.localized_link> и <.localized_link href="/guides/features/test-insights/flaky-tests/rust">нестабильных тестах Rust</.localized_link>.
