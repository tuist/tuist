---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Znaczniki metadanych {#metadata-tags}

W miarę jak projekty stają się coraz większe i bardziej złożone, praca z całą
bazą kodu na raz może stać się nieefektywna. Tuist udostępnia tagi metadanych
**** jako sposób na zorganizowanie celów w logiczne grupy i skupienie się na
określonych częściach projektu podczas jego rozwoju.

## Czym są tagi metadanych? {#what-are-metadata-tags}

Znaczniki metadanych to etykiety łańcuchowe, które można dołączyć do obiektów
docelowych w projekcie. Służą one jako znaczniki, które pozwalają na:

- **Grupowanie powiązanych obiektów docelowych** - oznaczanie obiektów
  docelowych należących do tej samej funkcji, zespołu lub warstwy
  architektonicznej.
- **Skoncentruj swój obszar roboczy** - Generuj projekty, które zawierają tylko
  cele z określonymi tagami.
- **Zoptymalizuj swój przepływ pracy** - Pracuj nad określonymi funkcjami bez
  ładowania niepowiązanych części bazy kodu.
- **Wybierz cele do zachowania jako źródła** - Wybierz grupę celów, które chcesz
  zachować jako źródła podczas buforowania.

Tagi są definiowane za pomocą właściwości `metadata` na obiektach docelowych i
są przechowywane jako tablica ciągów znaków.

## Definiowanie znaczników metadanych {#defining-metadata-tags}

Tagi można dodawać do dowolnego celu w manifeście projektu:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## Koncentracja na oznaczonych celach {#focusing-on-tagged-targets}

Po oznaczeniu celów można użyć polecenia `tuist generate`, aby utworzyć
skoncentrowany projekt, który zawiera tylko określone cele:

### Skupienie według tagu

Użyj tagu `:`, aby wygenerować projekt ze wszystkimi celami pasującymi do
określonego tagu:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Skupienie według nazwy

Możesz także skupić się na konkretnych celach według nazwy:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Jak działa fokus

Kiedy skupiasz się na celach:

1. **Uwzględnione cele** - Cele pasujące do zapytania są uwzględnione w
   wygenerowanym projekcie.
2. **Zależności** - Wszystkie zależności skupionych celów są automatycznie
   uwzględniane.
3. **Cele testowe** - uwzględniono cele testowe dla skoncentrowanych celów.
4. **Wykluczenie** - Wszystkie inne cele są wykluczone z obszaru roboczego.

Oznacza to, że otrzymujesz mniejszy, łatwiejszy w zarządzaniu obszar roboczy,
który zawiera tylko to, czego potrzebujesz do pracy nad swoją funkcją.

## Konwencje nazewnictwa znaczników {#tag-naming-conventions}

Chociaż jako tagu można użyć dowolnego ciągu znaków, przestrzeganie spójnej
konwencji nazewnictwa pomaga utrzymać porządek w tagach:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

Używanie prefiksów takich jak `feature:`, `team:`, lub `layer:` ułatwia
zrozumienie celu każdego tagu i uniknięcie konfliktów nazewnictwa.

## Używanie tagów z pomocnikami opisu projektu {#using-tags-with-helpers}

Możesz wykorzystać
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>, aby ustandaryzować sposób stosowania tagów w całym
projekcie:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

Następnie użyj go w swoich manifestach:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## Korzyści z używania znaczników metadanych {#benefits}

### Ulepszone doświadczenie deweloperskie

Skupiając się na określonych częściach projektu, możesz:

- **Zmniejsz rozmiar projektu Xcode** - Pracuj z mniejszymi projektami, które
  można szybciej otwierać i nawigować.
- **Przyspiesz kompilacje** - kompiluj tylko to, czego potrzebujesz do bieżącej
  pracy
- **Poprawa koncentracji** - Unikanie rozpraszania uwagi przez niepowiązany kod
- **Optymalizacja indeksowania** - Xcode indeksuje mniej kodu, dzięki czemu
  autouzupełnianie jest szybsze.

### Lepsza organizacja projektu

Tagi zapewniają elastyczny sposób organizacji bazy kodu:

- **Wiele wymiarów** - Oznaczaj cele według funkcji, zespołu, warstwy, platformy
  lub dowolnego innego wymiaru.
- **Brak zmian strukturalnych** - Dodanie struktury organizacyjnej bez zmiany
  układu katalogu
- **Zagadnienia przekrojowe** - Pojedynczy cel może należeć do wielu grup
  logicznych.

### Integracja z buforowaniem

Znaczniki metadanych płynnie współpracują z funkcjami buforowania
<LocalizedLink href="/guides/features/cache">Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Dobre praktyki {#best-practices}

1. **Zacznij od prostego** - Zacznij od pojedynczego wymiaru tagowania (np.
   cech) i rozszerzaj go w razie potrzeby.
2. **Zachowaj spójność** - Używaj tych samych konwencji nazewnictwa we
   wszystkich manifestach.
3. **Dokumentuj swoje tagi** - Zachowaj listę dostępnych tagów i ich znaczeń w
   dokumentacji projektu.
4. **Korzystanie z modułów pomocniczych** - Wykorzystanie modułów pomocniczych
   opisu projektu do standaryzacji stosowania znaczników
5. **Przeglądaj okresowo** - W miarę rozwoju projektu przeglądaj i aktualizuj
   strategię tagowania.

## Powiązane funkcje {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Udostępnianie kodu</LocalizedLink> - Używaj narzędzi pomocniczych opisu projektu, aby
  ustandaryzować użycie tagów
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - Połącz
  znaczniki z buforowaniem w celu uzyskania optymalnej wydajności kompilacji.
- <LocalizedLink href="/guides/features/selective-testing">Testowanie selektywne</LocalizedLink> - Uruchamianie testów tylko dla zmienionych celów
