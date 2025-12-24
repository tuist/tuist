---
{
  "title": "Manifests",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the manifest files that Tuist uses to define projects and workspaces and configure the generation process."
}
---
# Manifesty {#manifests}

Tuist domyślnie wykorzystuje pliki Swift jako podstawowy sposób definiowania
projektów i obszarów roboczych oraz konfigurowania procesu generowania. Pliki te
są określane jako pliki manifestu **** w całej dokumentacji.

Decyzja o użyciu języka Swift została zainspirowana przez [Swift Package
Manager](https://www.swift.org/documentation/package-manager/), który również
wykorzystuje pliki Swift do definiowania pakietów. Dzięki wykorzystaniu języka
Swift możemy wykorzystać kompilator do sprawdzenia poprawności treści i
ponownego wykorzystania kodu w różnych plikach manifestu, a Xcode do zapewnienia
pierwszorzędnego doświadczenia edycyjnego dzięki podświetlaniu składni,
automatycznemu uzupełnianiu i sprawdzaniu poprawności.

::: info CACHING
<!-- -->
Ponieważ pliki manifestu są plikami Swift, które muszą zostać skompilowane,
Tuist buforuje wyniki kompilacji, aby przyspieszyć proces analizowania. Dlatego
też przy pierwszym uruchomieniu Tuist wygenerowanie projektu może potrwać nieco
dłużej. Kolejne uruchomienia będą szybsze.
<!-- -->
:::

## Project.swift {#projectswift}

Manifest
<LocalizedLink href="/references/project-description/structs/project">`Project.swift`</LocalizedLink>
deklaruje projekt Xcode. Projekt zostanie wygenerowany w tym samym katalogu, w
którym znajduje się plik manifestu o nazwie wskazanej we właściwości `name`.

```swift
// Project.swift
let project = Project(
    name: "App",
    targets: [
        // ....
    ]
)
```


::: ostrzeżenie ROOT VARIABLES
<!-- -->
Jedyną zmienną, która powinna znajdować się w katalogu głównym manifestu jest
`let project = Project(...)`. Jeśli chcesz ponownie użyć kodu w różnych
częściach manifestu, możesz użyć funkcji Swift.
<!-- -->
:::

## Workspace.swift {#workspaceswift}

Domyślnie Tuist generuje [Xcode
Workspace](https://developer.apple.com/documentation/xcode/projects-and-workspaces)
zawierający generowany projekt i projekty od niego zależne. Jeśli z
jakiegokolwiek powodu chcesz dostosować obszar roboczy, aby dodać dodatkowe
projekty lub dołączyć pliki i grupy, możesz to zrobić, definiując manifest
<LocalizedLink href="/references/project-description/structs/workspace">`Workspace.swift`</LocalizedLink>.

```swift
// Workspace.swift
import ProjectDescription

let workspace = Workspace(
    name: "App-Workspace",
    projects: [
        "./App", // Path to directory containing the Project.swift file
    ]
)
```

:: info
<!-- -->
Tuist rozwiąże graf zależności i dołączy projekty zależności do obszaru
roboczego. Nie trzeba dołączać ich ręcznie. Jest to konieczne, aby system
kompilacji poprawnie rozwiązał zależności.
<!-- -->
:::

### Wiele lub jeden projekt {#multi-or-monoproject}

Często pojawia się pytanie, czy używać pojedynczego projektu, czy wielu
projektów w obszarze roboczym. W świecie bez Tuist, w którym konfiguracja
jednego projektu prowadziłaby do częstych konfliktów Git, zaleca się korzystanie
z przestrzeni roboczych. Ponieważ jednak nie zalecamy włączania wygenerowanych
przez Tuist projektów Xcode do repozytorium Git, konflikty Git nie stanowią
problemu. W związku z tym decyzja o korzystaniu z pojedynczego projektu lub
wielu projektów w obszarze roboczym należy do użytkownika.

W projekcie Tuist opieramy się na mono-projektach, ponieważ czas generowania na
zimno jest szybszy (mniej plików manifestu do skompilowania) i wykorzystujemy
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink> jako jednostkę enkapsulacji. Możesz jednak chcieć użyć
projektów Xcode jako jednostki enkapsulacji do reprezentowania różnych domen
aplikacji, co jest bardziej zgodne z zalecaną strukturą projektu Xcode.

## Tuist.swift {#tuistswift}

Tuist zapewnia
<LocalizedLink href="/contributors/principles.html#default-to-conventions">sensowne ustawienia domyślne</LocalizedLink> w celu uproszczenia konfiguracji projektu.
Można jednak dostosować konfigurację, definiując
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
w katalogu głównym projektu, który jest używany przez Tuist do określenia
katalogu głównego projektu.

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(generationOptions: .options(enforceExplicitDependencies: true))
)
```
