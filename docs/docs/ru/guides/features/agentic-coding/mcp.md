---
title: Протокол контекста модели (MCP)
titleTemplate: :title · AI · Guides · Tuist
description: Узнайте, как использовать MCP Tuist сервер, чтобы иметь языковый интерфейс для разработки приложений.
---

# Протокол контекста модели (MCP)

[Протокол контекста модели (MCP)](https://www.claudemcp.com) — стандарт, предложенный [Claude](https://claude.ai) для LLM взаимодействия со средами разработки.
Вы можете думать об этом как об USB-C в LLM.
Like shipping containers, which made cargo and transportation more interoperable,
or protocols like TCP, which decoupled the application layer from the transport layer,
MCP makes LLM-powered applications such as [Claude](https://claude.ai/) and editors like [Zed](https://zed.dev) or [Cursor](https://www.cursor.com) interoperable with other domains.

Tuist предоставляет локальный сервер через собственный CLI, чтобы вы могли взаимодействовать с вашим **окружением разработки приложений**.
Подключившись к клиентским приложениям, вы можете использовать язык для взаимодействия с вашими проектами.

На этой странице вы узнаете о том, как настроить его и о его возможностях.

> [!NOTE]
> Tuist MCP сервер использует последние проекты в Xcode как источник правды для проектов, с которыми вы хотите взаимодействовать.

## Настройка

Tuist provides automated setup commands for popular MCP-compatible clients. Simply run the appropriate command for your client:

### [Claude](https://claude.ai)

For [Claude desktop](https://claude.ai/download), run:

```bash
tuist mcp setup claude
```

Alternatively, can manually edit the file at `~/Library/Application\ Support/Claude/claude_desktop_config.json`, and add the Tuist MCP server:

### [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

For Claude Code, run:

```bash
tuist mcp setup claude-code
```

This will configure the same file as Claude desktop.

### [Cursor](https://www.cursor.com)

For Cursor IDE, you can configure it globally or locally:

```bash
# Global configuration
tuist mcp setup cursor --global

# Local configuration (in current project)
tuist mcp setup cursor

# Custom path configuration
tuist mcp setup cursor --path /path/to/project
```

### [Zed](https://zed.dev)

For Zed editor, you can also configure it globally or locally:

```bash
# Global configuration
tuist mcp setup zed --global

# Local configuration (in current project)
tuist mcp setup zed

# Custom path configuration
tuist mcp setup zed --path /path/to/project
```

### [VS Code](https://code.visualstudio.com)

For VS Code with MCP extension, configure it globally or locally:

```bash
# Global configuration
tuist mcp setup vscode --global

# Local configuration (in current project)
tuist mcp setup vscode

# Custom path configuration
tuist mcp setup vscode --path /path/to/project
```

### Manual Configuration

If you prefer to configure manually or are using a different MCP client, add the Tuist MCP server to your client's configuration:

:::code-group

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
      "args": ["x", "tuist@latest", "--", "tuist", "mcp", "start"] // Или tuist@x.y.z, чтобы установить версию
    }
  }
}
```

:::

## Возможности

В следующих разделах вы узнаете о возможностях Tuist MCP сервера.

### Ресурсы

#### Недавние проекты и рабочие области

Tuist ведет запись проектов Xcode и рабочих областей, с которыми вы недавно работали, предоставляя приложениям доступ к графикам зависимостей для получения выводов. Вы можете запросить эти данные для получения подробной информации о структуре вашего проекта и его связях, таких как:

- Каковы прямые и переходные зависимости конкретного таргета?
- Какой таргет имеет большинство исходных файлов, и сколько он включает?
- Каковы все статические продукты (например, статические библиотеки или фреймворки) в графе?
- Можете ли вы перечислить все таргеты, отсортированные по алфавиту, вместе с их именами и типами продуктов (например, приложение, фреймворк, модульный тест)?
- Какие таргеты зависят от конкретного фреймворка или внешней зависимости.
- Каково общее количество исходных файлов по всем таргетам проекта?
- Существуют ли циклические зависимости между таргетами, и если да, то где?
- Какие таргеты используют определенный ресурс (например, изображение или файл plist)?
- Что такое цепочка зависимостей в графе, и какие таргеты вовлечены?
- Можешь показать все тестовые таргеты и связанные с ними приложения или фреймворки?
- Какие таргеты имеют самое длинное время сборки в зависимости от недавних взаимодействий?
- Чем отличаются зависимости между двумя конкретными таргетами?
- Есть ли в проекте неиспользуемые исходные файлы или ресурсы?
- Какие таргеты имеют общие зависимости и каковы они?

С помощью Tuist, вы можете прогрузиться в свои проекты Xcode как никогда раньше, что облегчает понимание, оптимизацию и управление даже самыми сложными установками!
