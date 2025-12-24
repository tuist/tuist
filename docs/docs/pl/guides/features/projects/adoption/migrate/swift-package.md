---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Migracja pakietu Swift {#migrate-a-swift-package}

Swift Package Manager powstał jako menadżer zależności dla kodu Swift, który
nieumyślnie rozwiązał problem zarządzania projektami i obsługi innych języków
programowania, takich jak Objective-C. Ponieważ narzędzie to zostało
zaprojektowane z myślą o innym celu, korzystanie z niego do zarządzania
projektami na dużą skalę może być trudne, ponieważ brakuje mu elastyczności,
wydajności i mocy, które zapewnia Tuist. Zostało to dobrze ujęte w artykule
[Scaling iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2),
który zawiera poniższą tabelę porównującą wydajność Swift Package Manager i
natywnych projektów Xcode:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Często spotykamy się z deweloperami i organizacjami, które kwestionują potrzebę
Tuist, biorąc pod uwagę, że Swift Package Manager może pełnić podobną rolę w
zarządzaniu projektami. Niektórzy decydują się na migrację, aby później zdać
sobie sprawę, że ich doświadczenie programistyczne znacznie się pogorszyło. Na
przykład, zmiana nazwy pliku może zająć do 15 sekund, aby ponownie go
zindeksować. 15 sekund!

**Nie wiadomo, czy Apple uczyni Swift Package Manager wbudowanym menedżerem
projektów na dużą skalę.** Nie widzimy jednak żadnych oznak, że tak się stanie.
W rzeczywistości widzimy coś wręcz przeciwnego. Podejmują decyzje inspirowane
Xcode, takie jak osiągnięcie wygody poprzez niejawne konfiguracje, które
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> jak być może wiesz,</LocalizedLink> są źródłem komplikacji na dużą skalę. Uważamy, że
Apple musiałoby przejść do pierwszych zasad i zrewidować niektóre decyzje, które
miały sens jako menedżer zależności, ale nie jako menedżer projektów, na
przykład użycie skompilowanego języka jako interfejsu do definiowania projektów.

::: tip SPM AS JUST A DEPENDENCY MANAGER
<!-- -->
Tuist traktuje Swift Package Manager jako menedżer zależności i jest to świetny
menedżer. Używamy go do rozwiązywania zależności i ich budowania. Nie używamy go
do definiowania projektów, ponieważ nie jest do tego przeznaczony.
<!-- -->
:::

## Migracja z menedżera pakietów Swift do Tuist {#migrating-from-swift-package-manager-to-tuist}

Podobieństwa między Swift Package Manager i Tuist sprawiają, że proces migracji
jest prosty. Główna różnica polega na tym, że projekty będą definiowane przy
użyciu DSL Tuist zamiast `Package.swift`.

Najpierw utwórz plik `Project.swift` obok pliku `Package.swift`. Plik
`Project.swift` będzie zawierał definicję projektu. Oto przykład pliku
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

Kilka rzeczy, na które warto zwrócić uwagę:

- **ProjectDescription**: Zamiast używać `PackageDescription`, będziesz używać
  `ProjectDescription`.
- **Projekt:** Zamiast eksportować instancję `package`, będziesz eksportować
  instancję `project`.
- **Język Xcode:** Prymitywy, których używasz do definiowania projektu,
  naśladują język Xcode, więc znajdziesz między innymi schematy, cele i fazy
  kompilacji.

Następnie utwórz plik `Tuist.swift` o następującej zawartości:

```swift
import ProjectDescription

let tuist = Tuist()
```

Plik `Tuist.swift` zawiera konfigurację projektu, a jego ścieżka służy jako
odniesienie do określenia katalogu głównego projektu. Więcej informacji na temat
struktury projektów Tuist można znaleźć w dokumencie
<LocalizedLink href="/guides/features/projects/directory-structure">directory structure</LocalizedLink>.

## Edytowanie projektu {#editing-the-project}

Możesz użyć <LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>, aby edytować projekt w Xcode. Polecenie wygeneruje
projekt Xcode, który można otworzyć i rozpocząć pracę.

```bash
tuist edit
```

W zależności od wielkości projektu można rozważyć użycie go w jednym ujęciu lub
przyrostowo. Zalecamy rozpoczęcie od małego projektu, aby zapoznać się z DSL i
przepływem pracy. Radzimy zawsze zaczynać od najbardziej zależnego celu i
pracować aż do celu najwyższego poziomu.
