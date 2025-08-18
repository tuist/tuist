---
{
  "title": "Логирование",
  "titleTemplate": ":title · Интерфейс командной строки (CLI) · Tuist",
  "description": "Узнайте, как включить и настроить логирование в Tuist."
}
---
# Логирование {#logging}

CLI, внутри, логирует сообщение, чтобы помочь вам диагностировать проблемы.

## Поиск проблем с помощью логов {#diagnose-issues-using-logs}

Если вызов команды не дает желаемых результатов, вы можете диагностировать проблему, просмотрев логи. CLI направляет логи в [OSLog](https://developer.apple.com/documentation/os/oslog) и в файловую систему.

При каждом запуске он создает лог файл в `$XDG_STATE_HOME/tuist/logs/{uuid}. og`, где `$XDG_STATE_HOME` принимает значение `~/.local/state`, если переменная окружения не установлена.

По умолчанию, CLI выводит путь логов когда исполнение неожиданно завершается. Если это не так, то логи могут быть найдены в указанном выше пути (то есть в самом последнем лог-файле).

> [!ВАЖНО]
> Конфиденциальная информация не редактируется, поэтому будьте острожно при публикации логов.

### Непрерывная интеграция (CI) {#diagnose-issues-using-logs-ci}

В CI, где окружения являются одноразовыми, вам может потребоваться настроить ваш конвейер CI для экспорта логов Tuist.
Экспорт артефактов является общей возможностью CI-служб, и их конфигурации зависят от используемой вами службы.
Например, в GitHub Actions вы можете использовать действие `actions/upload-artifact` для выгрузки логов в качестве артефакта:

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
