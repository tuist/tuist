---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# Zależności {#dependencies}

Gdy projekt się rozrasta, często dzieli się go na wiele celów, aby współdzielić
kod, definiować granice i skrócić czas kompilacji. Wiele celów oznacza
definiowanie zależności między nimi, tworząc graf zależności **** , który może
obejmować również zależności zewnętrzne.

## Wykresy zakodowane w XcodeProj {#xcodeprojcodified-graphs}

Ze względu na konstrukcję Xcode i XcodeProj, utrzymanie wykresu zależności może
być żmudnym i podatnym na błędy zadaniem. Oto kilka przykładów problemów, które
można napotkać:

- Ponieważ system kompilacji Xcode wyprowadza wszystkie produkty projektu do
  tego samego katalogu w danych pochodnych, cele mogą być w stanie importować
  produkty, których nie powinny. Kompilacje mogą zakończyć się niepowodzeniem w
  CI, gdzie czyste kompilacje są bardziej powszechne, lub później, gdy używana
  jest inna konfiguracja.
- Przechodnie zależności dynamiczne celu muszą zostać skopiowane do dowolnego z
  katalogów, które są częścią ustawienia kompilacji `LD_RUNPATH_SEARCH_PATHS`.
  Jeśli tak nie jest, cel nie będzie w stanie ich znaleźć w czasie wykonywania.
  Jest to łatwe do pomyślenia i skonfigurowania, gdy wykres jest mały, ale staje
  się problemem, gdy wykres rośnie.
- Gdy cel łączy statyczny
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle),
  cel wymaga dodatkowej fazy kompilacji, aby Xcode mógł przetworzyć pakiet i
  wyodrębnić odpowiednie pliki binarne dla bieżącej platformy i architektury. Ta
  faza kompilacji nie jest dodawana automatycznie i łatwo jest zapomnieć o jej
  dodaniu.

Powyższe to tylko kilka przykładów, ale jest ich znacznie więcej, z którymi
mieliśmy do czynienia na przestrzeni lat. Wyobraź sobie, że potrzebujesz zespołu
inżynierów do utrzymania wykresu zależności i zapewnienia jego poprawności. Albo
jeszcze gorzej, że zawiłości zostały rozwiązane w czasie kompilacji przez
zamknięty system kompilacji, którego nie można kontrolować ani dostosowywać.
Brzmi znajomo? Jest to podejście przyjęte przez Apple w Xcode i XcodeProj, które
odziedziczył Swift Package Manager.

Głęboko wierzymy, że graf zależności powinien być **jawny** i **statyczny**
ponieważ tylko wtedy może być **zweryfikowany** i **zoptymalizowany**. Dzięki
Tuist skupiasz się na opisaniu, co zależy od czego, a my zajmujemy się resztą.
Zawiłości i szczegóły implementacji są abstrahowane od Ciebie.

W poniższych sekcjach dowiesz się, jak zadeklarować zależności w swoim
projekcie.

::: tip GRAPH VALIDATION
<!-- -->
Tuist waliduje graf podczas generowania projektu, aby upewnić się, że nie ma
cykli i że wszystkie zależności są prawidłowe. Dzięki temu każdy zespół może
wziąć udział w ewolucji grafu zależności bez obawy o jego uszkodzenie.
<!-- -->
:::

## Zależności lokalne {#local-dependencies}

Obiekty docelowe mogą zależeć od innych obiektów docelowych w tym samym lub
różnych projektach, a także od plików binarnych. Podczas tworzenia instancji
celu `` można przekazać argument `dependencies` z dowolną z poniższych opcji:

- `Cel`: Deklaruje zależność z celem w ramach tego samego projektu.
- `Projekt`: Deklaruje zależność z celem w innym projekcie.
- `Framework`: Deklaruje zależność z binarnym frameworkiem.
- `Biblioteka`: Deklaruje zależność z biblioteką binarną.
- `XCFramework`: Deklaruje zależność z binarnym XCFramework.
- `SDK`: Deklaruje zależność z systemowym SDK.
- `XCTest`: Deklaruje zależność z XCTest.

::: info DEPENDENCY CONDITIONS
<!-- -->
Każdy typ zależności akceptuje `warunek` opcję warunkowego łączenia zależności w
oparciu o platformę. Domyślnie łączy ona zależność dla wszystkich platform
obsługiwanych przez cel.
<!-- -->
:::

## Zależności zewnętrzne {#external-dependencies}

Tuist pozwala również na deklarowanie zewnętrznych zależności w projekcie.

### Pakiety Swift {#swift-packages}

Pakiety Swift to zalecany przez nas sposób deklarowania zależności w projekcie.
Można je zintegrować za pomocą domyślnego mechanizmu integracji Xcode lub
integracji opartej na XcodeProj Tuist.

#### Integracja Tuist oparta na XcodeProj {#tuists-xcodeprojbased-integration}

Domyślna integracja Xcode jest najwygodniejsza, ale brakuje jej elastyczności i
kontroli, które są wymagane w przypadku średnich i dużych projektów. Aby temu
zaradzić, Tuist oferuje integrację opartą na XcodeProj, która umożliwia
integrację pakietów Swift w projekcie przy użyciu celów XcodeProj. Dzięki temu
możemy nie tylko zapewnić większą kontrolę nad integracją, ale także uczynić ją
kompatybilną z przepływami pracy, takimi jak
<LocalizedLink href="/guides/features/cache">caching</LocalizedLink> i
<LocalizedLink href="/guides/features/test/selective-testing">selektywne uruchamianie testów</LocalizedLink>.

Integracja XcodeProj może zająć więcej czasu, aby obsługiwać nowe funkcje
pakietów Swift lub obsługiwać więcej konfiguracji pakietów. Jednak logika
mapowania między pakietami Swift i celami XcodeProj jest open-source i może być
współtworzona przez społeczność. Jest to przeciwieństwo domyślnej integracji
Xcode, która jest zamknięta i utrzymywana przez Apple.

Aby dodać zewnętrzne zależności, należy utworzyć plik `Package.swift` w sekcji
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
Instancja `PackageSettings` opakowana w dyrektywę kompilatora pozwala
skonfigurować sposób integracji pakietów. Na przykład w powyższym przykładzie
służy do zastąpienia domyślnego typu produktu używanego dla pakietów. Domyślnie
nie powinno to być potrzebne.
<!-- -->
:::

> [Jeśli projekt używa niestandardowych konfiguracji kompilacji (konfiguracji
> innych niż standardowe `Debug` i `Release`), należy je określić w
> `PackageSettings` używając `baseSettings`. Zewnętrzne zależności muszą
> wiedzieć o konfiguracjach projektu, aby kompilować się poprawnie. Na przykład:
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

Plik `Package.swift` to tylko interfejs do deklarowania zewnętrznych zależności,
nic więcej. Dlatego w pakiecie nie definiuje się żadnych obiektów docelowych ani
produktów. Po zdefiniowaniu zależności można uruchomić następujące polecenie,
aby rozwiązać i pobrać zależności do katalogu `Tuist/Dependencies`:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

Jak być może zauważyłeś, stosujemy podejście podobne do
[CocoaPods](https://cocoapods.org)', gdzie rozwiązywanie zależności jest osobnym
poleceniem. Daje to użytkownikom kontrolę nad tym, kiedy chcą, aby zależności
zostały rozwiązane i zaktualizowane, a także umożliwia otwarcie projektu Xcode i
przygotowanie go do kompilacji. Jest to obszar, w którym uważamy, że
doświadczenie programisty zapewniane przez integrację Apple z Menedżerem
pakietów Swift pogarsza się z czasem wraz z rozwojem projektu.

Z poziomu celów projektu można następnie odwoływać się do tych zależności za
pomocą typu zależności `TargetDependency.external`:

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
zachować czystość listy schematów. Można je utworzyć za pomocą interfejsu
użytkownika Xcode.
<!-- -->
:::

#### Domyślna integracja Xcode {#xcodes-default-integration}

Jeśli chcesz korzystać z domyślnego mechanizmu integracji Xcode, możesz
przekazać listę `pakietów` podczas tworzenia instancji projektu:

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

A następnie odwołaj się do nich ze swoich celów:

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

W przypadku makr Swift i wtyczek Build Tool należy użyć odpowiednio typów
`.macro` i `.plugin`.

::: warning SPM Build Tool Plugins
<!-- -->
Wtyczki narzędzi kompilacji SPM muszą być zadeklarowane przy użyciu mechanizmu
[Domyślna integracja Xcode](#xcode-s-default-integration), nawet jeśli używana
jest integracja Tuist [Oparta na
XcodeProj](#tuist-s-xcodeproj-based-integration) dla zależności projektu.
<!-- -->
:::

Praktycznym zastosowaniem wtyczki narzędzia kompilacji SPM jest wykonywanie
lintingu kodu podczas fazy kompilacji Xcode "Run Build Tool Plug-ins". W
manifeście pakietu jest to zdefiniowane w następujący sposób:

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
należy zadeklarować pakiet w manifeście projektu w tablicy `packages`, a
następnie dołączyć pakiet o typie `.plugin` do zależności celu.

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
lub `xcframeworks`, można uruchomić `carthage update`, aby wyświetlić zależności
w katalogu `Carthage/Build`, a następnie użyć typu zależności `.framework` lub
`.xcframework` target, aby zadeklarować zależność w celu. Można to zawinąć w
skrypt, który można uruchomić przed wygenerowaniem projektu.

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
Jeśli budujesz i testujesz swój projekt za pomocą `xcodebuild build` i `tuist
test`, musisz również upewnić się, że zależności rozwiązane przez Carthage są
obecne, uruchamiając polecenie `carthage update` przed budowaniem lub
testowaniem.
<!-- -->
:::

### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) oczekuje projektu Xcode w celu zintegrowania
zależności. Możesz użyć Tuist do wygenerowania projektu, a następnie uruchomić
`pod install`, aby zintegrować zależności, tworząc obszar roboczy zawierający
projekt i zależności Pods. Można to zawrzeć w skrypcie, który można uruchomić
przed wygenerowaniem projektu.

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
Zależności CocoaPods nie są kompatybilne z przepływami pracy, takimi jak `build`
lub `test`, które uruchamiają `xcodebuild` zaraz po wygenerowaniu projektu. Są
one również niekompatybilne z buforowaniem binarnym i testowaniem selektywnym,
ponieważ logika fingerprintingu nie uwzględnia zależności Pods.
<!-- -->
:::

## Statyczne lub dynamiczne {#static-or-dynamic}

Frameworki i biblioteki mogą być łączone statycznie lub dynamicznie, **wybór,
który ma znaczący wpływ na takie aspekty jak rozmiar aplikacji i czas
uruchamiania**. Pomimo swojego znaczenia, decyzja ta jest często podejmowana bez
większego zastanowienia.

Ogólna zasada **** jest taka, że chcesz, aby jak najwięcej rzeczy było
połączonych statycznie w kompilacjach wydania, aby osiągnąć szybki czas
uruchamiania, a jak najwięcej rzeczy było połączonych dynamicznie w kompilacjach
debugowania, aby osiągnąć szybki czas iteracji.

Wyzwanie związane ze zmianą pomiędzy statycznym i dynamicznym linkowaniem w
grafie projektu nie jest trywialne w Xcode, ponieważ zmiana ma kaskadowy wpływ
na cały graf (np. biblioteki nie mogą zawierać zasobów, statyczne frameworki nie
muszą być osadzone). Apple próbowało rozwiązać ten problem za pomocą rozwiązań w
czasie kompilacji, takich jak automatyczna decyzja Swift Package Manager
pomiędzy statycznym i dynamicznym linkowaniem lub [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Rozwiązanie to dodaje jednak nowe dynamiczne zmienne do grafu kompilacji,
dodając nowe źródła niedeterminizmu i potencjalnie powodując, że niektóre
funkcje, takie jak Swift Previews, które opierają się na grafie kompilacji,
stają się zawodne.

Na szczęście Tuist koncepcyjnie kompresuje złożoność związaną ze zmianą między
statycznym i dynamicznym i syntetyzuje
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</LocalizedLink>, które są standardowe dla wszystkich typów linkowania.
W połączeniu z
<LocalizedLink href="/guides/features/projects/dynamic-configuration"> dynamicznymi konfiguracjami poprzez zmienne środowiskowe</LocalizedLink>, możesz
przekazać typ łączenia w czasie wywołania i użyć wartości w swoich manifestach,
aby ustawić typ produktu swoich celów.

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
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> nie jest domyślnie wygodny poprzez niejawną konfigurację ze względu na jego koszty </LocalizedLink>. Oznacza to, że polegamy na ustawieniu typu linkowania i
wszelkich dodatkowych ustawień kompilacji, które są czasami wymagane, takich jak
flaga linkera [`-ObjC`
](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184),
aby zapewnić poprawność wynikowych plików binarnych. W związku z tym nasze
stanowisko polega na dostarczaniu zasobów, zwykle w postaci dokumentacji, w celu
podejmowania właściwych decyzji.

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
Pakiet Swift, który integruje wiele projektów, to [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture).
Więcej szczegółów można znaleźć w [tej sekcji](#the-composable-architecture).
<!-- -->
:::

### Scenariusze {#scenarios}

Istnieją pewne scenariusze, w których ustawienie linkowania całkowicie na
statyczne lub dynamiczne nie jest wykonalne lub nie jest dobrym pomysłem.
Poniżej znajduje się niewyczerpująca lista scenariuszy, w których może być
konieczne połączenie statycznego i dynamicznego linkowania:

- **Aplikacje z rozszerzeniami:** Ponieważ aplikacje i ich rozszerzenia muszą
  współdzielić kod, może być konieczne uczynienie tych celów dynamicznymi. W
  przeciwnym razie ten sam kod zostanie zduplikowany zarówno w aplikacji, jak i
  rozszerzeniu, co spowoduje zwiększenie rozmiaru pliku binarnego.
- **Wstępnie skompilowane zależności zewnętrzne:** Czasami dostarczane są
  prekompilowane pliki binarne, które są statyczne lub dynamiczne. Statyczne
  pliki binarne mogą być opakowane w dynamiczne frameworki lub biblioteki do
  dynamicznego łączenia.

Podczas wprowadzania zmian w wykresie, Tuist przeanalizuje go i wyświetli
ostrzeżenie, jeśli wykryje "statyczny efekt uboczny". Ostrzeżenie to ma na celu
pomóc w zidentyfikowaniu problemów, które mogą pojawić się w wyniku statycznego
łączenia celu, który zależy tranzytowo od celu statycznego za pośrednictwem
celów dynamicznych. Te efekty uboczne często objawiają się zwiększonym rozmiarem
pliku binarnego lub, w najgorszych przypadkach, awariami w czasie wykonywania.

## Rozwiązywanie problemów {#troubleshooting}

### Zależności Objective-C {#objectivec-dependencies}

Podczas integrowania zależności Objective-C, włączenie pewnych flag w celu
konsumpcji może być konieczne, aby uniknąć awarii w czasie wykonywania, jak
opisano szczegółowo w [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html).

Ponieważ system kompilacji i Tuist nie mają możliwości wywnioskowania, czy flaga
jest konieczna, czy nie, i ponieważ flaga ta ma potencjalnie niepożądane skutki
uboczne, Tuist nie zastosuje automatycznie żadnej z tych flag, a ponieważ
Menedżer pakietów Swift uważa `-ObjC` za dołączoną za pośrednictwem
`.unsafeFlag`, większość pakietów nie może dołączyć jej jako części swoich
domyślnych ustawień łączenia, gdy jest to wymagane.

Konsumenci zależności Objective-C (lub wewnętrznych celów Objective-C) powinni
stosować flagi `-ObjC` lub `-force_load`, gdy jest to wymagane, ustawiając
`OTHER_LDFLAGS` na konsumowanych celach.

### Firebase i inne biblioteki Google {#firebase-other-google-libraries}

Biblioteki open source Google - choć potężne - mogą być trudne do zintegrowania
z Tuist, ponieważ często wykorzystują niestandardową architekturę i techniki w
sposobie ich tworzenia.

Oto kilka wskazówek, które mogą być niezbędne do zintegrowania Firebase i innych
bibliotek Google dla platformy Apple:

#### Upewnij się, że `-ObjC` jest dodane do `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Wiele bibliotek Google jest napisanych w Objective-C. Z tego powodu każdy
zużywający się cel będzie musiał zawierać znacznik `-ObjC` w swoim
`OTHER_LDFLAGS` ustawieniu kompilacji. Można to ustawić w pliku `.xcconfig` lub
ręcznie określić w ustawieniach celu w manifestach Tuist. Przykład:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

Więcej szczegółów znajduje się w sekcji [Zależności
Objective-C](#objective-c-dependencies) powyżej.

#### Ustaw typ produktu dla `FBLPromises` na dynamiczny framework {#set-the-product-type-for-fblpromises-to-dynamic-framework}

Niektóre biblioteki Google zależą od `FBLPromises`, innej biblioteki Google.
Możesz napotkać awarię, która wspomina o `FBLPromises`, wyglądającą mniej więcej
tak:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

Jawne ustawienie typu produktu `FBLPromises` na `.framework` w pliku
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

### Architektura kompozytowa {#the-composable-architecture}

Jak opisano
[tutaj](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
i [sekcja rozwiązywania problemów](#troubleshooting), musisz ustawić ustawienie
kompilacji `OTHER_LDFLAGS` na `$(inherited) -ObjC` podczas statycznego łączenia
pakietów, co jest domyślnym typem łączenia Tuist. Alternatywnie można zastąpić
typ produktu, aby pakiet był dynamiczny. Podczas łączenia statycznego, cele
testowe i aplikacji zazwyczaj działają bez żadnych problemów, ale podglądy
SwiftUI są uszkodzone. Można to rozwiązać, łącząc wszystko dynamicznie. W
poniższym przykładzie [Sharing](https://github.com/pointfreeco/swift-sharing)
jest również dodane jako zależność, ponieważ jest często używane razem z The
Composable Architecture i ma swoje własne [pułapki
konfiguracyjne](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032).

Poniższa konfiguracja połączy wszystko dynamicznie - więc aplikacja + cele
testowe i podglądy SwiftUI działają.

::: tip STATIC OR DYNAMIC
<!-- -->
Dynamiczne linkowanie nie zawsze jest zalecane. Więcej szczegółów można znaleźć
w sekcji [Statyczne lub dynamiczne](#static-or-dynamic). W tym przykładzie
wszystkie zależności są łączone dynamicznie bez warunków dla uproszczenia.
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
Zamiast `import Sharing` należy `import SwiftSharing`.
<!-- -->
:::

### Przejściowe zależności statyczne wyciekają przez `.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

Gdy dynamiczny framework lub biblioteka zależy od statycznych poprzez `import
StaticSwiftModule`, symbole są zawarte w `.swiftmodule` dynamicznego frameworka
lub biblioteki, potencjalnie
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1"> powodując niepowodzenie kompilacji</LocalizedLink>. Aby temu zapobiec, należy
zaimportować zależność statyczną za pomocą
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink>:

```swift
internal import StaticModule
```

:: info
<!-- -->
Poziom dostępu do importów został włączony w Swift 6. Jeśli używasz starszych
wersji Swift, musisz użyć
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
zamiast tego:
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
