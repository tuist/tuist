---
title: Структура директорий
titleTemplate: :title · Проекты · Разработка · Руководства · Tuist
description: Узнайте о структуре Tuist проектов и как их организовать.
---

# Структура директорий {#directory-structure}

Хотя Tuist-проекты обычно используются для замены проектов Xcode, они не ограничиваются этим вариантом использования. Tuist-проекты также используются для создания других типов проектов, таких как SPM-пакеты, шаблоны, плагины и задачи. В этом документе описывается структура Tuist-проектов и как их организовать. В последующих разделах мы рассмотрим как задавать шаблоны, плагины и задачи.

## Стандартные Tuist-проекты {#standard-tuist-projects}

Tuist-проекты - **наиболее распространенный тип проектов, созданный Туистом.** Они используются для создания приложений, фреймворков и библиотек. В отличие от проектов Xcode, Tuist-проекты заданы с помощью Swift, что делает их более гибкими и простыми для поддержки. Tuist-проекты также более декларативны, что облегчает их чтение и понимание того что они задают. Следующая структура показывает типичный Tuist-проект, который генерирует проект Xcode:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Каталог Tuist:** Этот каталог имеет две цели. Во-первых, он сигнализирует **где находится корень проекта**. Это позволяет создавать пути относительно корня проекта, а также запускать команды Tuist из любого каталога проекта. Во-вторых, это контейнер для следующих файлов:
  - **ProjectDescriptionHelpers:** Этот каталог содержит Swift-код, доступный во всех манифест-файлах. Манифест-файлы могут использовать `import ProjectDescriptionHelpers`, чтобы использовать код, указанный в этой директории. Использование общего кода полезно для избежания дублирования и обеспечения постоянства в рамках проектов.
  - **Package.swift:** Этот файл содержит зависимости Swift Package для Tuist, для интеграции их в Xcode проекты и для Xcode targets (как [CocoaPods](https://cococapods)) которые настраиваемы и оптимизируемы. Узнайте больше <LocalizedLink href="/guides/develop/projects/dependencies">здесь</LocalizedLink>.

- **Корневой каталог**: Корневой каталог проекта, который также содержит папку `Tuist`.
  - <LocalizedLink href="/guides/develop/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink> Этот файл содержит конфигурацию Tuist, разделяемую всеми проектами, рабочими пространствами и окружениями. Например, он может использоваться для отключения автоматической генерации схем или для определения `deployment target` проектов.
  - <LocalizedLink href="/guides/develop/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink> This manifest represents an Xcode workspace. It's used to group other projects and can also add additional files and schemes.
  - <LocalizedLink href="/guides/develop/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink> This manifest represents an Xcode project. It's used to define the targets that are part of the project, and their dependencies.

When interacting with the above project, commands expect to find either a `Workspace.swift` or a `Project.swift` file in the working directory or the directory indicated via the `--path` flag. The manifest should be in a directory or subdirectory of a directory containing a `Tuist` directory, which represents the root of the project.

> [!TIP]
> Xcode workspaces allowed splitting projects into multiple Xcode projects to reduce the likelihood of merge conflicts. If that's what you were using workspaces for, you don't need them in Tuist. Tuist auto-generates a workspace containing a project and its dependencies' projects.

## Swift Package <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist also supports SPM package projects. If you are working on an SPM package, you shouldn't need to update anything. Tuist automatically picks up on your root `Package.swift` and all the features of Tuist work as if it was a `Project.swift` manifest.

To get started, run `tuist install` and `tuist generate` in your SPM package. Your project should now have all the same schemes and files that you would see in the vanilla Xcode SPM integration. However, now you can also run <LocalizedLink href="/guides/develop/build/cache">`tuist cache`</LocalizedLink> and have majority of your SPM dependencies and modules precompiled, making subsequent builds extremely fast.
