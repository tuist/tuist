---
{
  "title": "Проект на Rust",
  "titleTemplate": ":title · Начало работы · Руководства · Tuist",
  "description": "Подключите проект на Rust к Tuist, чтобы отслеживать сборки и тесты, включая документационные тесты, и находить нестабильные тесты."
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
- CLI Tuist и аккаунт Tuist.

Tuist работает с вашим существующим проектом Cargo. Вам не нужно добавлять зависимость Rust или менять способ сборки проекта.

## Подключение проекта

Установите <.localized_link href="/guides/install-tuist">CLI Tuist</.localized_link> и Rust. Создайте проект в дашборде, выбрав **Cargo (Rust)** в качестве системы сборки. Добавьте `tuist.toml` в корень вашего репозитория:

```toml
project = "account/project"
# url = "https://your-tuist-server.example.com"
```

Выполните вход с помощью `tuist auth login`, затем запускайте обычные команды Cargo через Tuist. В CI установите для `TUIST_TOKEN` токен проекта. Вы также можете задать `TUIST_PROJECT` вместо добавления файла конфигурации и `TUIST_URL`, если используете самостоятельно размещенный сервер.

```sh
tuist cargo build --workspace
tuist cargo check --all-targets
tuist cargo test --workspace
```

Используйте те же аргументы, которые вы обычно передаете Cargo, включая возможности (features), тулчейны и фильтры тестов. Cargo сохраняет свой обычный вывод и код выхода, даже если Tuist не может загрузить отчет.

## Продолжайте использовать Cargo

При включенных [обертках команд mise](https://mise.jdx.dev/dev-tools/shims.html#command-wrappers) добавьте следующее в `mise.toml`:

```toml
[wrappers.cargo]
command = "tuist"
args = ["cargo"]
```

Выполните `mise reshim` после добавления обертки. Затем вы сможете как обычно использовать `cargo build`, `cargo check` и `cargo test`. Mise будет запускать их через Tuist за вас.

> [!TIP] Coding agents
> Это полезно при работе с агентами написания кода: они могут продолжать выполнять `cargo build` и `cargo test`, не нуждаясь в напоминании добавить префикс `tuist`.

## Кэш компиляции

`tuist cargo build` автоматически кэширует подходящие библиотеки-листья из реестра локально и через удаленный кэш Kura. Дополнительная настройка инструментов или кэша не требуется. Кэш находится в экспериментальной стадии и пока не охватывает все компиляции или повторное использование при разных путях checkout. См. <.localized_link href="/guides/features/cache/rust">кэш Rust</.localized_link> для получения информации о поддерживаемых компиляциях, аутентификации и способах проверки повторного использования.

## Аналитика сборок

Откройте раздел **Сборки** в дашборде, чтобы увидеть длительность ваших сборок и сравнить локальные сборки со сборками в CI. Выберите сборку, чтобы найти крейты, компиляция которых заняла больше всего времени, и изучить предупреждения и ошибки.

Время компиляции указывается для крейтов, а не для отдельных исходных файлов. См. <.localized_link href="/guides/features/build-insights/rust">аналитику сборок Rust</.localized_link> для получения дополнительной информации о чтении отчета о сборке.

## Аналитика тестов

Запускайте тесты как обычно:

```sh
tuist cargo test --workspace
```

Откройте раздел **Тесты** в дашборде, чтобы увидеть пройденные, упавшие и проигнорированные тесты, включая doctests. Cargo сообщает длительность наборов тестов, но стабильная версия libtest не предоставляет время выполнения отдельных тестов.

Чтобы запустить только doctests:

```sh
tuist cargo test --doc
```

Подробнее читайте в разделах <.localized_link href="/guides/features/test-insights/rust">аналитика тестов Rust</.localized_link> и <.localized_link href="/guides/features/test-insights/flaky-tests/rust">нестабильные тесты Rust</.localized_link>.
