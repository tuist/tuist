---
{
  "title": "Плагины",
  "titleTemplate": ":title · Агентная разработка · Возможности · Руководства · Tuist",
  "description": "Установите плагин Tuist для Cursor или независимый от поставщика пакет Agent Plugins."
}
---

# Плагины

Tuist упаковывает навыки агента и размещённый MCP-сервер в виде плагинов, чтобы вы могли установить их вместе. Выберите пакет, соответствующий вашему агенту для написания кода.

## Claude Code

[Маркетплейс Tuist Claude Code](https://github.com/tuist/claude-plugin) предоставляет плагин Tuist для установки с помощью:

```bash
claude plugin marketplace add tuist/claude-plugin
claude plugin install tuist@tuist-plugins
```

Плагин добавляет навыки Tuist и подключает Claude Code к размещённому MCP-серверу.

## Cursor

Установите [плагин Tuist для Cursor](https://github.com/tuist/cursor-plugin) из [маркетплейса Cursor](https://cursor.com/marketplace):

1. Откройте **Customize** на боковой панели Cursor.
2. Найдите **Tuist**.
3. Выберите **Install**, затем укажите, устанавливать ли плагин для текущего проекта или для вашей учётной записи.

Вы также можете ввести `/add-plugin` в Cursor, чтобы открыть тот же процесс установки. Плагин добавляет навыки Tuist и подключает Cursor к размещённому MCP-серверу.

Если ваша организация управляет маркетплейсами Cursor, сначала импортируйте `https://github.com/tuist/cursor-plugin` через **Settings → Plugins → Team Marketplaces → Import Marketplace**.

## Другие агенты для написания кода

[Плагин Tuist Agent](https://github.com/tuist/agent-plugin) следует открытому, независимому от вендора стандарту [Agent Plugins](https://agent-plugins.org/). Укажите совместимому клиенту путь к репозиторию, следуя инструкциям этого клиента по установке или подключению каталогов плагинов:

```bash
git clone https://github.com/tuist/agent-plugin.git
```

Он устанавливает навыки Tuist и регистрирует `https://tuist.dev/mcp` как удалённый MCP-сервер. Для клиентов, которые пока не поддерживают Agent Plugins, установите <.localized_link href="/guides/features/agentic-coding/skills">навыки</.localized_link> или настройте <.localized_link href="/guides/features/agentic-coding/mcp">MCP-сервер</.localized_link> отдельно.

## Аутентификация

Большинство навыков используют интерфейс командной строки Tuist, поэтому выполните аутентификацию один раз, прежде чем разрешать агенту доступ к данным вашего проекта:

```bash
tuist auth login
```

Размещённый MCP-сервер запрашивает вход в систему при необходимости. См. <.localized_link href="/guides/features/agentic-coding/mcp">руководство по MCP</.localized_link> для получения сведений о настройке и аутентификации для конкретного клиента.
