---
{
  "title": "Использование Tuist с Swift Package",
  "titleTemplate": ":title · Внедрение · Проекты · Возможности · Руководства · Tuist",
  "description": "Узнайте, как использовать Tuist с Swift Package."
}
---
# Использование Tuist с Swift-пакетом <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist поддерживает использование `Package.swift` в качестве DSL для ваших проектов и преобразует цели вашего пакета в нативный проект Xcode и его цели.

> [!WARNING]
> Цель этой возможности — дать разработчикам простой способ оценить влияние внедрения Tuist в их Swift-пакеты. Поэтому мы не планируем поддерживать весь спектр возможностей Swift Package Manager и переносить все уникальные функции Tuist, такие как <.localized_link href="/guides/features/projects/code-sharing">вспомогательные средства для описания проектов</.localized_link>, в мир пакетов.


> [!NOTE]
> **Корневой каталог**
>
> Команды Tuist ожидают определённую <.localized_link href="/guides/features/projects/directory-structure#standard-tuist-projects">структуру каталогов</.localized_link>, корень которой определяется наличием каталога `Tuist` или `.git`.


## Использование Tuist с Swift-пакетом {#using-tuist-with-a-swift-package}

Мы будем использовать Tuist с репозиторием [TootSDK Package](https://github.com/TootSDK/TootSDK), который содержит Swift-пакет. Первое, что нужно сделать, — клонировать репозиторий:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Оказавшись в каталоге репозитория, установите зависимости Swift Package Manager:

```bash
tuist install
```

Под капотом `tuist install` использует Swift Package Manager для разрешения и загрузки зависимостей пакета. После завершения разрешения вы можете сгенерировать проект:

```bash
tuist generate
```

Готово! У вас есть нативный проект Xcode, который можно открыть и начать работу.
