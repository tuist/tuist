---
title: Логирование
titleTemplate: :title · Интерфейс командной строки (CLI) · Tuist
description: Узнайте, как включить и настроить логирование в Tuist.
---

# Логирование {#logging}

CLI, внутри, логирует сообщение, чтобы помочь вам диагностировать проблемы.

## Поиск проблем с помощью логов {#diagnose-issues-using-logs}

If a command invocation doesn't yield the intended results, you can diagnose the issue by inspecting the logs. The CLI forwards the logs to [OSLog](https://developer.apple.com/documentation/os/oslog) and the file-system.

In every run, it creates a log file at `$XDG_STATE_HOME/tuist/logs/{uuid}.log` where `$XDG_STATE_HOME` takes the value `~/.local/state` if the environment variable is not set.

По умолчанию, CLI выводит путь логов когда исполнение неожиданно завершается. Если это не так, то логи могут быть найдены в указанном выше пути (то есть в самом последнем лог-файле).

> [!ВАЖНО]
> Конфиденциальная информация - не редактируется, поэтому будьте острожно при публикации логов.

### Непрерывная интеграция (CI) {#diagnose-issues-using-logs-ci}

В CI, где окружения сбрасываемы, вы можете захотеть сконфигурировать ваш CI конвейер для экспорта логов Tuist.
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
