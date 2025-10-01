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
значение `~/.local/state`, если переменная окружения не установлена.

По умолчанию CLI выводит путь к журналам, когда выполнение неожиданно
завершается. Если этого не происходит, вы можете найти журналы по указанному
выше пути (т. е. в самом последнем файле журнала).

> [!ВАЖНО] Конфиденциальная информация не редактируется, поэтому будьте
> осторожны при передаче журналов.

### Непрерывная интеграция {#diagnose-issues-using-logs-ci}

В CI, где окружения являются одноразовыми, вам может понадобиться настроить
конвейер CI на экспорт журналов Tuist. Экспорт артефактов - это общая
возможность для всех сервисов CI, и конфигурация зависит от используемого
сервиса. Например, в GitHub Actions вы можете использовать действие
`actions/upload-artifact` для загрузки журналов в качестве артефакта:

```yaml
name: Node CI

on: [push]

env:
  XDG_STATE_HOME: /tmp

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
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```
