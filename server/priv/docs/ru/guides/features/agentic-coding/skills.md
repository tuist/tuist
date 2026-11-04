---
{
  "title": "Навыки",
  "titleTemplate": ":title · Агентовое программирование · Возможности · Руководства · Tuist",
  "description": "Готовые навыки, которые агенты-программисты могут использовать для выполнения типичных задач в Tuist, таких как миграция проектов."
}
---

# Навыки

Навыки — это готовые наборы инструкций для выполнения сложных многошаговых задач Tuist. Вместо того чтобы вручную направлять агента через процесс миграции или настройки, вы устанавливаете навык и позволяете агенту выполнить работу.

Если ваш кодовый агент поддерживает плагины, [плагины Tuist](/guides/features/agentic-coding/plugins) устанавливают эти навыки и размещённый сервер Model Context Protocol вместе.

## Доступные навыки

| Навык | Описание |
| --- | --- |
| `migrate` | Мигрирует существующие проекты Xcode в рабочие пространства, сгенерированные Tuist, с проверкой сборки и запуска, сопоставлением внешних зависимостей и контрольными списками миграции. |
| `generated-projects` | Помогает в повседневной работе с рабочими пространствами, сгенерированными Tuist: генерация, команды сборки/тестирования и папки, доступные для сборки. |
| `fix-flaky-tests` | Исправляет нестабильные тесты, анализируя паттерны сбоев из аналитики тестов Tuist, выявляя корневые причины и применяя целенаправленные исправления. |
| `debug-generated-project` | Отлаживает проблемы с проектами, сгенерированными Tuist, воспроизводя сценарий, собирая Tuist из исходного кода при необходимости и определяя, является ли проблема ошибкой, неверной конфигурацией или требует вмешательства команды. |
| `compare-gradle-builds` | Сравнивает два запуска сборки Gradle, чтобы выявить регрессии по длительности, изменения кэша и различия в результатах задач. Можно вызывать с идентификаторами сборок, URL-адресами панели управления или названиями веток. |

## Установка {#installation}

Рекомендуемый способ установки навыков Tuist — через CLI [`skills`](https://github.com/vercel-labs/skills). Он автоматически обнаруживает ваши кодовые агенты и размещает файлы `SKILL.md` в нужном месте.

### Установить все навыки

```bash
npx skills add tuist/agent-skills
```

Интерактивный запрос позволяет выбрать, какие навыки и для каких агентов установить.

### Установить конкретный навык

```bash
npx skills add tuist/agent-skills --skill migrate
```

### Установить для конкретного агента

```bash
npx skills add tuist/agent-skills -a claude-code
```

### Установить глобально

Добавьте флаг `-g`, чтобы установить навыки в домашнюю директорию, сделав их доступными для всех проектов:

```bash
npx skills add tuist/agent-skills -g
```

### Обновить навыки

```bash
npx skills update
```

### Неинтерактивный режим (CI)

```bash
npx skills add tuist/agent-skills --all -y
```

### Ручная установка {#manual}

Если вы предпочитаете не использовать CLI `skills`, вы можете скачать файлы `SKILL.md` напрямую. Установите переменные для нужного навыка и выполните команду `curl` для вашего агента:

```bash
SKILL_NAME=tuist-migrate          # or tuist-generated-projects
SKILL_URL=https://tuist.dev/skills/migrate/SKILL.md  # or .../generated-projects/SKILL.md
```

::: code-group

```bash [Claude Code]
mkdir -p .claude/skills/$SKILL_NAME
curl -o .claude/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Codex]
mkdir -p .codex/skills/$SKILL_NAME
curl -o .codex/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [Amp]
mkdir -p .agents/skills/$SKILL_NAME
curl -o .agents/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

```bash [OpenCode]
mkdir -p .opencode/skills/$SKILL_NAME
curl -o .opencode/skills/$SKILL_NAME/SKILL.md $SKILL_URL
```

:::
