---
{
  "title": "Create a new project",
  "titleTemplate": ":title · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to create a new project with Tuist."
}
---
# Utwórz nowy projekt {#create-a-new-project}

Najprostszym sposobem rozpoczęcia nowego projektu w Tuist jest użycie polecenia
`tuist init`. Polecenie to uruchamia interaktywny interfejs CLI, który
poprowadzi Cię przez proces konfiguracji projektu. Po wyświetleniu monitu
wybierz opcję utworzenia „wygenerowanego projektu”.

Następnie możesz
<LocalizedLink href="/guides/features/projects/editing">edytować
projekt</LocalizedLink>, uruchamiając `tuist edit`, a Xcode otworzy projekt, w
którym możesz go edytować. Jednym z wygenerowanych plików jest `Project.swift`,
który zawiera definicję projektu. Jeśli znasz menedżera pakietów Swift,
potraktuj go jako `Package.swift`, ale w języku projektów Xcode.

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
Celowo ograniczamy listę dostępnych szablonów, aby zminimalizować nakłady
związane z utrzymaniem. Jeśli chcesz utworzyć projekt, który nie reprezentuje
aplikacji, na przykład framework, możesz użyć `tuist init` jako punktu wyjścia,
a następnie zmodyfikować wygenerowany projekt zgodnie z własnymi potrzebami.
<!-- -->
:::

## Ręczne tworzenie projektu {#manually-creating-a-project}

Alternatywnie możesz utworzyć projekt ręcznie. Zalecamy to tylko wtedy, gdy
znasz już Tuist i jego koncepcje. Pierwszą rzeczą, którą musisz zrobić, jest
utworzenie dodatkowych katalogów dla struktury projektu:

```bash
mkdir MyFramework
cd MyFramework
```

Następnie utwórz plik `Tuist.swift`, który skonfiguruje Tuist i będzie używany
przez Tuist do określenia katalogu głównego projektu, oraz plik `Project.swift`,
w którym zostanie zadeklarowany Twój projekt:

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
następnie szuka innych plików manifestu, przeszukując katalogi. Zalecamy
utworzenie tych plików za pomocą wybranego edytora, a następnie użycie polecenia
`tuist edit` do edycji projektu w Xcode.
<!-- -->
:::
