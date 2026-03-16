---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Migracja pakietu Swift {#migrate-a-swift-package}

Swift Package Manager pojawił się jako menedżer zależności dla kodu Swift, który
nieoczekiwanie rozwiązał problem zarządzania projektami i obsługi innych języków
programowania, takich jak Objective-C. Ponieważ narzędzie to zostało
zaprojektowane z myślą o innym celu, korzystanie z niego do zarządzania
projektami na dużą skalę może stanowić wyzwanie, ponieważ brakuje mu
elastyczności, wydajności i mocy, które zapewnia Tuist. Zostało to dobrze
uchwycone w artykule [Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2),
który zawiera poniższą tabelę porównującą wydajność Swift Package Manager i
natywnych projektów Xcode:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Często spotykamy programistów i organizacje, które kwestionują potrzebę
stosowania Tuist, uważając, że Swift Package Manager może pełnić podobną rolę w
zarządzaniu projektami. Niektórzy decydują się na migrację, by później zdać
sobie sprawę, że komfort pracy programistów znacznie się pogorszył. Na przykład
ponowne indeksowanie po zmianie nazwy pliku może zająć nawet 15 sekund. 15
sekund!

**Nie jest pewne, czy Apple uczyni Swift Package Manager menedżerem projektów
stworzonym z myślą o skalowalności.** Nie widzimy jednak żadnych oznak, że tak
się dzieje. W rzeczywistości obserwujemy coś zupełnie przeciwnego. Podejmują
decyzje inspirowane Xcode, takie jak dążenie do wygody poprzez konfiguracje
domyślne, co
<LocalizedLink href="/guides/features/projects/cost-of-convenience">jak zapewne
wiesz,</LocalizedLink> jest źródłem komplikacji w przypadku skalowalności.
Uważamy, że Apple musiałoby powrócić do podstawowych zasad i ponownie
przeanalizować niektóre decyzje, które miały sens jako menedżer zależności, ale
nie jako menedżer projektów, na przykład użycie języka kompilowanego jako
interfejsu do definiowania projektów.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist traktuje Swift Package Manager jako menedżera zależności i jest to świetne
narzędzie. Używamy go do rozwiązywania zależności i ich kompilacji. Nie używamy
go do definiowania projektów, ponieważ nie jest do tego przeznaczony.
<!-- -->
:::

## Migracja z Swift Package Manager do Tuist {#migrating-from-swift-package-manager-to-tuist}

Podobieństwa między Swift Package Managerem a Tuistem sprawiają, że proces
migracji jest prosty. Główna różnica polega na tym, że projekty definiuje się
przy użyciu języka DSL Tuista zamiast pliku ` `Package.swift``.

Najpierw utwórz plik `Project.swift` obok pliku `Package.swift`. Plik
`Project.swift` będzie zawierał definicję Twojego projektu. Oto przykład pliku
`Project.swift`, który definiuje projekt z jednym celem:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Kilka uwag:

- **Opis projektu**: Zamiast używać `Opis pakietu`, będziesz używać `Opis
  projektu`.
- **Projekt:** Zamiast eksportować instancję pakietu `` , będziesz eksportować
  instancję projektu `` .
- **Język Xcode:** Elementy podstawowe używane do definiowania projektu
  naśladują język Xcode, dlatego znajdziesz tam między innymi schematy, cele i
  fazy kompilacji.

Następnie utwórz plik `Tuist.swift` o następującej treści:

```swift
import ProjectDescription

let tuist = Tuist()
```

Plik `Tuist.swift` zawiera konfigurację projektu, a jego ścieżka służy jako
odniesienie do określenia katalogu głównego projektu. Aby dowiedzieć się więcej
o strukturze projektów Tuist, zapoznaj się z dokumentem
<LocalizedLink href="/guides/features/projects/directory-structure">struktura
katalogów</LocalizedLink>.

## Edycja projektu {#editing-the-project}

Możesz użyć <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>, aby edytować projekt w Xcode. Polecenie wygeneruje
projekt Xcode, który możesz otworzyć i rozpocząć pracę.

```bash
tuist edit
```

W zależności od wielkości projektu możesz rozważyć użycie go jednorazowo lub
stopniowo. Zalecamy rozpoczęcie od małego projektu, aby zapoznać się z DSL i
przebiegiem pracy. Nasza rada to zawsze zaczynać od najbardziej zależnego celu i
pracować aż do celu najwyższego poziomu.
