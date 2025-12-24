---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Pamięć podręczna Xcode {#xcode-cache}

Tuist zapewnia obsługę pamięci podręcznej kompilacji Xcode, która umożliwia
zespołom udostępnianie artefaktów kompilacji poprzez wykorzystanie możliwości
buforowania systemu kompilacji.

## Konfiguracja {#setup}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
- Xcode 26.0 lub nowszy
<!-- -->
:::

Jeśli nie masz jeszcze konta i projektu Tuist, możesz je utworzyć, uruchamiając
aplikację:

```bash
tuist init
```

Gdy masz już plik `Tuist.swift` odwołujący się do twojego `fullHandle`, możesz
skonfigurować buforowanie dla swojego projektu, uruchamiając go:

```bash
tuist setup cache
```

To polecenie tworzy
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html),
aby uruchomić lokalną usługę pamięci podręcznej podczas uruchamiania, której
[system kompilacji](https://github.com/swiftlang/swift-build) Swift używa do
udostępniania artefaktów kompilacji. Polecenie to należy uruchomić raz zarówno w
środowisku lokalnym, jak i CI.

Aby skonfigurować pamięć podręczną na CI, upewnij się, że jesteś
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>.

### Konfiguracja ustawień kompilacji Xcode {#configure-xcode-build-settings}

Dodaj następujące ustawienia kompilacji do projektu Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Należy pamiętać, że `COMPILATION_CACHE_REMOTE_SERVICE_PATH` i
`COMPILATION_CACHE_ENABLE_PLUGIN` muszą zostać dodane jako **zdefiniowane przez
użytkownika ustawienia kompilacji**, ponieważ nie są one bezpośrednio dostępne w
interfejsie ustawień kompilacji Xcode:

::: info SOCKET PATH
<!-- -->
Ścieżka gniazda zostanie wyświetlona po uruchomieniu `tuist setup cache`. Jest
ona oparta na pełnej nazwie projektu z ukośnikami zastąpionymi podkreślnikami.
<!-- -->
:::

Ustawienia te można również określić podczas uruchamiania `xcodebuild`, dodając
następujące flagi, takie jak

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
Ręczne konfigurowanie ustawień nie jest konieczne, jeśli projekt został
wygenerowany przez Tuist.

W takim przypadku wystarczy dodać `enableCaching: true` do pliku `Tuist.swift`:
```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "your-org/your-project",
    project: .tuist(
        generationOptions: .options(
            enableCaching: true
        )
    )
)
```
<!-- -->
:::

### Ciągła integracja #{ciągła-integracja}

Aby włączyć buforowanie w środowisku CI, należy uruchomić to samo polecenie, co
w środowisku lokalnym: `tuist setup cache`.

Dodatkowo należy upewnić się, że ustawiona jest zmienna środowiskowa
`TUIST_TOKEN`. Można ją utworzyć, postępując zgodnie z dokumentacją
<LocalizedLink href="/guides/server/authentication#as-a-project"> tutaj</LocalizedLink>. Zmienna środowiskowa `TUIST_TOKEN` _ musi_ być obecna w
kroku kompilacji, ale zalecamy ustawienie jej dla całego przepływu pracy CI.

Przykładowy przepływ pracy dla GitHub Actions mógłby wyglądać następująco:
```yaml
name: Build

env:
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Set up Tuist Cache
        run: tuist setup cache
      - # Your build steps
```
