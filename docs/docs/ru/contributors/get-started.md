---
title: Get started
titleTemplate: :title · Участникам проекта · Tuist
description: Get started contributing to Tuist by following this guide.
---

# Get started {#get-started}

If you have experience building apps for Apple platforms, like iOS, adding code to Tuist shouldn’t be much different. There are two differences compared to developing apps that are worth mentioning:

- **The interactions with CLIs happen through the terminal.** The user executes Tuist, which performs the desired task, and then returns successfully or with a status code. During the execution, the user can be notified by sending output information to the standard output and standard error. There are no gestures, or graphical interactions, just the user intent.

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

If you needed to edit the project, for example to add dependencies or adjust targets, you can use the <LocalizedLink href="/guides/develop/projects/editing">`tuist edit` command</LocalizedLink>. Команда редко используется, но лучше помнить о том, что она существует.

## Запуск Tuist {#run-tuist}

### Из Xcode {#from-xcode}

Чтобы запустить `tuist` из сгенерированного проекта Xcode - отредактируйте схему `tuist` и установите аргументы, которые вы хотели бы передать в команду. For example, to run the `tuist generate` command, you can set the arguments to `generate --no-open` to prevent the project from opening after the generation.

![An example of a scheme configuration to run the generate command with Tuist](/images/contributors/scheme-arguments.png)

You'll also have to set the working directory to the root of the project being generated. You can do that either by using the `--path` argument, which all the commands accept, or configuring the working directory in the scheme as shown below:

![An example of how to set the working directory to run Tuist](/images/contributors/scheme-working-directory.png)

> [!WARNING] PROJECTDESCRIPTION COMPILATION
> The `tuist` CLI depends on the `ProjectDescription` framework's presence in the built products directory. If `tuist` fails to run because it can't find the `ProjectDescription` framework, build the `Tuist-Workspace` scheme first.

### From the terminal {#from-the-terminal}

You can run `tuist` using Tuist itself through its `run` command:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Alternatively, you can also run it through the Swift Package Manager directly:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
