---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# Начало работы {#get-started}

Если у вас есть опыт разработки приложений для платформ Apple, таких как iOS,
добавление кода в Tuist не покажется чем-то новым. Однако по сравнению с
созданием обычных приложений есть два отличия, о которых стоит упомянуть:

- **Взаимодействие с CLI происходит через терминал.** Пользователь запускает
  Tuist, который выполняет нужную задачу и завершает работу – успешно или с
  кодом состояния. Во время выполнения пользователю может выводиться информация
  через стандартный вывод или стандартный поток ошибок. Никаких жестов и
  графических элементов – только действия по намерению пользователя.

- **В CLI нет цикла выполнения (runloop), который поддерживает процесс в
  активном состоянии в ожидании ввода**, как это происходит в iOS-приложении,
  когда оно получает системные или пользовательские события. CLI выполняется в
  своём процессе и завершает работу, когда задача выполнена. Асинхронные
  операции можно выполнять с помощью системных API, таких как
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  или [структурированный
  параллелизм](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency),
  но необходимо убедиться, что процесс остаётся активным во время их выполнения.
  В противном случае процесс завершится, прервав выполнение асинхронной задачи.

Если у вас нет опыта работы со Swift, рекомендуем [официальную книгу
Apple](https://docs.swift.org/swift-book/), чтобы познакомиться с языком и
наиболее часто используемыми элементами API фреймворка Foundation.

## Минимальные требования {#minimum-requirements}

Чтобы внести свой вклад в Tuist, минимальными требованиями являются:

- macOS 14.0+
- Xcode 16.3+

## Настройка проекта локально {#set-up-the-project-locally}

Для начала работы над проектом выполните следующие шаги:

- Клонируйте репозиторий, выполнив команду `git clone
  git@github.com:tuist/tuist.git`
- [Установите](https://mise.jdx.dev/getting-started.html) Mise, чтобы
  подготовить среду разработки.
- Выполните команду `mise install`, чтобы установить системные зависимости,
  необходимые для работы Tuist
- Выполните команду `tuist install`, чтобы установить внешние зависимости,
  необходимые для работы Tuist
- (Опционально) Выполните команду `tuist auth login`, чтобы получить доступ к
  <LocalizedLink href="/guides/features/cache">Tuist Cache</LocalizedLink>
- Выполните команду `tuist generate`, чтобы сгенерировать Xcode-проект Tuist с
  помощью самого Tuist

**Сгенерированный проект откроется автоматически**. Если нужно открыть его
снова, не генерируя заново, выполните команду `open Tuist.xcworkspace` (или
откройте через Finder).

::: info XED .
<!-- -->
Если вы попытаетесь открыть проект с помощью команды `xed .`, откроется сам
пакет, а не проект, сгенерированный Tuist. Мы рекомендуем использовать проект,
созданный Tuist, чтобы тестировать инструмент на практике.
<!-- -->
:::

## Редактирование проекта {#edit-the-project}

Если вам нужно изменить проект, например, добавить зависимости или настроить
цели – используйте команду
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`
command</LocalizedLink>. Эта команда применяется редко, но полезно знать, что
она существует.

## Запуск Tuist {#run-tuist}

### Из Xcode {#from-xcode}

Чтобы запустить `tuist`из сгенерированного Xcode-проекта, отредактируйте схему
`tuist` и укажите аргументы, которые нужно передать команде. Например, чтобы
выполнить команду `tuist generate`, можно задать аргументы `generate --no-open`,
чтобы проект не открывался после генерации.

![An example of a scheme configuration to run the generate command with
Tuist](/images/contributors/scheme-arguments.png)

Вам также нужно будет указать в качестве рабочей директории корень создаваемого
проекта. Это можно сделать либо с помощью аргумента `--path`, который
поддерживают все команды, либо настроив рабочую директорию в схеме, как показано
ниже:


![An example of how to set the working directory to run
Tuist](/images/contributors/scheme-working-directory.png)

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
CLI `tuist` зависит от наличия фреймворка `ProjectDescription` в директории
собранных продуктов. Если `tuist` не запускается из-за того, что не может найти
фреймворк `ProjectDescription`, сначала соберите схему `Tuist-Workspace`.
<!-- -->
:::

### Из терминала {#from-the-terminal}

Вы можете запустить `tuist`, используя сам Tuist, с помощью команды `run` :

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Кроме того, вы можете запустить его напрямую через Swift Package Manager:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
