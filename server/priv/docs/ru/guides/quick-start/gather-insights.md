---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Сбор аналитики {#gather-insights}

Tuist может интегрироваться с сервером, чтобы расширить свои возможности. Одна
из таких возможностей – сбор аналитики о вашем проекте и сборках. Всё, что нужно
– это учётная запись и проект на сервере.

Прежде всего, вам нужно пройти аутентификацию, выполнив команду:

```bash
tuist auth login
```

## Создание проекта {#create-a-project}

Затем вы можете создать проект, выполнив команду:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Скопируйте `my-handle/MyApp`, который представляет собой полный дескриптор
проекта.

## Подключение проектов {#connect-projects}

После создания проекта на сервере вам нужно подключить его к локальному проекту.
Выполните команду `tuist edit` и отредактируйте файл `Tuist.swift`, чтобы
указать полный дескриптор проекта:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Вуаля! Теперь вы можете собирать аналитику о своём проекте и сборках. Выполните
команду `tuist test`, чтобы запустить тесты и отправить результаты на сервер.

> [!NOTE]
> Tuist помещает результаты в локальную очередь и пытается отправить их, не
> блокируя выполнение команды. Поэтому они могут быть отправлены не сразу после
> завершения команды. В CI результаты отправляются немедленно.


![An image that shows a list of runs in the
server](/images/guides/quick-start/runs.png)

Наличие данных о ваших проектах и сборках играет ключевую роль в принятии
обоснованных решений. Tuist продолжит расширять свои возможности, и вы сможете
пользоваться ими без необходимости изменять конфигурацию проекта. Магия, не
правда ли? 🪄
