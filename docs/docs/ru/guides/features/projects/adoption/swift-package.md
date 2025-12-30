---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Использование Tuist с Swift Package <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist поддерживает использование `Package.swift` в качестве DSL для проектов и
преобразует ваши пакетные модули в Xcode-проект и модули Xcode.

::: warning
<!-- -->
Цель этой функции – предоставить разработчикам простой способ оценить влияние
внедрения Tuist в их Swift-пакеты. Поэтому мы не планируем поддерживать весь
спектр возможностей Swift Package Manager, а также переносить в область Swift
Package Manager все уникальные возможности Tuist, такие как
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>.
<!-- -->
:::

::: info КОРНЕВОЙ КАТАЛОГ
<!-- -->
Команды Tuist ожидают наличия определенной
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">структуры папок</LocalizedLink>, корень которой определяется папкой `Tuist` или `.git`.
<!-- -->
:::

## Использование Tuist с Swift Package {#using-tuist-with-a-swift-package}

Мы собираемся использовать Tuist с [TootSDK
пакетом](https://github.com/TootSDK/TootSDK), который содержит Swift-пакет.
Первое, что нам нужно сделать, это скопировать репозиторий:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

После перехода в каталог репозитория необходимо установить зависимости Swift
Package Manager:

```bash
tuist install
```

Под капотом `tuist install`использует Swift Package Manager для скачивания
зависимостей. После того, как установка пакетов будет выполнена, вы сможете
сгенерировать проект:

```bash
tuist generate
```

Вуаля! Теперь у вас есть собственный Xcode-проект, который вы можете открыть и
начать работать над ним.
