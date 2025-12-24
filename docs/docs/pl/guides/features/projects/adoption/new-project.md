---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Utwórz nowy projekt {#create-a-new-project}

Najprostszym sposobem na rozpoczęcie nowego projektu z Tuist jest użycie
polecenia `tuist init`. Polecenie to uruchamia interaktywny interfejs CLI, który
prowadzi użytkownika przez proces konfiguracji projektu. Po wyświetleniu monitu
należy wybrać opcję utworzenia "wygenerowanego projektu".

Następnie można <LocalizedLink href="/guides/features/projects/editing"> edytować projekt</LocalizedLink> uruchamiając `tuist edit`, a Xcode otworzy
projekt, w którym można go edytować. Jednym z generowanych plików jest
`Project.swift`, który zawiera definicję projektu. Jeśli jesteś zaznajomiony z
menedżerem pakietów Swift, pomyśl o nim jak o `Package.swift`, ale z językiem
projektów Xcode.

::: code-group
```swift [Project.swift]
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
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: []
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
<!-- -->
:::

:: info
<!-- -->
Celowo utrzymujemy listę dostępnych szablonów krótką, aby zminimalizować koszty
utrzymania. Jeśli chcesz utworzyć projekt, który nie reprezentuje aplikacji, na
przykład framework, możesz użyć `tuist init` jako punktu wyjścia, a następnie
zmodyfikować wygenerowany projekt do swoich potrzeb.
<!-- -->
:::

## Ręczne tworzenie projektu {#manually-creating-a-project}

Alternatywnie można utworzyć projekt ręcznie. Zalecamy to zrobić tylko wtedy,
gdy jesteś już zaznajomiony z Tuist i jego koncepcjami. Pierwszą rzeczą, którą
musisz zrobić, jest utworzenie dodatkowych katalogów dla struktury projektu:

```bash
mkdir MyFramework
cd MyFramework
```

Następnie utwórz plik `Tuist.swift`, który skonfiguruje Tuist i będzie używany
przez Tuist do określenia katalogu głównego projektu, oraz plik `Project.swift`,
w którym zostanie zadeklarowany projekt:

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyFramework",
    targets: [
        .target(
            name: "MyFramework",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.MyFramework",
            sources: ["MyFramework/Sources/**"],
            dependencies: []
        )
    ]
)
```
```swift [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```
<!-- -->
:::

::: warning
<!-- -->
Tuist używa katalogu `Tuist/` do określenia katalogu głównego projektu, a
następnie szuka innych plików manifestu globalizujących katalogi. Zalecamy
utworzenie tych plików w wybranym edytorze i od tego momentu można użyć `tuist
edit` do edycji projektu za pomocą Xcode.
<!-- -->
:::
