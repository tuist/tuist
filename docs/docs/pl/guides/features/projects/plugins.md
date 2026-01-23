---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Wtyczki {#plugins}

Wtyczki są narzędziem służącym do udostępniania i ponownego wykorzystywania
artefaktów Tuist w wielu projektach. Obsługiwane są następujące artefakty:

- <LocalizedLink href="/guides/features/projects/code-sharing">Pomocnicy
  opisujący projekt</LocalizedLink> w wielu projektach.
- <LocalizedLink href="/guides/features/projects/templates">Szablony</LocalizedLink>
  w wielu projektach.
- Zadania w wielu projektach.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Szablon
  dostępu do zasobów</LocalizedLink> w wielu projektach

**Należy pamiętać, że wtyczki zostały zaprojektowane jako prosty sposób na
rozszerzenie funkcjonalności Tuist. Dlatego też istnieją pewne ograniczenia,
które należy wziąć pod uwagę**:

- Wtyczka nie może być zależna od innej wtyczki.
- Wtyczka nie może być zależna od pakietów Swift innych producentów.
- Wtyczka nie może korzystać z pomocników opisu projektu z projektu, który
  korzysta z tej wtyczki.

Jeśli potrzebujesz większej elastyczności, rozważ zaproponowanie funkcji dla
narzędzia lub stworzenie własnego rozwiązania w oparciu o framework generowania
Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Typy wtyczek {#plugin-types}

### Wtyczka pomocnicza do opisu projektu {#project-description-helper-plugin}

Wtyczka pomocnicza opisu projektu jest reprezentowana przez katalog zawierający
plik manifestu `Plugin.swift`, który deklaruje nazwę wtyczki, oraz katalog
`ProjectDescriptionHelpers` zawierający pomocnicze pliki Swift.

::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ProjectDescriptionHelpers
└── ...
```
<!-- -->
:::

### Wtyczka szablonów dostępu do zasobów {#resource-accessor-templates-plugin}

Jeśli chcesz udostępnić
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">syntetyzowane
akcesory zasobów</LocalizedLink>, możesz użyć tego typu wtyczki. Wtyczka jest
reprezentowana przez katalog zawierający plik manifestu `Plugin.swift`, który
deklaruje nazwę wtyczki, oraz katalog `ResourceSynthesizers` zawierający pliki
szablonów akcesorów zasobów.


::: code-group
```bash [Plugin.swift]
import ProjectDescription

let plugin = Plugin(name: "MyPlugin")
```
```bash [Directory structure]
.
├── ...
├── Plugin.swift
├── ResourceSynthesizers
├───── Strings.stencil
├───── Plists.stencil
├───── CustomTemplate.stencil
└── ...
```
<!-- -->
:::

Nazwa szablonu jest wersją typu zasobu w formacie [camel
case](https://en.wikipedia.org/wiki/Camel_case):

| Typ zasobu        | Nazwa pliku szablonu     |
| ----------------- | ------------------------ |
| Ciągi znaków      | Strings.stencil          |
| Zasoby            | Assets.stencil           |
| Listy właściwości | Plists.stencil           |
| Czcionki          | Fonts.stencil            |
| Dane podstawowe   | CoreData.stencil         |
| Interface Builder | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

Podczas definiowania syntezatorów zasobów w projekcie można określić nazwę
wtyczki, aby używać szablonów z tej wtyczki:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Wtyczka zadania <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Wtyczki zadań są przestarzałe. Jeśli szukasz rozwiązania do automatyzacji
swojego projektu, zapoznaj się z [tym wpisem na
blogu](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).
<!-- -->
:::

`Zadania są plikami wykonywalnymi $PATH`-exposed, które można wywołać za pomocą
polecenia `tuist`, jeśli są zgodne z konwencją nazewniczą `tuist-`. We
wcześniejszych wersjach Tuist udostępniał kilka słabych konwencji i narzędzi w
ramach `tuist plugin` do `build`, `run`, `test` i `archive` zadań
reprezentowanych przez pliki wykonywalne w pakietach Swift, ale wycofaliśmy tę
funkcję, ponieważ zwiększała ona obciążenie związane z utrzymaniem i złożoność
narzędzia.

Jeśli używasz Tuist do dystrybucji zadań, zalecamy stworzenie
- Możesz nadal korzystać z `ProjectAutomation.xcframework` dystrybuowanego wraz
  z każdą wersją Tuist, aby uzyskać dostęp do wykresu projektu z poziomu logiki
  za pomocą `let graph = try Tuist.graph()`. Polecenie wykorzystuje proces
  systemowy do uruchomienia `tuist` i zwraca reprezentację wykresu projektu w
  pamięci.
- Aby rozdzielić zadania, zalecamy dołączenie pliku binarnego obsługującego
  `arm64` i `x86_64` w wydaniach GitHub oraz użycie [Mise](https://mise.jdx.dev)
  jako narzędzia instalacyjnego. Aby poinstruować Mise, jak zainstalować
  narzędzie, potrzebne jest repozytorium wtyczek. Jako punkt odniesienia można
  użyć [Tuist's](https://github.com/asdf-community/asdf-tuist).
- Jeśli nazwiesz swoje narzędzie `tuist-{xxx}`, a użytkownicy będą mogli je
  zainstalować, uruchamiając `mise install`, będą mogli je uruchomić
  bezpośrednio lub poprzez `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Planujemy skonsolidować modele `ProjectAutomation` i `XcodeGraph` w jedną,
kompatybilną wstecznie strukturę, która udostępnia użytkownikowi całość wykresu
projektu. Ponadto wyodrębnimy logikę generowania do nowej warstwy, `XcodeGraph`,
z której można również korzystać z własnego interfejsu CLI. Potraktuj to jako
tworzenie własnego Tuist.
<!-- -->
:::

## Korzystanie z wtyczek {#using-plugins}

Aby użyć wtyczki, musisz dodać ją do pliku manifestu
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>
swojego projektu:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Jeśli chcesz ponownie wykorzystać wtyczkę w różnych projektach znajdujących się
w różnych repozytoriach, możesz przesłać swoją wtyczkę do repozytorium Git i
odwołać się do niej w pliku `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Po dodaniu wtyczek, polecenie `tuist install` pobierze wtyczki do globalnego
katalogu pamięci podręcznej.

::: info NO VERSION RESOLUTION
<!-- -->
Jak zapewne zauważyłeś, nie zapewniamy rozwiązań dotyczących wersji wtyczek.
Zalecamy stosowanie tagów Git lub SHA, aby zapewnić powtarzalność.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
W przypadku korzystania z wtyczki pomocy opisu projektu nazwa modułu
zawierającego pomoc jest nazwą wtyczki.
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
