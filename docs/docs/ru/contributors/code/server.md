---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# Сервер {#server}

Источник:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Для чего это нужно {#what-it-is-for}

Сервер обеспечивает работу серверных функций Tuist, таких как аутентификация,
учетные записи и проекты, хранение кэша, аналитика, предварительный просмотр,
реестр и интеграции (GitHub, Slack и SSO). Это приложение Phoenix/Elixir с
Postgres и ClickHouse.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB устарела и будет удалена. На данный момент, если она вам нужна для
локальной настройки или миграции, воспользуйтесь [документацией по установке
TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/).
<!-- -->
:::

## Как внести свой вклад {#how-to-contribute}

Для внесения изменений на сервер необходимо подписать CLA (`server/CLA.md`).

### Настройте локально {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!ПРИМЕЧАНИЕ] Разработчики-партнеры загружают зашифрованные секретные ключи с
> `priv/secrets/dev.key`. Внешние участники не будут иметь этот ключ, и это
> нормально. Сервер по-прежнему работает локально с `TUIST_SECRET_KEY_BASE`, но
> OAuth, Stripe и другие интеграции остаются отключенными.

### Тесты и форматирование {#tests-and-formatting}

- Тесты: `mix test`
- Формат: `mise run format`
