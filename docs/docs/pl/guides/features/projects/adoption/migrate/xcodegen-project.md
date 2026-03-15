---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Przenieś projekt XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) to narzędzie do generowania
projektów, które wykorzystuje YAML jako [format
konfiguracji](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
do definiowania projektów Xcode. Wiele organizacji **zaadoptowało je, próbując
uciec od częstych konfliktów Git, które pojawiają się podczas pracy z projektami
Xcode.** Jednak częste konflikty Git to tylko jeden z wielu problemów, których
doświadczają organizacje. Xcode naraża deweloperów na wiele zawiłości i
niejawnych konfiguracji, które utrudniają utrzymanie i optymalizację projektów
na dużą skalę. XcodeGen nie spełnia tego zadania, ponieważ jest to narzędzie do
generowania projektów Xcode, a nie menedżer projektów. Jeśli potrzebujesz
narzędzia, które pomoże Ci poza generowaniem projektów Xcode, możesz rozważyć
Tuist.

::: tip SWIFT OVER YAML
<!-- -->
Wiele organizacji preferuje również Tuist jako narzędzie do generowania
projektów, ponieważ wykorzystuje ono Swift jako format konfiguracyjny. Swift
jest językiem programowania, który jest znany programistom i zapewnia im wygodę
korzystania z funkcji autouzupełniania, sprawdzania typów i walidacji w Xcode.
<!-- -->
:::

Poniżej przedstawiono kilka wskazówek i wytycznych, które pomogą Ci przenieść
projekty z XcodeGen do Tuist.

## Generowanie projektu {#project-generation}

Zarówno Tuist, jak i XcodeGen udostępniają polecenie „ `” oraz „generate` ”,
które przekształcają deklarację projektu w projekty i obszary robocze Xcode.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

Różnica polega na sposobie edycji. Dzięki Tuist możesz uruchomić polecenie `
`tuist edit` `, które generuje na bieżąco projekt Xcode, który możesz otworzyć i
zacząć nad nim pracować. Jest to szczególnie przydatne, gdy chcesz szybko
wprowadzić zmiany w swoim projekcie.

## `project.yaml` {#projectyaml}

Plik opisowy XcodeGen `project.yaml` staje się `Project.swift`. Ponadto możesz
mieć `Workspace.swift` jako sposób na dostosowanie sposobu grupowania projektów
w obszarach roboczych. Możesz również mieć projekt `Project.swift` z celami,
które odwołują się do celów z innych projektów. W takich przypadkach Tuist
wygeneruje obszar roboczy Xcode zawierający wszystkie projekty.

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
autouzupełniania, sprawdzania typów i walidacji dostępnych w Xcode.
<!-- -->
:::

## Szablony specyfikacji {#spec-templates}

Jedną z wad języka YAML jako języka do konfiguracji projektów jest to, że nie
obsługuje on od razu ponownego wykorzystania plików YAML. Jest to powszechna
potrzeba podczas opisywania projektów, którą XcodeGen musiał rozwiązać za pomocą
własnego, zastrzeżonego rozwiązania o nazwie „szablony” ** . W Tuist możliwość
ponownego wykorzystania jest wbudowana w sam język, Swift, oraz poprzez moduł
Swift o nazwie
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink>, który pozwala na ponowne wykorzystanie kodu we
wszystkich plikach manifestu.

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
