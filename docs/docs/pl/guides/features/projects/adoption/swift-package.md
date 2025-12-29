---
{
  "title": "Use Tuist with a Swift Package",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist with a Swift Package."
}
---
# Używanie Tuist z pakietem Swift <Badge type="warning" text="beta" /> {#using-tuist-with-a-swift-package-badge-typewarning-textbeta-}

Tuist obsługuje korzystanie z `Package.swift` jako DSL dla projektów i
konwertuje cele pakietu na natywny projekt Xcode i cele.

::: warning
<!-- -->
Celem tej funkcji jest zapewnienie programistom łatwego sposobu oceny wpływu
przyjęcia Tuist w ich pakietach Swift. W związku z tym nie planujemy obsługiwać
pełnego zakresu funkcji menedżera pakietów Swift ani wprowadzać wszystkich
unikalnych funkcji Tuist, takich jak
<LocalizedLink href="/guides/features/projects/code-sharing">pomocnicy opisu projektu</LocalizedLink> do świata pakietów.
<!-- -->
:::

::: info ROOT DIRECTORY
<!-- -->
Polecenia Tuist oczekują określonej
<LocalizedLink href="/guides/features/projects/directory-structure#standard-tuist-projects"> struktury katalogów</LocalizedLink>, której korzeń jest identyfikowany przez
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

Gdy już znajdziemy się w katalogu repozytorium, musimy zainstalować zależności
Swift Package Manager:

```bash
tuist install
```

Pod maską `tuist install` używa Swift Package Manager do rozwiązywania i
pobierania zależności pakietu. Po zakończeniu rozpoznawania można wygenerować
projekt:

```bash
tuist generate
```

Voila! Masz natywny projekt Xcode, który możesz otworzyć i rozpocząć pracę.
