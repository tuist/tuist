---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Ведение журнала {#logging}

CLI ведет внутренний журнал сообщений, чтобы помочь вам диагностировать
проблемы.

## Диагностика проблем с помощью журналов {#diagnose-issues-using-logs}

Если вызов команды не приводит к желаемым результатам, вы можете диагностировать
проблему, просмотрев журналы. CLI направляет журналы в
[OSLog](https://developer.apple.com/documentation/os/oslog) и файловую систему.

При каждом запуске создается файл журнала по адресу
`$XDG_STATE_HOME/tuist/logs/{uuid}.log`, где `$XDG_STATE_HOME` принимает
значение `~/.local/state`, если переменная окружения не установлена. Вы также
можете использовать `$TUIST_XDG_STATE_HOME` для установки каталога состояния,
специфичного для Туиста, который имеет приоритет над `$XDG_STATE_HOME`.

::: tip
<!-- -->
Подробнее об организации каталогов в Tuist и о том, как настроить
пользовательские каталоги, вы можете узнать из документации
<LocalizedLink href="/cli/directories">Directories</LocalizedLink>.
<!-- -->
:::

По умолчанию CLI выводит путь к журналам, когда выполнение неожиданно
завершается. Если этого не происходит, вы можете найти журналы по указанному
выше пути (т. е. в самом последнем файле журнала).

::: warning
<!-- -->
Конфиденциальная информация не редактируется, поэтому будьте осторожны при
передаче журналов.
<!-- -->
:::

### Непрерывная интеграция {#diagnose-issues-using-logs-ci}

В CI, где окружения являются одноразовыми, вы можете захотеть настроить свой
CI-конвейер на экспорт журналов Tuist. Экспорт артефактов - это общая
возможность для всех сервисов CI, и конфигурация зависит от используемого
сервиса. Например, в GitHub Actions вы можете использовать действие
`actions/upload-artifact` для загрузки журналов в качестве артефакта:

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

Для отладки проблем, связанных с кэшем, Tuist регистрирует операции демона кэша
с помощью `os_log` с подсистемой `dev.tuist.cache`. Вы можете транслировать эти
журналы в режиме реального времени, используя:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Эти журналы также можно увидеть в Console.app, отфильтровав их для подсистемы
`dev.tuist.cache`. Это позволяет получить подробную информацию об операциях с
кэшем, что может помочь в диагностике проблем с загрузкой, выгрузкой и связью
кэша.
