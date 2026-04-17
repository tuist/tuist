---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Справочники {#directories}

Tuist организует свои файлы в нескольких каталогах в вашей системе, следуя
спецификации [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
Это обеспечивает чистый, стандартный способ управления файлами конфигурации,
кэша и состояния.

## Поддерживаемые переменные окружения {#supported-environment-variables}

Tuist поддерживает как стандартные переменные XDG, так и специфические для Tuist
варианты с префиксом. Варианты, специфичные для Tuist (с префиксом `TUIST_`),
имеют приоритет, что позволяет настраивать Tuist отдельно от других приложений.

### Каталог конфигурации {#configuration-directory}

**Переменные среды:**
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

**Переменные среды:**
- `TUIST_XDG_CACHE_HOME` (имеет приоритет)
- `XDG_CACHE_HOME`

**По умолчанию:** `~/.cache/tuist`

**Используется для:**
- **Плагины**: Загруженный и скомпилированный кэш плагинов
- **ProjectDescriptionHelpers**: Скомпилированные помощники для описания
  проектов
- **Манифесты**: Кэшированные файлы манифеста
- **Проекты**: Сгенерированный кэш проекта автоматизации
- **EditProjects**: Кэш для команды редактирования
- **Запуски**: тестирование и создание аналитических данных.
- **Бинарные файлы**: Двоичные файлы артефактов сборки (не подлежат совместному
  использованию в разных средах)
- **Выборочные тесты**: Кэш для выборочного тестирования

**Пример:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Государственный справочник {#state-directory}

**Переменные среды:**
- `TUIST_XDG_STATE_HOME` (имеет приоритет)
- `XDG_STATE_HOME`

**По умолчанию:** `~/.local/state/tuist`

**Используется для:**
- **Журналы**: Файлы журналов (`logs/{uuid}.log`)
- **Замки**: Файлы блокировки аутентификации (`{ дескриптор}.sock`)

**Пример:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Порядок старшинства {#precedence-order}

Определяя, какой каталог использовать, Tuist проверяет переменные окружения в
следующем порядке:

1. **Специфическая для Туиста переменная** (например, `TUIST_XDG_CONFIG_HOME`).
2. **Стандартная переменная XDG** (например, `XDG_CONFIG_HOME`).
3. **Расположение по умолчанию** (например, `~/.config/tuist`).

Это позволит вам:
- Используйте стандартные переменные XDG для последовательной организации всех
  ваших приложений
- Переопределите переменные, специфичные для Tuist, если вам нужны разные места
  для Tuist
- Полагайтесь на разумные значения по умолчанию без какой-либо настройки

## Общие случаи использования {#common-use-cases}

### Изолирование Туиста для каждого проекта {#isolating-tuist-per-project}

Возможно, вы захотите изолировать кэш и состояние Tuist для каждого проекта:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### Среды CI/CD {#ci-cd-environments}

В среде CI вы можете захотеть использовать временные каталоги:

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

При отладке проблем вам может понадобиться чистый лист:

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
