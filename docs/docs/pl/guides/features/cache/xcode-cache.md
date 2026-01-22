---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Pamięć podręczna Xcode {#xcode-cache}

Tuist zapewnia obsługę pamięci podręcznej kompilacji Xcode, która umożliwia
zespołom współdzielenie artefaktów kompilacji poprzez wykorzystanie możliwości
buforowania systemu kompilacji.

## Konfiguracja {#setup}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
- Xcode 26.0 lub nowszy
<!-- -->
:::

Jeśli nie masz jeszcze konta Tuist i projektu, możesz je utworzyć, uruchamiając:

```bash
tuist init
```

Po utworzeniu pliku `Tuist.swift` odwołującego się do `fullHandle`, możesz
skonfigurować buforowanie dla swojego projektu, uruchamiając:

```bash
tuist setup cache
```

To polecenie tworzy
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
w celu uruchomienia lokalnej usługi pamięci podręcznej podczas startu, której
system kompilacji Swift [build system](https://github.com/swiftlang/swift-build)
używa do udostępniania artefaktów kompilacji. Polecenie to należy uruchomić
jednokrotnie zarówno w środowisku lokalnym, jak i CI.

Aby skonfigurować pamięć podręczną w CI, upewnij się, że jesteś
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>.

### Skonfiguruj ustawienia kompilacji Xcode {#configure-xcode-build-settings}

Dodaj następujące ustawienia kompilacji do projektu Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Należy pamiętać, że `COMPILATION_CACHE_REMOTE_SERVICE_PATH` oraz
`COMPILATION_CACHE_ENABLE_PLUGIN` muszą zostać dodane jako **ustawienia
kompilacji zdefiniowane przez użytkownika**, ponieważ nie są one bezpośrednio
widoczne w interfejsie użytkownika ustawień kompilacji Xcode:

::: info SOCKET PATH
<!-- -->
Ścieżka gniazda zostanie wyświetlona po uruchomieniu polecenia `tuist setup
cache`. Jest ona oparta na pełnym uchwycie projektu, w którym ukośniki zostały
zastąpione znakami podkreślenia.
<!-- -->
:::

Możesz również określić te ustawienia podczas uruchamiania `xcodebuild`, dodając
następujące flagi, takie jak:

```
xcodebuild build -project YourProject.xcodeproj -scheme YourScheme \
    COMPILATION_CACHE_ENABLE_CACHING=YES \
    COMPILATION_CACHE_REMOTE_SERVICE_PATH=$HOME/.local/state/tuist/your_org_your_project.sock \
    COMPILATION_CACHE_ENABLE_PLUGIN=YES \
    COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
```

::: info GENERATED PROJECTS
<!-- -->
Ręczne ustawianie parametrów nie jest konieczne, jeśli projekt został
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

### Ciągła integracja #{continuous-integration}

Aby włączyć buforowanie w środowisku CI, należy uruchomić to samo polecenie, co
w środowiskach lokalnych: `tuist setup cache`.

W celu uwierzytelnienia można użyć
<LocalizedLink href="/guides/server/authentication#oidc-tokens">uwierzytelnienia
OIDC</LocalizedLink> (zalecane dla obsługiwanych dostawców CI) lub
<LocalizedLink href="/guides/server/authentication#account-tokens">tokenu
konta</LocalizedLink> poprzez zmienną środowiskową `TUIST_TOKEN`.

Przykładowy przebieg pracy dla GitHub Actions z wykorzystaniem uwierzytelniania
OIDC:
```yaml
name: Build

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      - run: tuist auth login
      - run: tuist setup cache
      - # Your build steps
```

Więcej przykładów, w tym uwierzytelnianie oparte na tokenach i inne platformy
CI, takie jak Xcode Cloud, CircleCI, Bitrise i Codemagic, można znaleźć w
<LocalizedLink href="/guides/integrations/continuous-integration">przewodniku po
ciągłej integracji</LocalizedLink>.
