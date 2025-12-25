---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Migracja projektu XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) to narzędzie do generowania
projektów, które wykorzystuje YAML jako [format
konfiguracji](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
do definiowania projektów Xcode. Wiele organizacji **zaadoptowało je, próbując
uciec od częstych konfliktów Git, które pojawiają się podczas pracy z projektami
Xcode.** Jednak częste konflikty Git to tylko jeden z wielu problemów, których
doświadczają organizacje. Xcode naraża programistów na wiele zawiłości i
niejawnych konfiguracji, które utrudniają utrzymanie i optymalizację projektów
na dużą skalę. XcodeGen nie spełnia tego zadania, ponieważ jest to narzędzie do
generowania projektów Xcode, a nie menedżer projektów. Jeśli potrzebujesz
narzędzia, które pomoże Ci poza generowaniem projektów Xcode, możesz rozważyć
Tuist.

::: tip SWIFT OVER YAML
<!-- -->
Wiele organizacji preferuje Tuist jako narzędzie do generowania projektów,
ponieważ wykorzystuje on Swift jako format konfiguracji. Swift to język
programowania, z którym programiści są zaznajomieni i który zapewnia im wygodę
korzystania z funkcji autouzupełniania, sprawdzania typów i walidacji Xcode.
<!-- -->
:::

Poniżej znajduje się kilka uwag i wskazówek, które pomogą w migracji projektów z
XcodeGen do Tuist.

## Generowanie projektu {#project-generation}

Zarówno Tuist, jak i XcodeGen udostępniają polecenie `generate`, które
przekształca deklarację projektu w projekty i obszary robocze Xcode.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Różnica polega na sposobie edycji. W Tuist można uruchomić polecenie `tuist
edit`, które generuje projekt Xcode w locie, który można otworzyć i rozpocząć
pracę. Jest to szczególnie przydatne, gdy chcesz szybko wprowadzić zmiany w
projekcie.

## `project.yaml` {#projectyaml}

Plik opisu XcodeGen `project.yaml` staje się `Project.swift`. Ponadto można mieć
`Workspace.swift` jako sposób na dostosowanie sposobu grupowania projektów w
obszarach roboczych. Można również mieć projekt `Project.swift` z obiektami
docelowymi, które odwołują się do obiektów docelowych z innych projektów. W
takich przypadkach Tuist wygeneruje Xcode Workspace zawierający wszystkie
projekty.

::: code-group

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

::: tip XCODE'S LANGUAGE
<!-- -->
Zarówno XcodeGen, jak i Tuist wykorzystują język i koncepcje Xcode. Jednak
konfiguracja Tuist oparta na języku Swift zapewnia wygodę korzystania z funkcji
autouzupełniania, sprawdzania typu i walidacji Xcode.
<!-- -->
:::

## Szablony specyfikacji {#spec-templates}

Jedną z wad YAML jako języka konfiguracji projektu jest to, że nie obsługuje on
możliwości ponownego wykorzystania plików YAML po wyjęciu z pudełka. Jest to
powszechna potrzeba przy opisywaniu projektów, którą XcodeGen musiał rozwiązać
za pomocą własnego rozwiązania o nazwie *"templates"*. W Tuist możliwość
ponownego użycia jest wbudowana w sam język Swift i poprzez moduł Swift o nazwie
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>, który umożliwia ponowne użycie kodu we wszystkich
plikach manifestu.

::: code-group
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
