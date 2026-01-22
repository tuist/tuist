---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Каталоги {#directories}

Tuist организует свои файлы в нескольких каталогах вашей системы в соответствии
со спецификацией [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
Это обеспечивает чистый, стандартный способ управления файлами конфигурации,
кэша и состояния.

## Поддерживаемые переменные окружения {#supported-environment-variables}

Tuist поддерживает как стандартные переменные XDG, так и специфичные для Tuist
варианты с префиксами. Специфичные для Tuist варианты (с префиксами `TUIST_`)
имеют приоритет, что позволяет настраивать Tuist отдельно от других приложений.

### Каталог конфигурации {#configuration-directory}

**Переменные окружения:**
- `TUIST_XDG_CONFIG_HOME` (имеет приоритет)
- `XDG_CONFIG_HOME`

**По умолчанию:** `~/.config/tuist`

**Используется для:**
- Учетные данные сервера (`credentials/{host}.json`)

**Пример:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Каталог кэша {#cache-directory}

**Переменные окружения:**
- `TUIST_XDG_CACHE_HOME` (имеет приоритет)
- `XDG_CACHE_HOME`

**По умолчанию:** `~/.cache/tuist`

**Используется для:**
- **Плагины**: Загруженный и скомпилированный кэш плагинов
- **ProjectDescriptionHelpers**: Скомпилированные помощники для описания проекта
- **Манифесты**: Кэшированные файлы манифестов
- **Проекты**: Сгенерированный кэш проекта автоматизации
- **EditProjects**: Кэш для команды редактирования
- **Запуск**: тестирование и сбор аналитических данных о запуске
- **Бинарные файлы**: создание бинарных файлов артефактов (не могут
  использоваться в разных средах)
- **SelectiveTests**: кэш выборочного тестирования

**Пример:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Справочник штатов {#state-directory}

**Переменные окружения:**
- `TUIST_XDG_STATE_HOME` (имеет приоритет)
- `XDG_STATE_HOME`

**По умолчанию:** `~/.local/state/tuist`

**Используется для:**
- **Журналы**: файлы журналов (`logs/{uuid}.log`)
- **Блокировки**: Файлы блокировки аутентификации (` дескриптор.sock`)

**Пример:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Порядок приоритета {#precedence-order}

При определении, какой каталог использовать, Tuist проверяет переменные
окружения в следующем порядке:

1. **Переменная, специфичная для Tuist** (например, `TUIST_XDG_CONFIG_HOME`)
2. **Стандартная переменная XDG** (например, `XDG_CONFIG_HOME`)
3. **По умолчанию расположение** (например, `~/.config/tuist`)

Это позволяет вам:
- Используйте стандартные переменные XDG для последовательной организации всех
  ваших приложений.
- Переопределите с помощью переменных Tuist, если вам нужны разные
  местоположения для Tuist.
- Полагайтесь на разумные настройки по умолчанию без какой-либо конфигурации.

## Типичные случаи использования {#common-use-cases}

### Изолирование Tuist по проектам {#isolating-tuist-per-project}

Возможно, вам захочется изолировать кэш и состояние Tuist для каждого проекта:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### Среды CI/CD {#ci-cd-environments}

В средах CI вы можете использовать временные каталоги:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### Отладка с изолированными каталогами {#debugging-with-isolated-directories}

При отладке проблем может понадобиться «чистый лист»:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
