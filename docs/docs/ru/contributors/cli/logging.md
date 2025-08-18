---
{
  "title": "Логирование",
  "titleTemplate": ":title · CLI · Contributors · Tuist",
  "description": "Узнайте, как внести вклад в Tuist, проводя ревью на пулл-реквесты"
}
---
# Логирование {#logging}

CLI использует интерфейс [swift-log](https://github.com/apple/swift-log) интерфейс для логирования. Пакет абстрагирует детали реализации логирования, позволяя CLI быть независимым от её исполнения. The logger is dependency-injected using task locals and can be accessed anywhere using:

```bash
Logger.current
```

> [!NOTE]
> Task locals don't propagate the value when using `Dispatch` or detached tasks, so if you use them, you'll need to get it and pass it to the asynchronous operation.

## Что логировать {#what-to-log}

Логи не являются интерфейсом CLI. Они являются инструментом для диагностики проблем по мере их возникновения.
Поэтому чем больше информации вы предоставите, тем лучше.
При создании новых функций поставьте себя на место разработчика, столкнувшегося с неожиданным поведением, и подумайте, какая информация будет ему полезна.
Убедитесь, что вы используете правильный [уровень лога](https://www.swift.org/documentation/server/guides/libraries/log-levels.html). В противном случае разработчики не смогут отфильтровать шум.
