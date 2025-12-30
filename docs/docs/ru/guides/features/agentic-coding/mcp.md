---
{
  "title": "Model Context Protocol (MCP)",
  "titleTemplate": ":title · Agentic coding · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's MCP server to have a language-based interface for your app development environment."
}
---
# Контекстный протокол модели (MCP)

[Model Context Protocol (MCP)](https://www.claudemcp.com) - это стандарт,
предложенный [Claude](https://claude.ai) для взаимодействия LLM со средами
разработки. Его можно рассматривать как USB-C для LLM. Подобно морским
контейнерам, сделавшим грузы и транспорт более совместимыми, или протоколам
вроде TCP, отделившим прикладной уровень от транспортного, MCP делает приложения
на базе LLM, такие как [Claude](https://claude.ai/), [Claude
Code](https://docs.anthropic.com/en/docs/claude-code), и редакторы вроде
[Zed](https://zed.dev), [Cursor](https://www.cursor.com) или [VS
Code](https://code.visualstudio.com), совместимыми с другими доменами.

Tuist предоставляет локальный сервер через CLI, чтобы вы могли взаимодействовать
с вашей **средой разработки приложений** . Подключив к нему свои клиентские
приложения, вы можете использовать язык для взаимодействия с вашими проектами.

На этой странице вы узнаете о том, как его настроить и о его возможностях.

::: info
<!-- -->
Сервер Tuist MCP использует самые последние проекты Xcode в качестве источника
истины для проектов, с которыми вы хотите взаимодействовать.
<!-- -->
:::

## Установите его

Tuist предоставляет автоматические команды настройки для популярных
MCP-совместимых клиентов. Просто запустите соответствующую команду для вашего
клиента:

### [Клод](https://claude.ai)

Для [Claude desktop](https://claude.ai/download) выполните команду:
```bash
tuist mcp setup claude
```

Это настроит файл по адресу `~/Library/Application
Support/Claude/claude_desktop_config.json`.

### [Код Клода](https://docs.anthropic.com/en/docs/claude-code)

Для кода Клода выполните команду:
```bash
tuist mcp setup claude-code
```

Это позволит настроить тот же файл, что и на рабочем столе Клода.

### [Курсор](https://www.cursor.com)

Для Cursor IDE вы можете настроить его глобально или локально:
```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

Для редактора Zed вы можете настроить его глобально или локально:
```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

Для VS Code с расширением MCP настройте его глобально или локально:
```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Ручная конфигурация

Если вы предпочитаете настраивать вручную или используете другой MCP-клиент,
добавьте сервер Tuist MCP в конфигурацию вашего клиента:

::: code-group

```json [Global Tuist installation (e.g. Homebrew)]
{
  "mcpServers": {
    "tuist": {
      "command": "tuist",
      "args": ["mcp", "start"]
    }
  }
}
```

```json [Mise installation]
{
  "mcpServers": {
    "tuist": {
      "command": "mise",
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Or tuist@x.y.z to fix the version
    }
  }
}
```
<!-- -->
:::

## Возможности

В следующих разделах вы узнаете о возможностях сервера Tuist MCP.

### Ресурсы

#### Последние проекты и рабочие места

Tuist ведет учет проектов и рабочих пространств Xcode, с которыми вы недавно
работали, предоставляя вашему приложению доступ к их графам зависимостей, что
позволяет получить мощную аналитическую информацию. Вы можете запросить эти
данные, чтобы узнать подробности о структуре проекта и взаимосвязях, например:

- Каковы прямые и транзитивные зависимости от конкретной цели?
- Какая цель имеет наибольшее количество исходных файлов и сколько из них она
  включает?
- Какие статические продукты (например, статические библиотеки или фреймворки)
  присутствуют в графе?
- Можете ли вы перечислить все цели, отсортированные по алфавиту, с указанием их
  имен и типов продуктов (например, приложение, фреймворк, модульный тест)?
- Какие цели зависят от конкретного фреймворка или внешних зависимостей?
- Каково общее количество исходных файлов для всех целей в проекте?
- Существуют ли круговые зависимости между целями, и если да, то где?
- Какие цели используют определенный ресурс (например, образ или plist-файл)?
- Какая самая глубокая цепочка зависимостей в графе и какие цели в ней
  задействованы?
- Можете ли вы показать мне все тестовые цели и связанные с ними цели приложений
  или фреймворков?
- Какие цели имеют самое длительное время создания, судя по недавним
  взаимодействиям?
- Каковы различия в зависимостях между двумя конкретными целями?
- Есть ли в проекте неиспользуемые исходные файлы или ресурсы?
- Какие цели имеют общие зависимости и что это за зависимости?

С Tuist вы можете копаться в своих проектах Xcode как никогда раньше, облегчая
понимание, оптимизацию и управление даже самыми сложными установками!
