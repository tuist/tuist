---
{
  "title": "Plugins",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use plugins in Tuist to extend its functionality."
}
---
# Wtyczki {#plugins}

Wtyczki to narzędzie służące do udostępniania i ponownego wykorzystywania
artefaktów Tuist w wielu projektach. Obsługiwane są następujące artefakty:

- <LocalizedLink href="/guides/features/projects/code-sharing">Pomocnicy opisów
  projektów</LocalizedLink> w wielu projektach.
- <LocalizedLink href="/guides/features/projects/templates">Szablony</LocalizedLink>
  w wielu projektach.
- Zadania w wielu projektach.
- <LocalizedLink href="/guides/features/projects/synthesized-files">Szablon
  akcesora zasobów</LocalizedLink> w wielu projektach

Należy pamiętać, że wtyczki zostały zaprojektowane jako prosty sposób na
rozszerzenie funkcjonalności Tuist. W związku z tym istnieją pewne ograniczenia,
które należy wziąć pod uwagę **** :

- Wtyczka nie może być zależna od innej wtyczki.
- Wtyczka nie może opierać się na pakietach Swift innych firm
- Wtyczka nie może korzystać z pomocników opisu projektu z projektu, który
  korzysta z tej wtyczki.

Jeśli potrzebujesz większej elastyczności, rozważ zgłoszenie sugestii dotyczącej
funkcji narzędzia lub stworzenie własnego rozwiązania w oparciu o framework
generujący Tuist,
[`TuistGenerator`](https://github.com/tuist/tuist/tree/main/Sources/TuistGenerator).

## Typy wtyczek {#plugin-types}

### Wtyczka pomocnicza do opisu projektu {#project-description-helper-plugin}

Wtyczka pomocnicza do opisu projektu jest reprezentowana przez katalog
zawierający plik manifestu `Plugin.swift`, który deklaruje nazwę wtyczki, oraz
katalog `ProjectDescriptionHelpers` zawierający pomocnicze pliki Swift.

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

Nazwa szablonu to wersja typu zasobu zapisana w stylu [camel
case](https://en.wikipedia.org/wiki/Camel_case):

| Typ zasobu        | Nazwa pliku szablonu     |
| ----------------- | ------------------------ |
| Ciągi znaków      | Strings.stencil          |
| Zasoby            | Assets.stencil           |
| Listy właściwości | Plists.stencil           |
| Czcionki          | Fonts.stencil            |
| Podstawowe dane   | CoreData.stencil         |
| Interface Builder | InterfaceBuilder.stencil |
| JSON              | JSON.stencil             |
| YAML              | YAML.stencil             |

Podczas definiowania syntezatorów zasobów w projekcie można określić nazwę
wtyczki, aby korzystać z szablonów z tej wtyczki:

```swift
let project = Project(resourceSynthesizers: [.strings(plugin: "MyPlugin")])
```

### Wtyczka zadania <Badge type="warning" text="deprecated" /> {#task-plugin-badge-typewarning-textdeprecated-}

::: warning DEPRECATED
<!-- -->
Wtyczki zadań zostały wycofane. Jeśli szukasz rozwiązania do automatyzacji dla
swojego projektu, zapoznaj się z [tym wpisem na
blogu](https://tuist.dev/blog/2025/04/15/automation-in-swift-projects).
<!-- -->
:::

Zadania to pliki wykonywalne udostępnione w `$PATH`, które można wywołać za
pomocą polecenia `tuist`, jeśli są zgodne z konwencją nazewniczą `tuist-`. We
wcześniejszych wersjach Tuist udostępniał pewne słabe konwencje i narzędzia w
ramach `tuist plugin` do `tworzenia`, `uruchamiania`, `testowania` oraz
`archiwizowania` zadań reprezentowanych przez pliki wykonywalne w pakietach
Swift, ale wycofaliśmy tę funkcję, ponieważ zwiększała ona obciążenie związane z
utrzymaniem i złożoność narzędzia.

Jeśli korzystałeś z Tuist do przydzielania zadań, zalecamy utworzenie
- Możesz nadal korzystać z biblioteki `ProjectAutomation.xcframework` dołączanej
  do każdej wersji Tuist, aby uzyskać dostęp do grafu projektu z poziomu logiki
  za pomocą `let graph = try Tuist.graph()`. Polecenie to wykorzystuje proces
  systemowy do uruchomienia polecenia `tuist` i zwraca reprezentację grafu
  projektu w pamięci.
- Aby rozdzielić zadania, zalecamy dołączenie pliku binarnego typu „fat binary”,
  który obsługuje `arm64` oraz `x86_64` w wydaniach GitHub, a także użycie
  [Mise](https://mise.jdx.dev) jako narzędzia instalacyjnego. Aby poinstruować
  Mise, jak zainstalować Twoje narzędzie, potrzebujesz repozytorium wtyczek.
  Możesz skorzystać z [Tuist's](https://github.com/asdf-community/asdf-tuist)
  jako punktu odniesienia.
- Jeśli nazwiesz swoje narzędzie `tuist-{xxx}`, a użytkownicy będą mogli je
  zainstalować, uruchamiając `mise install`, będą mogli je uruchomić albo
  bezpośrednio, albo poprzez `tuist xxx`.

::: info THE FUTURE OF PROJECTAUTOMATION
<!-- -->
Planujemy połączyć modele `ProjectAutomation` oraz `XcodeGraph` w jedną,
kompatybilną wstecznie strukturę, która udostępnia użytkownikowi całość grafu
projektu. Ponadto wyodrębnimy logikę generowania do nowej warstwy, `XcodeGraph`,
z której można również korzystać z własnego CLI. Potraktuj to jako tworzenie
własnego Tuist.
<!-- -->
:::

## Korzystanie z wtyczek {#using-plugins}

Aby użyć wtyczki, musisz dodać ją do pliku manifestu projektu
<LocalizedLink href="/references/project-description/structs/tuist">`Tuist.swift`</LocalizedLink>:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .local(path: "/Plugins/MyPlugin")
    ])
)
```

Jeśli chcesz ponownie wykorzystać wtyczkę w projektach znajdujących się w
różnych repozytoriach, możesz przesłać ją do repozytorium Git i odwołać się do
niej w pliku `Tuist.swift`:

```swift
import ProjectDescription


let tuist = Tuist(
    project: .tuist(plugins: [
        .git(url: "https://url/to/plugin.git", tag: "1.0.0"),
        .git(url: "https://url/to/plugin.git", sha: "e34c5ba")
    ])
)
```

Po dodaniu wtyczek polecenie ` `` oraz `tuist install` ` pobierze wtyczki do
globalnego katalogu pamięci podręcznej.

::: info NO VERSION RESOLUTION
<!-- -->
Jak zapewne zauważyłeś, nie zapewniamy rozróżniania wersji dla wtyczek. Zalecamy
używanie tagów Git lub identyfikatorów SHA, aby zapewnić odtwarzalność.
<!-- -->
:::

::: tip PROJECT DESCRIPTION HELPERS PLUGINS
<!-- -->
W przypadku korzystania z wtyczki pomocniczej do opisów projektów nazwa modułu
zawierającego pomocniki jest nazwą wtyczki
```swift
import ProjectDescription
import MyTuistPlugin
let project = Project.app(name: "MyCoolApp", platform: .iOS)
```
<!-- -->
:::
