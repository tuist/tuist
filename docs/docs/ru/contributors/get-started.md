---
title: Начало работы
titleTemplate: :title · Участникам проекта · Tuist
description: Начните вносить свой вклад в Tuist c помощью этого руководства.
---

# Начало работы {#get-started}

Если у вас есть опыт создания приложений для платформ Apple, таких как iOS, добавление кода в Tuist не показаться сильно иным. Есть два отличия, по сравнению с разработкой приложений, которые стоит упомянуть:

- **Взаимодействие с командным интерфейсом происходит через терминал.** Пользователь запускает Tuist, который выполняет желаемую задачу и затем завершается успешно или со статус-кодом. В процессе выполнения пользователь может получать уведомления с помощью отправки выходной информацию в стандартный поток вывода или в стандартный поток ошибок. There are no gestures, or graphical interactions, just the user intent.

- **There’s no runloop that keeps the process alive waiting for input**, like it happens in an iOS app when the app receives system or user events. CLIs run in its process and finishes when the work is done. Asynchronous work can be done using system APIs like [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) or [structured concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency), but need to make sure the process is running while the asynchronous work is being executed. Otherwise, the process will terminate the asynchronous work.

Если у вас нет опыта работы с Swift, мы рекомендуем [официальную документацию Apple](https://docs.swift.org/swift-book/) для ознакомления с языком и наиболее часто используемыми сущностями библиотеки `Foundation`.

## Минимальные требования {#minimum-requirements}

Минимальные требования для внесения вклада в Tuist:

- macOS 14.0+
- Xcode 16.0+

## Настройте проект локально {#set-up-the-project-locally}

Чтобы начать работу над проектом, можно выполнить следующие действия:

- Склонируйте репозиторий выполнив: `git clone git@github.com:tuist/tuist.git`
- [Установите](https://mise.jdx.dev/getting-started.html) Mise, чтобы подготовить среду разработки
- Выполните `mise install` для установки системных зависимостей, необходимых Tuist
- Выполните `tuist install` для установки внешних зависимостей, необходимых Tuist
- (Необязательно) Выполните `tuist auth`, чтобы получить доступ к <LocalizedLink href="/guides/develop/build/cache">Tuist Cache</LocalizedLink>
- Выполните `tuist generate`, чтобы сгенерировать Xcode-проект Tuist с помощью самого Tuist

**После генерации проект откроется автоматически**. Если вам нужно открыть проект снова, без генерации - выполните `open Tuist.xcworkspace` (или используйте Finder).

> [!NOTE] XED .
> Если вы попробуете открыть проект используя `xed .` - он откроет пакет, а не проект созданный Tuist. Мы рекомендуем использовать проект сгенерированный самим Tuist чтобы "прочувствовать плоды собственного труда".

## Редактирование проекта {#edit-the-project}

Если вам необходимо изменить проект, например, для добавления зависимостей или корректировки target, вы можете использовать команду <LocalizedLink href="/guides/develop/projects/editing">`tuist edit`</LocalizedLink>. Команда редко используется, но лучше помнить о том, что она существует.

## Запуск Tuist {#run-tuist}

### Из Xcode {#from-xcode}

Чтобы запустить `tuist` из сгенерированного проекта Xcode - отредактируйте схему `tuist` и установите аргументы, которые вы хотели бы передать в команду. Например, чтобы выполнить команду `tuist generate`, вы можете задать аргументы `generate --no-open`, чтобы проект не открылся автоматически после генерации.

![Пример конфигурации схемы для запуска команды generate с Tuist](/images/contributors/scheme-arguments.png)

Вы также должны установить рабочий каталог в корень генерируемого проекта. Вы можете сделать это либо с помощью аргумента `--path`, который принимается всеми командами, либо с помощью настройки рабочего каталога в схеме, как показано ниже:

![Пример настройки рабочего каталога для запуска Tuist](/images/contributors/scheme-working-directory.png)

> [!WARNING] СБОРКА PROJECTDESCRIPTION
> Работа команды `tuist` зависит от наличия фреймворка `ProjectDescription` в каталоге собранных продуктов. Если `tuist` не может быть выполнена, потому что команда не может найти фреймворк `ProjectDescription`, постройте сначала схему `Tuist-Workspace`.

### Из терминала {#from-the-terminal}

Вы можете выполнить `tuist` с помощью самого Tuist, используя его команду `run`:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Как альтернатива - вы можете запустить его напрямую через Менеджер Пакетов Swift:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
