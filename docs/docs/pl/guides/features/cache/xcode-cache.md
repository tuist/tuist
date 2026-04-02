---
{
  "title": "Xcode cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Enable Xcode compilation cache for your existing Xcode projects to improve build times both locally and on the CI."
}
---
# Pamięć podręczna Xcode {#xcode-cache}

Tuist obsługuje pamięć podręczną kompilacji Xcode, co pozwala zespołom na
współdzielenie artefaktów kompilacji dzięki wykorzystaniu możliwości buforowania
systemu kompilacji.

## Konfiguracja {#setup}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
- Xcode 26.0 lub nowszy
<!-- -->
:::

Jeśli nie masz jeszcze konta i projektu w Tuist, możesz je utworzyć,
uruchamiając:

```bash
tuist init
```

Gdy już masz plik `Tuist.swift` odwołujący się do `fullHandle`, możesz
skonfigurować buforowanie dla swojego projektu, uruchamiając:

```bash
tuist setup cache
```

To polecenie tworzy plik
[LaunchAgent](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
w celu uruchomienia lokalnej usługi pamięci podręcznej podczas startu systemu, z
której korzysta [system kompilacji](https://github.com/swiftlang/swift-build)
Swift do udostępniania artefaktów kompilacji. Polecenie to należy uruchomić
jednokrotnie zarówno w środowisku lokalnym, jak i w środowisku CI.

Aby skonfigurować pamięć podręczną w CI, upewnij się, że jesteś
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autoryzowany</LocalizedLink>.

### Skonfiguruj ustawienia kompilacji w Xcode {#configure-xcode-build-settings}

Dodaj następujące ustawienia kompilacji do swojego projektu Xcode:

```
COMPILATION_CACHE_ENABLE_CACHING = YES
COMPILATION_CACHE_REMOTE_SERVICE_PATH = $HOME/.local/state/tuist/your_org_your_project.sock
COMPILATION_CACHE_ENABLE_PLUGIN = YES
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS = YES
```

Należy pamiętać, że `COMPILATION_CACHE_REMOTE_SERVICE_PATH` oraz
`COMPILATION_CACHE_ENABLE_PLUGIN` należy dodać jako **ustawienia kompilacji
zdefiniowane przez użytkownika**, ponieważ nie są one bezpośrednio widoczne w
interfejsie użytkownika ustawień kompilacji Xcode:

::: info SOCKET PATH
<!-- -->
Ścieżka gniazda zostanie wyświetlona po uruchomieniu polecenia ` `tuist setup
cache``. Jest ona oparta na pełnym identyfikatorze projektu, w którym ukośniki
zostały zastąpione znakami podkreślenia.
<!-- -->
:::

Możesz również określić te ustawienia podczas uruchamiania polecenia `
`xcodebuild` `, dodając następujące flagi, na przykład:

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

### Ciągła integracja #{continuous-integration}

Aby włączyć buforowanie w środowisku CI, należy uruchomić to samo polecenie, co
w środowiskach lokalnych: `tuist setup cache`.

Do uwierzytelniania można użyć
<LocalizedLink href="/guides/server/authentication#oidc-tokens">uwierzytelniania
OIDC</LocalizedLink> (zalecane dla obsługiwanych dostawców CI) lub
<LocalizedLink href="/guides/server/authentication#account-tokens">tokena
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

Więcej przykładów, w tym uwierzytelnianie oparte na tokenach oraz inne platformy
CI, takie jak Xcode Cloud, CircleCI, Bitrise i Codemagic, znajdziesz w
<LocalizedLink href="/guides/integrations/continuous-integration">przewodniku po
ciągłej integracji</LocalizedLink>.
