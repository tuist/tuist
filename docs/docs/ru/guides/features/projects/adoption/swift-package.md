---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Использование Tuist с пакетом Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist поддерживает использование `Package.swift` в качестве DSL для ваших
проектов и преобразует цели пакета в родной проект и цели Xcode.

> [!ВНИМАНИЕ] Цель этой функции - предоставить разработчикам простой способ
> оценить влияние внедрения Tuist в их Swift-пакеты. Поэтому мы не планируем
> поддерживать весь спектр возможностей менеджера пакетов Swift, а также
> привносить в мир пакетов все уникальные возможности Tuist, такие как
> <LocalizedLink href="/guides/features/projects/code-sharing">помощники
> описания проектов</LocalizedLink>.

> [!ПРИМЕЧАНИЕ] ROOT DIRECTORY Команды Tuist ожидают наличия определенной
> <LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">структуры
> каталогов</LocalizedLink>, корень которой определяется каталогом `Tuist` или
> `.git`.

## Использование Tuist с пакетом Swift {#using-tuist-with-a-swift-package}

Мы будем использовать Tuist с репозиторием [TootSDK
Package](https://github.com/TootSDK/TootSDK), который содержит пакет Swift.
Первое, что нам нужно сделать, - это клонировать репозиторий:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Попав в каталог репозитория, нам нужно установить зависимости Swift Package
Manager:

```bash
tuist install
```

Под капотом `tuist install` использует менеджер пакетов Swift для разрешения и
извлечения зависимостей пакета. После завершения разрешения вы можете
сгенерировать проект:

```bash
tuist generate
```

Вуаля! У вас есть собственный проект Xcode, который вы можете открыть и начать
работать над ним.
