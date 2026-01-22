---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Регистрация {#logging}

CLI регистрирует сообщения внутренне, чтобы помочь вам диагностировать проблемы.

## Диагностика проблем с помощью журналов {#diagnose-issues-using-logs}

Если вызов команды не дает желаемых результатов, вы можете диагностировать
проблему, просматривая журналы. CLI пересылает журналы в
[OSLog](https://developer.apple.com/documentation/os/oslog) и файловую систему.

При каждом запуске создается файл журнала по адресу
`$XDG_STATE_HOME/tuist/logs/{uuid}.log`, где `$XDG_STATE_HOME` принимает
значение `~/.local/state`, если переменная среды не установлена. Вы также можете
использовать `$TUIST_XDG_STATE_HOME` для установки каталога состояния,
специфичного для Tuist, который имеет приоритет над `$XDG_STATE_HOME`.

::: tip
<!-- -->
Узнайте больше об организации каталогов Tuist и о том, как настроить
пользовательские каталоги, в <LocalizedLink href="/cli/directories">документации
по каталогам</LocalizedLink>.
<!-- -->
:::

По умолчанию CLI выводит путь к журналам, когда выполнение завершается
неожиданно. Если этого не происходит, вы можете найти журналы по указанному выше
пути (т. е. самый последний файл журнала).

::: warning
<!-- -->
Конфиденциальная информация не редактируется, поэтому будьте осторожны при
обмене журналами.
<!-- -->
:::

### Непрерывная интеграция {#diagnose-issues-using-logs-ci}

В CI, где среды являются одноразовыми, вы можете настроить конвейер CI для
экспорта журналов Tuist. Экспорт артефактов является общей функцией для всех
служб CI, и настройка зависит от используемой службы. Например, в GitHub Actions
вы можете использовать действие `actions/upload-artifact` для загрузки журналов
в качестве артефакта:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### Отладка демона кэша {#cache-daemon-debugging}

Для отладки проблем, связанных с кэшем, Tuist регистрирует операции кэш-демона с
помощью `os_log` с подсистемой `dev.tuist.cache`. Вы можете просматривать эти
журналы в режиме реального времени с помощью:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Эти журналы также можно просмотреть в Console.app, отфильтровав подсистему
`dev.tuist.cache`. Это предоставляет подробную информацию об операциях кэша,
которая может помочь в диагностике проблем с загрузкой, скачиванием и связью
кэша.
