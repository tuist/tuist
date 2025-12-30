---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# Migracja projektu Bazel {#migrate-a-bazel-project}

[Bazel](https://bazel.build) to system kompilacji, który Google udostępniło w
2015 roku. Jest to potężne narzędzie, które pozwala szybko i niezawodnie tworzyć
i testować oprogramowanie dowolnej wielkości. Korzystają z niego niektóre duże
organizacje, takie jak
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/),
[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
czy [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel), jednak jego
wdrożenie i utrzymanie wymaga początkowych (tj. nauki technologii) i ciągłych
inwestycji (tj. nadążania za aktualizacjami Xcode). Chociaż sprawdza się to w
przypadku niektórych organizacji, które traktują to jako kwestię przekrojową,
może nie być najlepszym rozwiązaniem dla innych, które chcą skupić się na
rozwoju swoich produktów. Na przykład widzieliśmy organizacje, których zespół
platformy iOS wprowadził Bazel i musiał go porzucić po tym, jak inżynierowie,
którzy kierowali wysiłkiem, opuścili firmę. Stanowisko Apple w sprawie silnego
sprzężenia między Xcode a systemem kompilacji jest kolejnym czynnikiem, który
utrudnia utrzymanie projektów Bazel w czasie.

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Zamiast walczyć z Xcode i projektami Xcode, Tuist je obejmuje. To te same
koncepcje (np. cele, schematy, ustawienia kompilacji), znajomy język (tj. Swift)
oraz proste i przyjemne doświadczenie, które sprawia, że utrzymywanie i
skalowanie projektów jest zadaniem każdego, a nie tylko zespołu platformy iOS.
<!-- -->
:::

## Zasady {#rules}

Bazel wykorzystuje reguły do definiowania sposobu tworzenia i testowania
oprogramowania. Reguły są napisane w języku
[Starlark](https://github.com/bazelbuild/starlark), podobnym do Pythona. Tuist
używa języka Swift jako języka konfiguracyjnego, który zapewnia programistom
wygodę korzystania z funkcji autouzupełniania, sprawdzania typu i walidacji
Xcode. Przykładowo, poniższa reguła opisuje sposób tworzenia biblioteki Swift w
Bazel:

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


## Zależności Menedżera pakietów Swift {#swift-package-manager-dependencies}

W Bazel można użyć wtyczki
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
wtyczki do używania pakietów Swift jako zależności. Wtyczka wymaga pliku
`Package.swift` jako źródła prawdy dla zależności. Interfejs Tuist jest w tym
sensie podobny do interfejsu Bazel. Możesz użyć polecenia `tuist install`, aby
rozwiązać i pobrać zależności pakietu. Po zakończeniu rozwiązywania można
następnie wygenerować projekt za pomocą polecenia `tuist generate`.

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## Generowanie projektu {#project-generation}

Społeczność udostępnia zestaw reguł,
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj), do
generowania projektów Xcode z projektów zadeklarowanych przez Bazel. W
przeciwieństwie do Bazel, gdzie trzeba dodać pewną konfigurację do pliku
`BUILD`, Tuist nie wymaga żadnej konfiguracji. Możesz uruchomić `tuist generate`
w katalogu głównym swojego projektu, a Tuist wygeneruje dla ciebie projekt
Xcode.
