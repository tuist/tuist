---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Korzystanie z Tuist z pakietem Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist obsługuje pakiet `Package.swift` jako DSL dla Twoich projektów i
konwertuje cele pakietu na natywny projekt Xcode i cele.

::: warning
<!-- -->
Celem tej funkcji jest zapewnienie programistom łatwego sposobu oceny wpływu
wdrożenia Tuist w ich pakietach Swift. Dlatego nie planujemy obsługiwać pełnego
zakresu funkcji Swift Package Manager ani wprowadzać wszystkich unikalnych
funkcji Tuist, takich jak
<LocalizedLink href="/guides/features/projects/code-sharing">pomocniki opisu
projektu</LocalizedLink>, do świata pakietów.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Polecenia Tuist wymagają określonej
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects">struktury
katalogów</LocalizedLink>, której katalog główny jest identyfikowany przez
katalog `Tuist` lub `.git`.
<!-- -->
:::

## Korzystanie z Tuist z pakietem Swift {#using-tuist-with-a-swift-package}

Będziemy używać Tuist z repozytorium [TootSDK
Package](https://github.com/TootSDK/TootSDK), które zawiera pakiet Swift.
Pierwszą rzeczą, którą musimy zrobić, jest sklonowanie repozytorium:

```bash
git clone https://github.com/TootSDK/TootSDK
cd TootSDK
```

Po przejściu do katalogu repozytorium musimy zainstalować zależności Swift
Package Manager:

```bash
tuist install
```

Pod maską `tuist install` używa menedżera pakietów Swift do rozwiązywania i
pobierania zależności pakietu. Po zakończeniu rozwiązywania można wygenerować
projekt:

```bash
tuist generate
```

Voilà! Masz teraz natywny projekt Xcode, który możesz otworzyć i rozpocząć
pracę.
