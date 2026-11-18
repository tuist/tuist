---
{
  "title": "Использование Tuist с пакетом Swift",
  "titleTemplate": ":title · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist с пакетом Swift."
}
---
# Использование Tuist со Swift-пакетом <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist поддерживает использование `Package.swift` в качестве DSL для ваших проектов и преобразует цели пакета в нативный проект Xcode с соответствующими целями.

> [!WARNING]
> Цель этой функции — предоставить разработчикам простой способ оценить влияние внедрения Tuist в их Swift-пакеты. Поэтому мы не планируем поддерживать весь набор функций Swift Package Manager или переносить все уникальные возможности Tuist, такие как <.localized_link href="/guides/features/projects/code-sharing">хелперы описания проекта</.localized_link>, в мир пакетов.


> [!NOTE]
> **Корневая директория**
>
> Команды Tuist ожидают определённую <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">структуру директорий</.localized_link>, корень которой определяется наличием директории `Tuist` или `.git`.


## Использование Tuist со Swift-пакетом {#using-tuist-with-a-swift-package}

Мы будем использовать Tuist с репозиторием [TootSDK Package](https://github.com/TootSDK/TootSDK), который содержит Swift-пакет. Первое, что нужно сделать, — клонировать репозиторий:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Находясь в директории репозитория, установите зависимости Swift Package Manager:

```bash
tuist install
```

Под капотом `tuist install` использует Swift Package Manager для разрешения и загрузки зависимостей пакета. После завершения разрешения вы можете сгенерировать проект:

```bash
tuist generate
```

Готово! У вас есть нативный проект Xcode, который можно открыть и начать работу.
