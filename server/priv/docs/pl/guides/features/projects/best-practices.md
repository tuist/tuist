---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# Dobre praktyki {#best-practices}

Przez lata pracy z różnymi zespołami i projektami zidentyfikowaliśmy zestaw
dobrych praktyk, które zalecamy przestrzegać podczas pracy z projektami Tuist i
Xcode. Praktyki te nie są obowiązkowe, ale mogą pomóc w ustrukturyzowaniu
projektów w sposób ułatwiający ich utrzymanie i skalowanie.

## Xcode {#xcode}

### Niepożądane wzorce {#discouraged-patterns}

#### Konfiguracje do modelowania środowisk aplikacji {#configurations-to-model-remote-environments}

Wiele organizacji używa konfiguracji kompilacji do modelowania różnych środowisk
(np. `Debug-Production` lub `Release-Canary`), takie podejście ma niestety pewne
wady:

- **Niespójności:** Jeśli wśród zależności występują niespójności konfiguracji,
  kompilator może użyć niewłaściwej konfiguracji dla niektórych targetów.
- **Złożoność:** Projekty mogą skończyć z długą listą konfiguracji, które są
  trudne w zrozumieniu i utrzymaniu.

Konfiguracje kompilatora zostały zaprojektowane w celu ucieleśnienia różnych
ustawień kompilacji, a projekty rzadko potrzebują ich więcej niż `Debug` i
`Release`. Potrzebę modelowania różnych środowisk można zrealizować na inne
sposoby:

- **W buildach Debug:** Można dołączyć wszystkie konfiguracje, które powinny być
  dostępne w fazie rozwoju w aplikacji (np. endpointy) i podmieniać je w trakcie
  pracy aplikacji. Wybór może odbywać się za pomocą zmiennych środowiskowych
  ustawianych w scheme lub za pomocą interfejsu użytkownika w aplikacji.
- **W wersjach Release:** W przypadku wersji release można dołączyć tylko
  konfigurację, z którą powiązana jest wersja produkcyjna aplikacji
  wykorzystując dyrektywy kompilatora.

::: info Niestandardowe konfiguracje
<!-- -->
Chociaż Tuist obsługuje niestandardowe konfiguracje i upraszcza zarządzanie nimi
w porównaniu do zwykłych projektów Xcode, jeśli konfiguracje nie są spójne dla
grafu zależności, otrzymasz ostrzeżenia . Pomaga to zapewnić niezawodność
kompilacji i zapobiega problemom związanym z konfiguracją.
<!-- -->
:::

## Wygenerowane projekty

### Foldery do zbudowania

W wersji Tuist 4.62.0 dodano obsługę **folderów do kompilacji**
(zsynchronizowanych grup Xcode), funkcji wprowadzonej w Xcode 16 w celu
ograniczenia konfliktów.

Podczas gdy wzorce wieloznaczne Tuist (np. `Sources/**/*.swift`) już eliminują
konflikty scalania w generowanych projektach, foldery kompilowalne oferują
dodatkowe korzyści:

- **Automatyczna synchronizacja**: Struktura projektu pozostaje zsynchronizowana
  z systemem plików - nie jest wymagana regeneracja projektu podczas dodawania
  lub usuwania plików
- **Przyjazne dla sztucznej inteligencji**: Asystenci i agenci AI mogą
  modyfikować kodu źródłowy bez uruchamiania regeneracji projektu
- **Prostsza konfiguracja**: Definiowanie ścieżek folderów zamiast zarządzania
  jawnymi listami plików

Zalecamy stosowanie folderów do kompilacji zamiast tradycyjnych referencji
`Target.sources` i `Target.resources` w celu usprawnienia procesu wywarzania
oprogramowania.

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Zależności

#### Wymuszanie rozwiązanych wersji na CI

Podczas instalowania zależności Swift Package Manager w CI zalecamy użycie flagi
`--force-resolved-versions`, aby zapewnić deterministyczne kompilacje:

```bash
tuist install --force-resolved-versions
```

Flaga ta zapewnia, że zależności są rozwiązywane przy użyciu dokładnych wersji
przypiętych w `Package.resolved`, eliminując problemy spowodowane
niedeterminizmem w rozwiązywaniu zależności. Jest to szczególnie ważne w CI,
gdzie powtarzalne kompilacje są krytyczne.
