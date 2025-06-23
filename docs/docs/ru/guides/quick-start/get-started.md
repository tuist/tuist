---
title: Начало работы
titleTemplate: :title · Начало · Руководства · Tuist
description: Узнайте, как установить Tuist в вашей среде.
---

# Начало работы {#get-started}

Самый простой способ начать работу с Tuist в любом каталоге или в каталоге вашего Xcode-проекта или workspace:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```

:::

Команда проведет вас по шагам для <LocalizedLink href="/guides/features/projects">создания сгенерированного проекта</LocalizedLink> или интегрирования существующего Xcode-проекта или workspace. Это поможет вам подключить вашу среду к удаленному серверу, предоставляя доступ к таким функциям, как <LocalizedLink href="/guides/features/selective-testing">выборочное тестирование</LocalizedLink>, <LocalizedLink href="/guides/features/previews">предварительные просмотры</LocalizedLink>, и <LocalizedLink href="/guides/features/registry">реестры</LocalizedLink>.

> [!NOTE] MIGRATE AN EXISTING PROJECT
> If you want to migrate an existing project to generated projects to improve the developer experience and take advantage of our <LocalizedLink href="/guides/features/cache">cache</LocalizedLink>, check out our <LocalizedLink href="/guides/features/projects/adoption/migrate/xcode-project">migration guide</LocalizedLink>.
