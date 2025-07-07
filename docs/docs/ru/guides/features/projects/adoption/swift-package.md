---
title: Использование Tuist с Swift Package
titleTemplate: :title · Adoption · Projects · Features · Guides · Tuist
description: Узнайте, как использовать Tuist с Swift Package.
---

# Использование Tuist с Swift Package <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist поддерживает использование `Package.swift` в качестве DSL для проектов и преобразует ваши пакетные модули в Xcode проект и модули Xcode.

> [!WARNING]
> Цель этой функции - предоставить разработчикам простой способ оценить влияние внедрения Tuist в их Swift пакеты. Поэтому мы не планируем поддерживать весь спектр возможностей Swift Package Manage, а также переносить в область Swift Package Manager все уникальные возможности Tuist, такие, как <LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>.

> [!NOTE] КОРНЕВОЙ КАТАЛОГ
> Команды Tuist ожидают наличия определенной <LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">структуры папок</LocalizedLink>, корень которой определяется папкой `Tuist` или `.git`.

## Использование Tuist с Swift Package {#using-tuist-with-a-swift-package}

Мы собираемся использовать Tuist с [TootSDK пакетом](https://github.com/TootSDK/TootSDK), который содержит Swift пакет. Первое, что нам нужно сделать, это скопировать репозиторий:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Как закончили клонировать, необходимо установить Swift Package Manager зависимости:

```bash
tuist install
```

Под капотом `tuist install` использует Swift Package Manager для скачивания зависимостей.
После того как установка пакетов будет выполнена, вы сможете сгенерировать проект:

```bash
tuist generate
```

Вуаля! Теперь у вас есть собственный проект Xcode, который вы можете открыть и начать работать над ним.
