---
{
  "title": "Сервер",
  "titleTemplate": ":title · Код · Участники · Tuist",
  "description": "Внесите свой вклад в развитие сервера Tuist."
}
---
# Сервер {#server}

Исходный код: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Для чего он нужен {#what-it-is-for}

Сервер обеспечивает работу серверных функций Tuist, таких как аутентификация, управление аккаунтами и проектами, хранение кэша, аналитика, превью, реестр и интеграции (GitHub, Slack и SSO). Это приложение на Phoenix/Elixir с использованием Postgres и ClickHouse.

## Как внести вклад {#how-to-contribute}

Для внесения вклада в сервер необходимо подписать CLA (`server/CLA.md`).

### Локальная настройка {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

Откройте `http://localhost:8080` в браузере. В режиме разработки страница входа содержит кнопку **Войти как тестовый пользователь**, которая выполняет вход с помощью готового аккаунта (`tuistrocks@tuist.dev` / `tuistrocks`).

> [!NOTE]
> Разработчики из основной команды загружают секреты для разработки из 1Password через fnox — `mise run dev` оборачивает сервер в `fnox exec` (см. `server/fnox.toml`). Внешним контрибьюторам доступ к 1Password не требуется; сервер работает локально без него. Интеграции OAuth, Stripe и другие сторонние сервисы будут отключены, но основной функционал будет работать.

### Локальное тестирование Helm {#local-helm-testing}

Вы можете развернуть полный стек на своей машине с помощью [kind](https://kind.sigs.k8s.io/) и включенных задач mise. Это собирает образы Docker локально, создает кластер kind, устанавливает чарт и автоматически настраивает перенаправление портов для всех сервисов:

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**Требования:** `docker`, `kind`, `helm` и `kubectl`.

### Тесты и форматирование {#tests-and-formatting}

- Тесты: `mix test`
- Форматирование: `mise run format`
