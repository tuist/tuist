---
title: Редактирование
titleTemplate: :title · Projects · Develop · Guides · Tuist
description: Узнайте, как использовать редактор Tuist, чтобы объявить свой проект, используя возможности системы сборки и редактора Xcode.
---

# Редактирование {#editing}

В отличие от традиционных проектов Xcode или пакетов Swift Packages, где изменения вносятся через интерфейс Xcode, проекты, управляемые Tuist, определяются в коде Swift, содержащемся в **манифест файлах**.
Если вы знакомы с Swift Packages и файлом `Package.swift`,
то подход окажется очень похож.

Вы можете редактировать эти файлы с помощью любого текстового редактора, но мы рекомендуем использовать для этого редактор, предоставляемый Tuist – `tuist edit`.
Редактор создает проект Xcode, содержащий все манифест файлы, и позволяет редактировать и компилировать их.
Благодаря использованию Xcode, вы получаете все преимущества **дополнения кода, подсветки синтаксиса и проверки ошибок**.

## Редактирование проекта {#edit-the-project}

Чтобы отредактировать проект, вы можете выполнить следующую команду в директории проекта Tuist или его поддиректории:

```bash
tuist edit
```

Команда создает проект Xcode в глобальной директории и открывает его в Xcode.
Проект включает в себя директорию `Manifests`, который вы можете собрать, чтобы убедиться, что все ваши манифесты верны.

> [!INFO] GLOB-RESOLVED MANIFESTS
> `tuist edit` resolves the manifests to be included by using the glob `**/{Manifest}.swift` from the project's root directory (the one containing the `Tuist.swift` file). Make sure there's a valid `Tuist.swift` at the root of the project.

## Edit and generate workflow {#edit-and-generate-workflow}

As you might have noticed, the editing can't be done from the generated Xcode project.
That's by design to prevent the generated project from having a dependency on Tuist,
ensuring you can move from Tuist in the future with little effort.

When iterating on a project, we recommend running `tuist edit` from a terminal session to get an Xcode project to edit the project, and use another terminal session to run `tuist generate`.
