---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Zależności {#dependencies}

Gdy projekt się rozrasta, często dzieli się go na wiele celów, aby dzielić kod,
definiować granice i skrócić czas kompilacji. Wiele celów oznacza definiowanie
zależności między nimi, tworząc wykres zależności typu „ **”**, który może
również obejmować zależności zewnętrzne.

## Wykresy zakodowane w XcodeProj {#xcodeprojcodified-graphs}

Ze względu na konstrukcję Xcode i XcodeProj utrzymanie wykresu zależności może
być żmudnym i podatnym na błędy zadaniem. Oto kilka przykładów problemów, które
mogą się pojawić:

- Ponieważ system kompilacji Xcode umieszcza wszystkie produkty projektu w tym
  samym katalogu w danych pochodnych, cele mogą importować produkty, których nie
  powinny. Kompilacje mogą zakończyć się niepowodzeniem w CI, gdzie częściej
  stosuje się kompilacje czyste, lub później, gdy używana jest inna
  konfiguracja.
- Zależności dynamiczne celów muszą zostać skopiowane do dowolnego katalogu
  należącego do ustawienia kompilacji `LD_RUNPATH_SEARCH_PATHS`. Jeśli tak nie
  jest, cel nie będzie w stanie ich znaleźć w czasie wykonywania. Jest to łatwe
  do zrozumienia i skonfigurowania, gdy graf jest mały, ale staje się problemem
  w miarę jego powiększania się.
- Gdy cel łączy statyczny
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle),
  potrzebuje dodatkowej fazy kompilacji, aby Xcode mógł przetworzyć pakiet i
  wyodrębnić odpowiedni plik binarny dla bieżącej platformy i architektury. Ta
  faza kompilacji nie jest dodawana automatycznie i łatwo o niej zapomnieć.

Powyższe przykłady to tylko kilka z wielu, z którymi zetknęliśmy się na
przestrzeni lat. Wyobraź sobie, że musisz zatrudnić zespół inżynierów, którzy
będą utrzymywać wykres zależności i zapewniać jego poprawność. Albo, co gorsza,
że zawiłości są rozwiązywane w czasie kompilacji przez zamknięty system
kompilacji, którego nie możesz kontrolować ani dostosowywać. Brzmi znajomo?
Takie podejście przyjęła firma Apple w przypadku Xcode i XcodeProj, a Swift
Package Manager je przejął.

Jesteśmy głęboko przekonani, że wykres zależności powinien być **explicit** and
**static** ponieważ tylko wtedy można go **validated** and **optimized**. Dzięki
Tuist możesz skupić się na opisaniu, co od czego zależy, a my zajmiemy się
resztą. Skomplikowane szczegóły i kwestie związane z implementacją są dla Ciebie
abstrakcyjne.

W kolejnych sekcjach dowiesz się, jak zadeklarować zależności w swoim projekcie.

::: tip GRAPH VALIDATION
<!-- -->
Tuist weryfikuje wykres podczas generowania projektu, aby upewnić się, że nie ma
cykli i że wszystkie zależności są prawidłowe. Dzięki temu każdy zespół może
brać udział w rozwijaniu wykresu zależności bez obawy o jego uszkodzenie.
<!-- -->
:::

## Zależności lokalne {#local-dependencies}

Cele mogą zależeć od innych celów w tym samym lub innym projekcie oraz od plików
binarnych. Podczas instancjonowania celu `Target` można przekazać argument
zależności `` z dowolną z następujących opcji:

- `` docelowy: Deklaruje zależność z celem w ramach tego samego projektu.
- `Projekt`: Deklaruje zależność z celem w innym projekcie.
- `Framework`: Deklaruje zależność od binarnego frameworka.
- `Biblioteka`: Deklaruje zależność od biblioteki binarnej.
- `XCFramework`: Deklaruje zależność od pliku binarnego XCFramework.
- `SDK`: Deklaruje zależność od systemowego SDK.
- `XCTest`: Deklaruje zależność od XCTest.

::: info DEPENDENCY CONDITIONS
<!-- -->
Każdy typ zależności akceptuje warunek `opcję`, aby warunkowo połączyć zależność
w oparciu o platformę. Domyślnie łączy zależność dla wszystkich platform
obsługiwanych przez cel.
<!-- -->
:::

## Zależności zewnętrzne {#external-dependencies}

Tuist umożliwia również deklarowanie zewnętrznych zależności w projekcie.

### Pakiety Swift {#swift-packages}

Pakiety Swift są zalecanym sposobem deklarowania zależności w projekcie. Można
je zintegrować za pomocą domyślnego mechanizmu integracji Xcode lub integracji
Tuist opartej na XcodeProj.

#### Integracja Tuist oparta na XcodeProj {#tuists-xcodeprojbased-integration}

Domyślna integracja Xcode, choć najwygodniejsza, nie zapewnia elastyczności i
kontroli wymaganej w przypadku średnich i dużych projektów. Aby temu zaradzić,
Tuist oferuje integrację opartą na XcodeProj, która pozwala zintegrować pakiety
Swift w projekcie przy użyciu celów XcodeProj. Dzięki temu możemy nie tylko
zapewnić większą kontrolę nad integracją, ale także zapewnić jej kompatybilność
z takimi procesami jak
<LocalizedLink href="/guides/features/cache">buforowanie</LocalizedLink> i
<LocalizedLink href="/guides/features/test/selective-testing">selektywne
uruchamianie testów</LocalizedLink>.

Integracja XcodeProj prawdopodobnie zajmie więcej czasu, aby obsługiwać nowe
funkcje pakietu Swift lub obsługiwać więcej konfiguracji pakietów. Jednak logika
mapowania między pakietami Swift a celami XcodeProj jest otwarta i może być
rozwijana przez społeczność. Jest to sprzeczne z domyślną integracją Xcode,
która jest zamknięta i utrzymywana przez Apple.

Aby dodać zewnętrzne zależności, musisz utworzyć plik `Package.swift` w katalogu
`Tuist/` lub w katalogu głównym projektu.

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip PACKAGE SETTINGS
<!-- -->
`Instancja PackageSettings`, zawarta w dyrektywie kompilatora, pozwala
skonfigurować sposób integracji pakietów. Na przykład w powyższym przykładzie
służy ona do zastąpienia domyślnego typu produktu używanego dla pakietów.
Domyślnie nie powinna być potrzebna.
<!-- -->
:::

> [!WAŻNE] NIESTANDARDOWE KONFIGURACJE KOMPILACJI Jeśli projekt wykorzystuje
> niestandardowe konfiguracje kompilacji (inne niż standardowe `Debug` i
> `Release`), należy je określić w `PackageSettings` przy użyciu `baseSettings`.
> Zewnętrzne zależności muszą znać konfiguracje projektu, aby kompilacja
> przebiegła poprawnie. Na przykład:
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> Więcej szczegółów można znaleźć w
> [#8345](https://github.com/tuist/tuist/issues/8345).

`Plik Package.swift` jest jedynie interfejsem służącym do deklarowania
zewnętrznych zależności, niczym więcej. Dlatego nie definiuje się w nim żadnych
celów ani produktów. Po zdefiniowaniu zależności można uruchomić następujące
polecenie, aby je rozwiązać i pobrać do katalogu `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Jak zapewne zauważyłeś, stosujemy podejście podobne do
[CocoaPods](https://cocoapods.org), gdzie rozwiązywanie zależności jest osobnym
poleceniem. Dzięki temu użytkownicy mają kontrolę nad tym, kiedy chcą
rozwiązywać i aktualizować zależności, a także mogą otworzyć Xcode w projekcie i
przygotować go do kompilacji. Uważamy, że w tym obszarze doświadczenia
programistów związane z integracją Apple z menedżerem pakietów Swift pogarszają
się wraz z rozwojem projektu.

Z poziomu celów projektu można następnie odwołać się do tych zależności,
używając typu zależności `TargetDependency.external`:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
Schematy **** nie są automatycznie tworzone dla projektów Swift Package, aby
lista schematów była przejrzysta. Można je utworzyć za pomocą interfejsu
użytkownika Xcode.
<!-- -->
:::

#### Domyślna integracja Xcode {#xcodes-default-integration}

Jeśli chcesz skorzystać z domyślnego mechanizmu integracji Xcode, możesz
przekazać listę `pakietów` podczas instancjonowania projektu:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

Następnie odwołaj się do nich w swoich celach:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

W przypadku makr Swift i wtyczek narzędzi kompilacyjnych należy użyć odpowiednio
typów `.macro` i `.plugin`.

::: warning SPM Build Tool Plugins
<!-- -->
Wtyczki narzędzia SPM build muszą być deklarowane przy użyciu mechanizmu
[domyślnej integracji Xcode](#xcode-s-default-integration), nawet jeśli w
projekcie używasz [integracji opartej na
XcodeProj](#tuist-s-xcodeproj-based-integration) firmy Tuist dla zależności
projektu.
<!-- -->
:::

Praktycznym zastosowaniem wtyczki narzędzia do tworzenia SPM jest sprawdzanie
poprawności kodu podczas fazy kompilacji „Uruchom wtyczki narzędzia do
kompilacji” w Xcode. W manifeście pakietu jest to zdefiniowane w następujący
sposób:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

Aby wygenerować projekt Xcode z nienaruszoną wtyczką narzędzia kompilacji,
należy zadeklarować pakiet w tablicy `packages` manifestu projektu, a następnie
dołączyć pakiet typu `.plugin` do zależności celu.

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Kartagina {#carthage}

Ponieważ [Carthage](https://github.com/carthage/carthage) wyświetla `frameworks`
lub `xcframeworks`, możesz uruchomić `carthage update`, aby wyświetlić
zależności w katalogu `Carthage/Build`, a następnie użyć typu zależności
docelowej `.framework` lub `.xcframework`, aby zadeklarować zależność w swoim
celu. Możesz to zawrzeć w skrypcie, który można uruchomić przed wygenerowaniem
projektu.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Jeśli kompilujesz i testujesz swój projekt za pomocą polecenia „ `”, „xcodebuild
build` ” oraz „ `tuist test` ”, musisz również upewnić się, że zależności
rozwiązane przez Carthage są obecne, uruchamiając polecenie „ `carthage update`
” przed kompilacją lub testowaniem.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) oczekuje, że projekt Xcode zintegruje
zależności. Możesz użyć Tuist do wygenerowania projektu, a następnie uruchomić
`pod install`, aby zintegrować zależności poprzez utworzenie obszaru roboczego
zawierającego Twój projekt i zależności Pods. Możesz to zawrzeć w skrypcie,
który można uruchomić przed wygenerowaniem projektu.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
Zależności CocoaPods nie są kompatybilne z procesami takimi jak `build` lub
`test`, które uruchamiają `xcodebuild` zaraz po wygenerowaniu projektu. Są one
również niekompatybilne z buforowaniem plików binarnych i testowaniem
selektywnym, ponieważ logika fingerprintingu nie uwzględnia zależności Pods.
<!-- -->
:::

## Statyczne lub dynamiczne {#static-or-dynamic}

Frameworki i biblioteki mogą być łączone statycznie lub dynamicznie, **co ma
znaczący wpływ na takie aspekty, jak rozmiar aplikacji i czas uruchamiania**.
Pomimo swojego znaczenia, decyzja ta jest często podejmowana bez większego
zastanowienia.

Ogólna zasada dotycząca **** mówi, że w kompilacjach wydanych należy statycznie
łączyć jak najwięcej elementów, aby uzyskać krótki czas uruchamiania, a w
kompilacjach debugowanych należy dynamicznie łączyć jak najwięcej elementów, aby
uzyskać krótki czas iteracji.

Wyzwaniem związanym ze zmianą między statycznym a dynamicznym łączeniem w grafie
projektu jest to, że w Xcode nie jest to trywialne, ponieważ zmiana ma kaskadowy
wpływ na cały graf (np. biblioteki nie mogą zawierać zasobów, statyczne
frameworki nie muszą być osadzane). Firma Apple próbowała rozwiązać ten problem
za pomocą rozwiązań kompilacyjnych, takich jak automatyczny wybór między
statycznym a dynamicznym łączeniem w Swift Package Manager lub [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Dodaje to jednak nowe zmienne dynamiczne do wykresu kompilacji, wprowadzając
nowe źródła niedeterminizmu i potencjalnie powodując, że niektóre funkcje, takie
jak Swift Previews, które opierają się na wykresie kompilacji, stają się
zawodne.

Na szczęście Tuist koncepcyjnie kompresuje złożoność związaną z przechodzeniem
między trybem statycznym a dynamicznym i syntetyzuje
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">akcesory
pakietów</LocalizedLink>, które są standardowe dla wszystkich typów łączenia. W
połączeniu z
<LocalizedLink href="/guides/features/projects/dynamic-configuration">konfiguracjami
dynamicznymi za pomocą zmiennych środowiskowych</LocalizedLink> można przekazać
typ łączenia w momencie wywołania i użyć wartości w manifestach do ustawienia
typu produktu docelowego.

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Należy pamiętać, że Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> nie
domyślnie zapewnia wygodę poprzez domyślną konfigurację ze względu na związane z
tym koszty</LocalizedLink>. Oznacza to, że polegamy na użytkowniku, który
ustawia typ łącza i wszelkie dodatkowe ustawienia kompilacji, które są czasami
wymagane, takie jak flaga linkera [`-ObjC`
](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
aby zapewnić poprawność wynikowych plików binarnych. Dlatego też nasze
stanowisko polega na dostarczaniu użytkownikowi zasobów, zazwyczaj w formie
dokumentacji, aby mógł on podjąć właściwe decyzje.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Pakiet Swift, który integruje wiele projektów, to [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture).
Więcej szczegółów można znaleźć w [tej sekcji](#the-composable-architecture).
<!-- -->
:::

### Scenariusze {#scenarios}

Istnieją sytuacje, w których ustawienie łączenia całkowicie na statyczne lub
dynamiczne nie jest wykonalne lub nie jest dobrym pomysłem. Poniżej znajduje się
niepełna lista sytuacji, w których może być konieczne połączenie łączenia
statycznego i dynamicznego:

- **Aplikacje z rozszerzeniami:** Ponieważ aplikacje i ich rozszerzenia muszą
  współdzielić kod, może być konieczne uczynienie tych celów dynamicznymi. W
  przeciwnym razie ten sam kod zostanie zduplikowany zarówno w aplikacji, jak i
  rozszerzeniu, co spowoduje zwiększenie rozmiaru pliku binarnego.
- **Wstępnie skompilowane zależności zewnętrzne:** Czasami otrzymujesz wstępnie
  skompilowane pliki binarne, które są statyczne lub dynamiczne. Pliki binarne
  statyczne można zawrzeć w dynamicznych frameworkach lub bibliotekach, aby były
  one łączone dynamicznie.

Podczas wprowadzania zmian w wykresie Tuist przeanalizuje go i wyświetli
ostrzeżenie, jeśli wykryje „statyczny efekt uboczny”. Ostrzeżenie to ma na celu
pomóc w identyfikacji problemów, które mogą wyniknąć z statycznego powiązania,
które zależy przechodnio od statycznego celu poprzez cele dynamiczne. Efekty
uboczne często objawiają się zwiększoną wielkością pliku binarnego lub, w
najgorszych przypadkach, awariami podczas działania.

## Rozwiązywanie problemów {#troubleshooting}

### Zależności Objective-C {#objectivec-dependencies}

Podczas integracji zależności Objective-C może być konieczne dodanie określonych
flag w docelowym miejscu wykorzystania, aby uniknąć awarii w czasie wykonywania,
jak opisano szczegółowo w [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Ponieważ system kompilacji i Tuist nie mają możliwości ustalenia, czy flaga jest
konieczna, a także ponieważ flaga ta może powodować niepożądane skutki uboczne,
Tuist nie stosuje automatycznie żadnej z tych flag, a ponieważ Swift Package
Manager uznaje `-ObjC` za dołączoną poprzez `.unsafeFlag`, większość pakietów
nie może dołączyć jej jako części domyślnych ustawień łączenia, gdy jest to
wymagane.

Użytkownicy zależności Objective-C (lub wewnętrznych celów Objective-C) powinni
stosować flagi `-ObjC` lub `-force_load`, gdy jest to wymagane, ustawiając
`OTHER_LDFLAGS` w celach konsumpcyjnych.

### Firebase i inne biblioteki Google {#firebase-other-google-libraries}

Biblioteki open source firmy Google — choć potężne — mogą być trudne do
zintegrowania z Tuist, ponieważ często wykorzystują niestandardową architekturę
i techniki w sposobie ich budowy.

Oto kilka wskazówek, których należy przestrzegać, aby zintegrować Firebase i
inne biblioteki Google dla platformy Apple:

#### Upewnij się, że `-ObjC` zostało dodane do `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Wiele bibliotek Google jest napisanych w języku Objective-C. Z tego powodu każdy
docelowy konsument będzie musiał dołączyć tag `-ObjC` w ustawieniu kompilacji
`OTHER_LDFLAGS`. Można to ustawić w pliku `.xcconfig` lub ręcznie określić w
ustawieniach docelowych w manifestach Tuist. Przykład:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Więcej szczegółów można znaleźć w sekcji [Zależności
Objective-C](#objective-c-dependencies) powyżej.

#### Ustaw typ produktu dla `FBLPromises` na dynamic framework. {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Niektóre biblioteki Google są zależne od `FBLPromises`, innej biblioteki Google.
Może wystąpić awaria, która wspomina o `FBLPromises`, wyglądająca mniej więcej
tak:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Wyraźne ustawienie typu produktu `FBLPromises` na `.framework` w pliku
`Package.swift` powinno rozwiązać problem:

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### Architektura kompozycyjna {#the-composable-architecture}

Jak opisano
[tutaj](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
i w [sekcji dotyczącej rozwiązywania problemów](#troubleshooting), podczas
statycznego łączenia pakietów, które jest domyślnym typem łączenia w Tuist,
należy ustawić opcję kompilacji `OTHER_LDFLAGS` na `$(inherited) -ObjC`.
Alternatywnie można nadpisać typ produktu dla pakietu, aby był dynamiczny.
Podczas łączenia statycznego cele testowe i aplikacyjne zazwyczaj działają bez
żadnych problemów, ale podglądy SwiftUI są uszkodzone. Można to rozwiązać,
łącząc wszystko dynamicznie. W poniższym przykładzie dodano również
[Sharing](https://github.com/pointfreeco/swift-sharing) jako zależność, ponieważ
jest ono często używane razem z The Composable Architecture i ma swoje własne
[pułapki
konfiguracyjne](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

Poniższa konfiguracja połączy wszystko dynamicznie — dzięki temu aplikacja +
cele testowe i podglądy SwiftUI będą działać.

::: tip STATIC OR DYNAMIC
<!-- -->
Łączenie dynamiczne nie zawsze jest zalecane. Więcej szczegółów można znaleźć w
sekcji [Statyczne lub dynamiczne](#static-or-dynamic). W tym przykładzie
wszystkie zależności są połączone dynamicznie bez warunków dla uproszczenia.
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: warning
<!-- -->
Zamiast `import Sharing` należy użyć `import SwiftSharing`.
<!-- -->
:::

### Przenikanie zależności statycznych poprzez `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Gdy dynamiczna struktura lub biblioteka zależy od statycznych poprzez `import
StaticSwiftModule`, symbole są zawarte w `.swiftmodule` dynamicznej struktury
lub biblioteki, co może
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">spowodować
niepowodzenie kompilacji</LocalizedLink>. Aby temu zapobiec, należy zaimportować
statyczną zależność za pomocą
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>:

```swift
internal import StaticModule
```

:: info
<!-- -->
Poziom dostępu do importów został uwzględniony w Swift 6. Jeśli używasz
starszych wersji Swift, musisz zamiast tego użyć
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
