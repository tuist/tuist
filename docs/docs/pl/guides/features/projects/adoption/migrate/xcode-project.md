---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migracja projektu Xcode {#migrate-an-xcode-project}

O ile nie
<LocalizedLink href="/guides/features/projects/adoption/new-project">utworzysz
nowego projektu za pomocą Tuist</LocalizedLink>, w którym to przypadku wszystko
zostanie skonfigurowane automatycznie, będziesz musiał zdefiniować swoje
projekty Xcode za pomocą prymitywów Tuist. To, jak żmudny jest ten proces,
zależy od stopnia złożoności Twoich projektów.

Jak zapewne wiesz, projekty Xcode mogą z czasem stać się nieuporządkowane i
złożone: grupy, które nie pasują do struktury katalogów, pliki współdzielone
między celami lub odniesienia do plików, które nie istnieją (aby wymienić tylko
kilka). Cała ta nagromadzona złożoność utrudnia nam zapewnienie polecenia, które
niezawodnie przenosi projekt.

Ponadto ręczna migracja jest doskonałym ćwiczeniem pozwalającym uporządkować i
uprościć projekty. Będą za to wdzięczni nie tylko programiści pracujący nad
projektem, ale także Xcode, który będzie szybciej je przetwarzał i indeksował.
Po pełnym wdrożeniu Tuist zapewni spójną definicję projektów i ich prostotę.

Aby ułatwić tę pracę, przedstawiamy kilka wskazówek opartych na opiniach
otrzymanych od użytkowników.

## Utwórz szkielet projektu {#create-project-scaffold}

Najpierw utwórz szkielet projektu z następującymi plikami Tuist:

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` to plik manifestu, w którym definiujesz swój projekt, a
`Package.swift` to plik manifestu, w którym definiujesz swoje zależności. Plik
`Tuist.swift` służy do definiowania ustawień Tuist w zakresie projektu.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Aby zapobiec konfliktom z istniejącym projektem Xcode, zalecamy dodanie do nazwy
projektu sufiksów `-Tuist`. Możesz je usunąć po zakończeniu migracji projektu do
Tuist.
<!-- -->
:::

## Skompiluj i przetestuj projekt Tuist w CI. {#build-and-test-the-tuist-project-in-ci}

Aby zapewnić prawidłowość migracji każdej zmiany, zalecamy rozszerzenie ciągłej
integracji w celu skompilowania i przetestowania projektu wygenerowanego przez
Tuist na podstawie pliku manifestu:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Wyodrębnij ustawienia kompilacji projektu do plików `.xcconfig`. {#extract-the-project-build-settings-into-xcconfig-files}

Wyodrębnij ustawienia kompilacji z projektu do pliku `.xcconfig`, aby projekt
był bardziej przejrzysty i łatwiejszy do migracji. Możesz użyć następującego
polecenia, aby wyodrębnić ustawienia kompilacji z projektu do pliku `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Następnie zaktualizuj plik `Project.swift`, aby wskazywał na właśnie utworzony
plik `.xcconfig`.

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

Następnie rozszerz potok ciągłej integracji, aby uruchomić następujące polecenie
w celu zapewnienia, że zmiany w ustawieniach kompilacji są wprowadzane
bezpośrednio w plikach `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Wyodrębnij zależności pakietu {#extract-package-dependencies}

Wyodrębnij wszystkie zależności projektu do pliku `Tuist/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

::: tip PRODUCT TYPES
<!-- -->
Możesz zmienić typ produktu dla konkretnego pakietu, dodając go do słownika
`productTypes` w strukturze `PackageSettings`. Domyślnie Tuist zakłada, że
wszystkie pakiety są statycznymi frameworkami.
<!-- -->
:::


## Określ kolejność migracji {#determine-the-migration-order}

Zalecamy migrację celów od najbardziej zależnych do najmniej zależnych. Możesz
użyć następującego polecenia, aby wyświetlić listę celów projektu posortowaną
według liczby zależności:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Rozpocznij migrację celów od góry listy, ponieważ są to te, od których zależy
najwięcej.


## Migruj cele {#migrate-targets}

Przenoś cele jeden po drugim. Zalecamy wykonanie pull requestu dla każdego celu,
aby zapewnić, że zmiany zostaną sprawdzone i przetestowane przed ich scaleniem.

### Wyodrębnij docelowe ustawienia kompilacji do plików `.xcconfig`. {#extract-the-target-build-settings-into-xcconfig-files}

Podobnie jak w przypadku ustawień kompilacji projektu, wyodrębnij ustawienia
kompilacji docelowej do pliku `.xcconfig`, aby docelowy plik był bardziej
przejrzysty i łatwiejszy do migracji. Możesz użyć następującego polecenia, aby
wyodrębnić ustawienia kompilacji z docelowego pliku do pliku `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Zdefiniuj cel w pliku `Project.swift`. {#define-the-target-in-the-projectswift-file}

Zdefiniuj cel w pliku `Project.targets`:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
Jeśli cel ma powiązany cel testowy, należy go zdefiniować w pliku
`Project.swift`, powtarzając te same kroki.
<!-- -->
:::

### Sprawdź poprawność migracji docelowej. {#validate-the-target-migration}

Uruchom `tuist generate`, a następnie `xcodebuild build`, aby upewnić się, że
projekt został skompilowany, oraz `tuist test`, aby upewnić się, że testy
zakończyły się powodzeniem. Dodatkowo możesz użyć
[xcdiff](https://github.com/bloomberg/xcdiff), aby porównać wygenerowany projekt
Xcode z istniejącym i upewnić się, że zmiany są poprawne.

### Powtórz {#repeat}

Powtarzaj tę czynność, aż wszystkie cele zostaną w pełni przeniesione. Po
zakończeniu zalecamy zaktualizowanie potoków CI i CD w celu skompilowania i
przetestowania projektu przy użyciu `tuist generate`, a następnie `xcodebuild
build` i `tuist test`.

## Rozwiązywanie problemów {#troubleshooting}

### Błędy kompilacji spowodowane brakującymi plikami. {#compilation-errors-due-to-missing-files}

Jeśli pliki powiązane z celami projektu Xcode nie zostały zawarte w katalogu
systemu plików reprezentującym cel, może to spowodować, że projekt nie będzie
się kompilował. Upewnij się, że lista plików po wygenerowaniu projektu za pomocą
Tuist jest zgodna z listą plików w projekcie Xcode i skorzystaj z okazji, aby
dostosować strukturę plików do struktury celu.
