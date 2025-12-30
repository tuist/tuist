---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Migracja projektu Xcode {#migrate-an-xcode-project}

O ile <LocalizedLink href="/guides/features/projects/adoption/new-project"> nie utworzysz nowego projektu przy użyciu Tuist</LocalizedLink>, w którym to
przypadku wszystko zostanie skonfigurowane automatycznie, będziesz musiał
zdefiniować swoje projekty Xcode przy użyciu prymitywów Tuist. Żmudność tego
procesu zależy od stopnia złożoności projektu.

Jak zapewne wiesz, projekty Xcode mogą z czasem stać się nieuporządkowane i
złożone: grupy, które nie pasują do struktury katalogów, pliki, które są
współdzielone między celami lub odniesienia do plików, które wskazują na
nieistniejące pliki (by wspomnieć o niektórych). Cała ta nagromadzona złożoność
utrudnia nam dostarczenie polecenia, które niezawodnie migruje projekt.

Co więcej, ręczna migracja jest doskonałym ćwiczeniem do czyszczenia i
upraszczania projektów. Nie tylko deweloperzy w projekcie będą za to wdzięczni,
ale także Xcode, który będzie je szybciej przetwarzał i indeksował. Gdy w pełni
zaadoptujesz Tuist, upewnisz się, że projekty są spójnie zdefiniowane i
pozostają proste.

Aby ułatwić tę pracę, przedstawiamy kilka wskazówek opartych na opiniach, które
otrzymaliśmy od użytkowników.

## Tworzenie rusztowania projektu {#create-project-scaffold}

Przede wszystkim utwórz rusztowanie dla swojego projektu z następującymi plikami
Tuist:

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

`Project.swift` to plik manifestu, w którym definiuje się projekt, a
`Package.swift` to plik manifestu, w którym definiuje się zależności. Plik
`Tuist.swift` to miejsce, w którym można zdefiniować ustawienia Tuist dla
projektu.

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
Aby zapobiec konfliktom z istniejącym projektem Xcode, zalecamy dodanie
przyrostka `-Tuist` do nazwy projektu. Można go usunąć po pełnej migracji
projektu do Tuist.
<!-- -->
:::

## Zbuduj i przetestuj projekt Tuist w CI {#build-and-test-the-tuist-project-in-ci}

Aby upewnić się, że migracja każdej zmiany jest prawidłowa, zalecamy
rozszerzenie ciągłej integracji w celu zbudowania i przetestowania projektu
wygenerowanego przez Tuist z pliku manifestu:

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## Wyodrębnij ustawienia kompilacji projektu do plików `.xcconfig`. {#extract-the-project-build-settings-into-xcconfig-files}

Wyodrębnij ustawienia kompilacji z projektu do pliku `.xcconfig`, aby uprościć
projekt i ułatwić migrację. Za pomocą poniższego polecenia można wyodrębnić
ustawienia kompilacji z projektu do pliku `.xcconfig`:


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

Następnie zaktualizuj plik `Project.swift`, aby wskazywał na właśnie utworzony
plik `.xcconfig`:

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

Następnie należy rozszerzyć potok ciągłej integracji, aby uruchomić następujące
polecenie w celu zapewnienia, że zmiany ustawień kompilacji są wprowadzane
bezpośrednio do plików `.xcconfig`:

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## Wyodrębnij zależności pakietów {#extract-package-dependencies}

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
Typ produktu dla określonego pakietu można zastąpić, dodając go do słownika
`productTypes` w strukturze `PackageSettings`. Domyślnie Tuist zakłada, że
wszystkie pakiety są statycznymi frameworkami.
<!-- -->
:::


## Określenie kolejności migracji {#determine-the-migration-order}

Zalecamy migrację obiektów docelowych od tego, który jest najbardziej zależny do
najmniej. Możesz użyć następującego polecenia, aby wyświetlić listę obiektów
docelowych projektu, posortowanych według liczby zależności:

```bash
tuist migration list-targets -p Project.xcodeproj
```

Rozpocznij migrację celów z góry listy, ponieważ są one najbardziej zależne.


## Migracja celów {#migrate-targets}

Migruj cele jeden po drugim. Zalecamy wykonanie pull requesta dla każdego celu,
aby upewnić się, że zmiany zostały sprawdzone i przetestowane przed ich
scaleniem.

### Wyodrębnij docelowe ustawienia kompilacji do plików `.xcconfig`. {#extract-the-target-build-settings-into-xcconfig-files}

Podobnie jak w przypadku ustawień kompilacji projektu, należy wyodrębnić
docelowe ustawienia kompilacji do pliku `.xcconfig`, aby docelowa kompilacja
była prostsza i łatwiejsza do migracji. Możesz użyć następującego polecenia, aby
wyodrębnić ustawienia kompilacji z celu do pliku `.xcconfig`:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### Zdefiniuj cel w pliku `Project.swift` {#define-the-target-in-the-projectswift-file}

Zdefiniuj cel w `Project.targets`:

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

### Weryfikacja migracji docelowej {#validate-the-target-migration}

Uruchom `tuist generate`, a następnie `xcodebuild build`, aby upewnić się, że
projekt zostanie zbudowany, oraz `tuist test`, aby upewnić się, że testy
zakończą się pomyślnie. Dodatkowo możesz użyć
[xcdiff](https://github.com/bloomberg/xcdiff), aby porównać wygenerowany projekt
Xcode z istniejącym, aby upewnić się, że zmiany są prawidłowe.

### Powtarzanie {#repeat}

Powtarzaj tę czynność, aż wszystkie obiekty docelowe zostaną w pełni zmigrowane.
Po zakończeniu zalecamy aktualizację potoków CI i CD w celu zbudowania i
przetestowania projektu przy użyciu `tuist generate`, a następnie `xcodebuild
build` i `tuist test`.

## Rozwiązywanie problemów {#troubleshooting}

### Błędy kompilacji z powodu brakujących plików. {#compilation-errors-due-to-missing-files}

Jeśli pliki powiązane z celami projektu Xcode nie były zawarte w katalogu
systemu plików reprezentującym cel, projekt może się nie skompilować. Upewnij
się, że lista plików po wygenerowaniu projektu za pomocą Tuist jest zgodna z
listą plików w projekcie Xcode i skorzystaj z okazji, aby dostosować strukturę
plików do struktury docelowej.
