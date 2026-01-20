---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Udostępnianie kodu {#code-sharing}

Jedną z niedogodności Xcode, gdy używamy go z dużymi projektami, jest to, że nie
pozwala on na ponowne wykorzystanie elementów projektów innych niż ustawienia
kompilacji za pośrednictwem plików `.xcconfig`. Możliwość ponownego
wykorzystania definicji projektu jest przydatna z następujących powodów:

- Ułatwia to konserwację **** , ponieważ zmiany można wprowadzać w jednym
  miejscu, a wszystkie projekty otrzymują je automatycznie.
- Umożliwia to zdefiniowanie konwencji **** , z którymi mogą być zgodne nowe
  projekty.
- Projekty są bardziej **spójne** i dlatego prawdopodobieństwo zepsutych
  kompilacji z powodu niespójności jest znacznie mniejsze.
- Dodanie nowego projektu staje się łatwym zadaniem, ponieważ możemy ponownie
  wykorzystać istniejącą logikę.

Ponowne wykorzystanie kodu w plikach manifestu jest możliwe w Tuist dzięki
koncepcji pomocników opisu projektu **** .

::: tip A TUIST UNIQUE ASSET
<!-- -->
Wiele organizacji lubi Tuist, ponieważ widzą w narzędziach pomocniczych do opisu
projektów platformę dla zespołów platformowych do kodyfikowania własnych
konwencji i wymyślania własnego języka do opisywania swoich projektów. Na
przykład, generatory projektów oparte na YAML muszą wymyślić własne rozwiązanie
szablonowe oparte na YAML lub zmusić organizacje do budowania swoich narzędzi.
<!-- -->
:::

## Pomocnicy opisu projektu {#project-description-helpers}

Pomocnicy opisu projektu to pliki Swift, które są kompilowane do modułu
`ProjectDescriptionHelpers`, który może importować pliki manifestu. Moduł jest
kompilowany poprzez zebranie wszystkich plików w katalogu
`Tuist/ProjectDescriptionHelpers`.

Można je zaimportować do pliku manifestu, dodając instrukcję importu w górnej
części pliku:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` są dostępne w następujących manifestach:
- `Project.swift`
- `Package.swift` (tylko za flagą kompilatora `#TUIST` )
- `Workspace.swift`

## Przykład {#example}

Poniższe fragmenty zawierają przykład tego, jak rozszerzamy model `Project`, aby
dodać statyczne konstruktory i jak ich używamy z pliku `Project.swift`:

::: code-group
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
<!-- -->
:::

::: tip A TOOL TO ESTABLISH CONVENTIONS
<!-- -->
Zwróć uwagę, jak za pomocą funkcji definiujemy konwencje dotyczące nazw obiektów
docelowych, identyfikatora pakietu i struktury folderów.
<!-- -->
:::
