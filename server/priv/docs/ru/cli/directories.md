---
{
  "title": "Каталоги",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Узнайте, как Tuist организует каталоги конфигурации, кэша и состояния."
}
---
# Каталоги {#directories}

Tuist организует свои файлы в нескольких каталогах вашей системы, следуя [спецификации базовых каталогов XDG](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html). Это обеспечивает чистый и стандартный способ управления файлами конфигурации, кэша и состояния.

## Поддерживаемые переменные окружения {#supported-environment-variables}

Tuist поддерживает как стандартные переменные XDG, так и варианты с префиксом Tuist. Варианты, специфичные для Tuist (с префиксом `TUIST_`), имеют приоритет, что позволяет настраивать Tuist отдельно от других приложений.

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
- **Plugins**: кэш загруженных и скомпилированных плагинов
- **ProjectDescriptionHelpers**: скомпилированные вспомогательные средства описания проекта
- **Manifests**: кэшированные файлы манифестов
- **Projects**: кэш сгенерированных проектов автоматизации
- **EditProjects**: кэш для команды edit
- **Runs**: данные аналитики запусков тестов и сборок
- **Binaries**: бинарные артефакты сборки (не предназначены для совместного использования между средами)
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

### Каталог состояния {#state-directory}

**Переменные окружения:**
- `TUIST_XDG_STATE_HOME` (имеет приоритет)
- `XDG_STATE_HOME`

**По умолчанию:** `~/.local/state/tuist`

**Используется для:**
- **Sessions**: журналы сеансов и сетевые записи (`sessions/{uuid}/`)
- **Locks**: файлы блокировок аутентификации (`{handle}.sock`)

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

При определении используемого каталога Tuist проверяет переменные окружения в следующем порядке:

1. **Переменная, специфичная для Tuist** (например, `TUIST_XDG_CONFIG_HOME`)
2. **Стандартная переменная XDG** (например, `XDG_CONFIG_HOME`)
3. **Расположение по умолчанию** (например, `~/.config/tuist`)

Это позволяет вам:
- Использовать стандартные переменные XDG для единообразной организации всех ваших приложений
- Переопределять с помощью переменных, специфичных для Tuist, когда нужны отдельные расположения для Tuist
- Полагаться на разумные значения по умолчанию без какой-либо настройки

## Частые сценарии использования {#common-use-cases}

### Изоляция Tuist для каждого проекта {#isolating-tuist-per-project}

Вы можете захотеть изолировать кэш и состояние Tuist для каждого проекта:

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

При отладке проблем вам может понадобиться чистое окружение:

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
