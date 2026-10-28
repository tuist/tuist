---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Understand test-sharding availability for plain Cargo test runs."
}
---
# Сегментирование тестов Rust {#rust-test-sharding}

Tuist не сегментирует обычные запуски `cargo test` и не распределяет скомпилированные тесты между CI-воркерами. Установка переменных окружения shard-plan не влияет на то, какие тесты выполняет Cargo.

Вместо этого запускайте тесты в одном CI-задании:

```sh
tuist cargo test --workspace
```

Cargo управляет локальным параллелизмом тестов, а Tuist сообщает результаты, включая doctests. См. <.localized_link href="/guides/features/test-insights/rust">аналитику тестов Rust</.localized_link> для получения подробной информации о настройке и отчётности.

Вы можете использовать выбор пакетов и фильтры тестов Cargo, чтобы определить, что будет выполняться в каждом задании, но эти задания являются независимыми запусками, а не сегментами, управляемыми Tuist.
