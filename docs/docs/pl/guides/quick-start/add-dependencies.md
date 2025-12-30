---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# Dodaj zależności {#add-dependencies}

Często zdarza się, że projekty zależą od bibliotek innych firm w celu
zapewnienia dodatkowej funkcjonalności. Aby to zrobić, uruchom następujące
polecenie, aby uzyskać najlepsze wrażenia z edycji projektu:

```bash
tuist edit
```

Otworzy się projekt Xcode zawierający pliki projektu. Edytuj plik
`Package.swift` i dodaj plik

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

Następnie edytuj cel aplikacji w swoim projekcie, aby zadeklarować `Kingfisher`
jako zależność:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            buildableFolders: [
                "MyApp/Sources",
                "MyApp/Resources",
            ],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

Następnie uruchom `tuist install`, aby rozwiązać i pobrać zależności za pomocą
[Swift Package Manager](https://www.swift.org/documentation/package-manager/).

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Zalecane przez Tuist podejście do zależności wykorzystuje Swift Package Manager
(SPM) wyłącznie do rozwiązywania zależności. Następnie Tuist konwertuje je na
projekty Xcode i obiekty docelowe w celu zapewnienia maksymalnej
konfigurowalności i kontroli.
<!-- -->
:::

## Wizualizacja projektu {#visualize-the-project}

Strukturę projektu można zwizualizować, uruchamiając ją:

```bash
tuist graph
```

Polecenie wyświetli i otworzy plik `graph.png` w katalogu projektu:

![Wykres projektu](/images/guides/quick-start/graph.png)

## Użyj zależności {#use-the-dependency}

Uruchom `tuist generate`, aby otworzyć projekt w Xcode i wprowadź następujące
zmiany w pliku `ContentView.swift`:

```swift
import SwiftUI
import Kingfisher // [!code ++]

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("Hello, World!") // [!code --]
            .padding() // [!code --]
        KFImage(URL(string: "https://cloud.tuist.io/images/tuist_logo_32x32@2x.png")!) // [!code ++]
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

Uruchom aplikację z Xcode, a powinieneś zobaczyć obraz załadowany z adresu URL.
