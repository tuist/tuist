---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Migracja projektu Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) to system kompilacji, który Google udostępnił na
licencji open source w 2015 roku. Jest to potężne narzędzie, które pozwala
szybko i niezawodnie kompilować i testować oprogramowanie dowolnej wielkości.
Korzystają z niego niektóre duże organizacje, takie jak
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
czy [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), jednak jego
wdrożenie i utrzymanie wymaga początkowej inwestycji (tj. nauki obsługi
technologii) oraz ciągłych nakładów (tj. śledzenia aktualizacji Xcode). Chociaż
rozwiązanie to sprawdza się w niektórych organizacjach, które traktują je jako
kwestię przekrojową, może nie być najlepszym rozwiązaniem dla innych, które chcą
skupić się na rozwoju swoich produktów. Widzieliśmy na przykład organizacje,
których zespół zajmujący się platformą iOS wprowadził Bazel, a następnie musiał
z niego zrezygnować po odejściu z firmy inżynierów, którzy kierowali tym
przedsięwzięciem. Stanowisko Apple w sprawie silnego powiązania między Xcode a
systemem kompilacji jest kolejnym czynnikiem, który utrudnia utrzymanie
projektów Bazel w dłuższej perspektywie.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Zamiast walczyć z Xcode i projektami Xcode, Tuist je akceptuje. To te same
koncepcje (np. cele, schematy, ustawienia kompilacji), znany język (tj. Swift)
oraz proste i przyjemne doświadczenie, dzięki czemu utrzymanie i skalowanie
projektów jest zadaniem wszystkich, a nie tylko zespołu platformy iOS.
<!-- -->
:::

## Zasady {#rules}

Bazel wykorzystuje reguły do definiowania sposobu kompilacji i testowania
oprogramowania. Reguły są zapisywane w języku
[Starlark](https://github.com/bazelbuild/starlark), podobnym do języka Python.
Tuist wykorzystuje język Swift jako język konfiguracyjny, co zapewnia
programistom wygodę korzystania z funkcji autouzupełniania, sprawdzania typów i
walidacji programu Xcode. Na przykład poniższa reguła opisuje sposób kompilacji
biblioteki Swift w Bazel:

::: code-group
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

Oto kolejny przykład porównujący sposób definiowania testów jednostkowych w
Bazel i Tuist:

::: code-group
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)

```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Zależności menedżera pakietów Swift {#swift-package-manager-dependencies}

W Bazel można użyć wtyczki
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md),
aby używać pakietów Swift jako zależności. Wtyczka wymaga pliku `Package.swift`
jako źródła informacji o zależnościach. Interfejs Tuist jest pod tym względem
podobny do interfejsu Bazel. Możesz użyć polecenia `tuist install`, aby
rozwiązać i pobrać zależności pakietu. Po zakończeniu rozwiązywania możesz
wygenerować projekt za pomocą polecenia `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Generowanie projektu {#project-generation}

Społeczność udostępnia zestaw reguł
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj) do
generowania projektów Xcode na podstawie projektów zadeklarowanych w Bazel. W
przeciwieństwie do Bazel, gdzie trzeba dodać pewne ustawienia do pliku BUILD` w
katalogu `, Tuist nie wymaga żadnych ustawień. Wystarczy uruchomić polecenie
`tuist generate` w katalogu głównym projektu, a Tuist wygeneruje projekt Xcode.
