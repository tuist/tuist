---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Udostępnianie kodu {#code-sharing}

Jedną z niedogodności Xcode podczas pracy z dużymi projektami jest to, że nie
pozwala on na ponowne wykorzystanie elementów projektów innych niż ustawienia
kompilacji poprzez pliki `.xcconfig`. Możliwość ponownego wykorzystania
definicji projektów jest przydatna z następujących powodów:

- Ułatwia to utrzymanie **** , ponieważ zmiany można wprowadzać w jednym
  miejscu, a wszystkie projekty otrzymują je automatycznie.
- Umożliwia to zdefiniowanie konwencji **** , do których mogą dostosować się
  nowe projekty.
- Projekty są bardziej spójne **** , dzięki czemu prawdopodobieństwo wystąpienia
  błędów kompilacji spowodowanych niespójnościami jest znacznie mniejsze.
- Dodawanie nowych projektów staje się łatwym zadaniem, ponieważ możemy ponownie
  wykorzystać istniejącą logikę.

Ponowne wykorzystanie kodu w plikach manifestu jest możliwe w Tuist dzięki
koncepcji pomocników opisu projektu typu „ **”**.

::: tip A TUIST UNIQUE ASSET
<!-- -->
Wiele organizacji lubi Tuist, ponieważ widzą w opisach projektów pomocników
platformę dla zespołów platformowych do kodyfikowania własnych konwencji i
tworzenia własnego języka do opisywania swoich projektów. Na przykład generatory
projektów oparte na YAML muszą wymyślić własne, oparte na YAML, zastrzeżone
rozwiązanie szablonowe lub zmusić organizacje do tworzenia narzędzi w oparciu o
nie.
<!-- -->
:::

## Pomocnicy opisujący projekt {#project-description-helpers}

Pomocniki opisu projektu to pliki Swift, które są kompilowane do modułu
`ProjectDescriptionHelpers`, który może być importowany przez pliki manifestu.
Moduł jest kompilowany poprzez zebranie wszystkich plików z katalogu
`Tuist/ProjectDescriptionHelpers`.

Możesz zaimportować je do pliku manifestu, dodając instrukcję importu na
początku pliku:

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

Poniższe fragmenty zawierają przykład rozszerzenia modelu projektu `` w celu
dodania konstruktorów statycznych oraz wykorzystania ich w pliku
`Project.swift`:

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
Zwróć uwagę, że za pomocą funkcji definiujemy konwencje dotyczące nazwy celów,
identyfikatora pakietu i struktury folderów.
<!-- -->
:::
