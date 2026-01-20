---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Wtyczki {#plugins}

Wtyczki są narzędziem do udostępniania i ponownego wykorzystywania artefaktów
Tuist w wielu projektach. Obsługiwane są następujące artefakty:

- <LocalizedLink href="/guides/features/projects/code-sharing">Pomocnicy opisu projektu</LocalizedLink> w wielu projektach.
- <LocalizedLink href="/guides/features/projects/templates">Szablony</LocalizedLink>
  w wielu projektach.
- Zadania w wielu projektach.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Szablon Resource Accessor</LocalizedLink> w wielu projektach

Należy pamiętać, że wtyczki zostały zaprojektowane jako prosty sposób na
rozszerzenie funkcjonalności Tuist. W związku z tym istnieją **pewne
ograniczenia, które należy wziąć pod uwagę**:

- Wtyczka nie może zależeć od innej wtyczki.
- Wtyczka nie może zależeć od pakietów Swift innych firm
- Wtyczka nie może używać pomocników opisu projektu z projektu, który używa
  wtyczki.

Jeśli potrzebujesz większej elastyczności, rozważ zasugerowanie funkcji dla
narzędzia lub zbudowanie własnego rozwiązania w oparciu o strukturę generowania
Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Typy wtyczek {#plugin-types}

### Wtyczka pomocnicza opisu projektu {#project-description-helper-plugin}

Wtyczka pomocnicza opisu projektu jest reprezentowana przez katalog zawierający
plik manifestu `Plugin.swift`, który deklaruje nazwę wtyczki oraz katalog
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

### Wtyczka szablonów akcesorów zasobów {#resource-accessor-templates-plugin}

Jeśli potrzebujesz udostępnić
<LocalizedLink href="/guides/features/projects/synthesized-files#resource-accessors">syntetyzowane akcesory zasobów</LocalizedLink>, możesz użyć tego typu wtyczki. Wtyczka jest
reprezentowana przez katalog zawierający plik manifestu `Plugin.swift`, który
deklaruje nazwę wtyczki oraz katalog `ResourceSynthesizers` zawierający pliki
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

Nazwa szablonu to [camel case](https://en.wikipedia.org/wiki/Camel_case) wersja
typu zasobu:

| Typ zasobu              | Nazwa pliku szablonu     |
| ----------------------- | ------------------------ |
| Struny                  | Strings.stencil          |
| Aktywa                  | Assets.stencil           |
| Listy nieruchomości     | Plists.stencil           |
| Czcionki                | Fonts.stencil            |
| Dane podstawowe         | CoreData.stencil         |
| Konstruktor interfejsów | InterfaceBuilder.stencil |
| JSON                    | JSON.stencil             |
| YAML                    | YAML.stencil             |

Podczas definiowania syntezatorów zasobów w projekcie można określić nazwę
wtyczki, aby użyć szablonów z wtyczki:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Wtyczka zadań <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Wtyczki zadań są przestarzałe. Sprawdź [ten wpis na
blogu](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects), jeśli
szukasz rozwiązania automatyzacji dla swojego projektu.
<!-- -->
:::

Zadania to `$PATH`-eksponowane pliki wykonywalne, które można wywołać za pomocą
polecenia `tuist`, jeśli są zgodne z konwencją nazewnictwa `tuist-`. We
wcześniejszych wersjach Tuist zapewniał pewne słabe konwencje i narzędzia pod
`tuist plugin` do `build`, `run`, `test` i `archive` zadań reprezentowanych
przez pliki wykonywalne w pakietach Swift, ale przestaliśmy korzystać z tej
funkcji, ponieważ zwiększa ona obciążenie związane z utrzymaniem i złożoność
narzędzia.

Jeśli korzystasz z Tuist do dystrybucji zadań, zalecamy zbudowanie swojego
- Możesz nadal korzystać z `ProjectAutomation.xcframework` dystrybuowanego z
  każdą wersją Tuist, aby mieć dostęp do grafu projektu z poziomu logiki za
  pomocą `let graph = try Tuist.graph()`. Polecenie wykorzystuje proces
  systemowy do uruchomienia polecenia `tuist` i zwraca reprezentację grafu
  projektu w pamięci.
- Aby dystrybuować zadania, zalecamy dołączenie grubego pliku binarnego
  obsługującego `arm64` i `x86_64` w wydaniach GitHub i użycie
  [Mise](https://mise.jdx.dev) jako narzędzia instalacyjnego. Aby poinstruować
  Mise, jak zainstalować narzędzie, potrzebne będzie repozytorium wtyczek.
  Możesz użyć [Tuist's](https://github.com/asdf-community/asdf-tuist) jako
  odniesienia.
- Jeśli nazwiesz swoje narzędzie `tuist-{xxx}` i użytkownicy mogą je
  zainstalować uruchamiając `mise install`, mogą je uruchomić bezpośrednio lub
  poprzez `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Planujemy skonsolidować modele `ProjectAutomation` i `XcodeGraph` w jeden,
kompatybilny wstecz framework, który udostępni użytkownikowi cały graf projektu.
Co więcej, wyodrębnimy logikę generowania do nowej warstwy, `XcodeGraph`, której
można również używać z własnego CLI. Pomyśl o tym jak o budowaniu własnego
Tuist.
<!-- -->
:::

## Korzystanie z wtyczek {#using-plugins}

Aby użyć wtyczki, należy dodać ją do pliku manifestu projektu
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Jeśli chcesz ponownie użyć wtyczki w projektach, które znajdują się w różnych
repozytoriach, możesz przesłać wtyczkę do repozytorium Git i odwołać się do niej
w pliku `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Po dodaniu wtyczek, `tuist install` pobierze wtyczki z globalnego katalogu
cache.

::: info NO VERSION RESOLUTION
<!-- -->
Jak być może zauważyłeś, nie zapewniamy rozdzielczości wersji dla wtyczek.
Zalecamy używanie tagów Git lub SHA, aby zapewnić powtarzalność.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
W przypadku korzystania z wtyczki pomocników opisu projektu, nazwa modułu
zawierającego pomocników jest nazwą wtyczki
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
