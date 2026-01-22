---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Tagi metadanych {#metadata-tags}

Wraz ze wzrostem rozmiaru i złożoności projektów praca z całym kodem źródłowym
naraz może stać się nieefektywna. Tuist udostępnia tagi metadanych **** , które
pozwalają organizować cele w logiczne grupy i skupiać się na konkretnych
częściach projektu podczas jego tworzenia.

## Czym są tagi metadanych? {#what-are-metadata-tags}

Tagi metadanych to etykiety tekstowe, które można dołączyć do elementów
docelowych w projekcie. Służą one jako znaczniki, które umożliwiają:

- **Grupuj powiązane cele** - Oznaczaj cele, które należą do tej samej funkcji,
  zespołu lub warstwy architektury.
- **Skoncentruj się na swoim obszarze roboczym** - Generuj projekty, które
  zawierają tylko cele z określonymi tagami
- **Zoptymalizuj przepływ pracy** - Pracuj nad konkretnymi funkcjami bez
  ładowania niepowiązanych części kodu źródłowego.
- **Wybierz cele, które chcesz zachować jako źródła** - Wybierz grupę celów,
  które chcesz zachować jako źródła podczas buforowania

Tagi są definiowane przy użyciu właściwości `metadata` w celach i są
przechowywane jako tablica ciągów znaków.

## Definiowanie tagów metadanych {#defining-metadata-tags}

Możesz dodać tagi do dowolnego celu w manifeście projektu:

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

## Skupianie się na oznaczonych celach {#focusing-on-tagged-targets}

Po oznaczeniu celów można użyć polecenia `tuist generate`, aby utworzyć projekt
skupiony, który zawiera tylko określone cele:

### Skup się na tagu

Użyj tagu `:` prefix, aby wygenerować projekt ze wszystkimi celami pasującymi do
określonego tagu:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Skup się na nazwie

Możesz również skupić się na konkretnych celach według nazwy:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Jak działa fokus

Kiedy skupiasz się na celach:

1. **Zawarte cele** - Cele pasujące do Twojego zapytania są zawarte w
   wygenerowanym projekcie.
2. **Zależności** - Wszystkie zależności wybranych celów są automatycznie
   uwzględniane.
3. **Cele testowe** - Cele testowe dla celów, na których skupiono uwagę, są
   zawarte
4. **Wykluczenie** - Wszystkie pozostałe cele są wykluczone z obszaru roboczego.

Oznacza to, że otrzymujesz mniejsze, łatwiejsze w zarządzaniu miejsce pracy,
które zawiera tylko to, czego potrzebujesz do pracy nad swoją funkcją.

## Konwencje nazewnictwa tagów {#tag-naming-conventions}

Chociaż jako tag można użyć dowolnego ciągu znaków, stosowanie spójnych
konwencji nazewniczych pomaga utrzymać porządek w tagach:

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

Używanie przedrostków, takich jak `feature:`, `team:` lub `layer:` ułatwia
zrozumienie przeznaczenia każdego tagu i pozwala uniknąć konfliktów nazw.

## Tagi systemowe {#system-tags}

Tuist używa przedrostka `tuist:` dla tagów zarządzanych przez system. Tagi te są
automatycznie stosowane przez Tuist i mogą być używane w profilach pamięci
podręcznej w celu kierowania do określonych typów generowanych treści.

### Dostępne tagi systemowe

| Tag                 | Opis                                                                                                                                                                                                                                         |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tuist:synthesized` | Stosowane do syntetycznych pakietów docelowych tworzonych przez Tuist do obsługi zasobów w bibliotekach statycznych i frameworkach statycznych. Pakiety te istnieją z powodów historycznych, aby zapewnić dostęp do interfejsów API zasobów. |

### Korzystanie z tagów systemowych z profilami pamięci podręcznej

Możesz używać tagów systemowych w profilach pamięci podręcznej, aby włączać lub
wyłączać syntetyzowane cele:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
Syntetyzowane pakiety docelowe dziedziczą wszystkie tagi z nadrzędnego pakietu
docelowego, a dodatkowo otrzymują tag `tuist:synthesized`. Oznacza to, że jeśli
oznaczysz bibliotekę statyczną tagiem `feature:auth`, jej syntetyzowany pakiet
zasobów będzie zawierał zarówno tagi `feature:auth`, jak i `tuist:synthesized`.
<!-- -->
:::

## Korzystanie z tagów z pomocnikami opisu projektu {#using-tags-with-helpers}

Możesz wykorzystać
<LocalizedLink href="/guides/features/projects/code-sharing">pomocniki opisu
projektu</LocalizedLink>, aby ujednolicić sposób stosowania tagów w całym
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

## Korzyści wynikające z używania tagów metadanych {#benefits}

### Ulepszone środowisko programistyczne

Skupiając się na konkretnych częściach projektu, możesz:

- **Zmniejsz rozmiar projektu Xcode** - Pracuj z mniejszymi projektami, które
  szybciej się otwierają i są łatwiejsze w nawigacji.
- **Przyspiesz kompilacje** - Kompiluj tylko to, co jest potrzebne do bieżącej
  pracy
- **Popraw skupienie** - Unikaj rozpraszania uwagi przez niepowiązany kod
- **Optymalizacja indeksowania** - Xcode indeksuje mniej kodu, dzięki czemu
  autouzupełnianie działa szybciej.

### Lepsza organizacja projektu

Tagi zapewniają elastyczny sposób organizowania kodu źródłowego:

- **Wiele wymiarów** - Oznaczaj cele według funkcji, zespołu, warstwy, platformy
  lub innego wymiaru.
- **Brak zmian strukturalnych** - Dodaj strukturę organizacyjną bez zmiany
  układu katalogów
- **Kwestie przekrojowe** - Pojedynczy cel może należeć do wielu grup
  logicznych.

### Integracja z buforowaniem

Tagi metadanych działają płynnie z funkcjami buforowania
<LocalizedLink href="/guides/features/cache">Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Dobre praktyki {#best-practices}

1. **Zacznij od prostych tagów** - Zacznij od jednego wymiaru tagowania (np.
   cechy) i rozszerzaj go w razie potrzeby.
2. **Zachowaj spójność** - Stosuj te same konwencje nazewnictwa we wszystkich
   manifestach.
3. **Dokumentuj swoje tagi** - Zachowaj listę dostępnych tagów i ich znaczeń w
   dokumentacji swojego projektu.
4. **Korzystaj z pomocy** - Wykorzystaj pomocniki opisujące projekt, aby
   ujednolicić stosowanie tagów.
5. **Regularnie sprawdzaj** - W miarę rozwoju projektu sprawdzaj i aktualizuj
   strategię tagowania.

## Powiązane funkcje {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Udostępnianie
  kodu</LocalizedLink> - Używaj pomocy opisujących projekt, aby ujednolicić
  użycie tagów.
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - Połącz
  tagi z buforowaniem, aby uzyskać optymalną wydajność kompilacji.
- <LocalizedLink href="/guides/features/selective-testing">Testowanie
  selektywne</LocalizedLink> - Przeprowadzaj testy tylko dla zmienionych celów.
