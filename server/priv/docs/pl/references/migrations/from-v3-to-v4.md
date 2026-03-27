---
{
  "title": "From v3 to v4",
  "titleTemplate": ":title · Migrations · References · Tuist",
  "description": "This page documents how to migrate the Tuist CLI from the version 3 to version 4."
}
---
# Z Tuist v3 do v4 {#from-tuist-v3-to-v4}

Wraz z wydaniem [Tuist 4](https://github.com/tuist/tuist/releases/tag/4.0.0),
skorzystaliśmy z okazji, aby wprowadzić kilka przełomowych zmian w projekcie,
które naszym zdaniem ułatwią jego użytkowanie i utrzymanie w dłuższej
perspektywie. Niniejszy dokument przedstawia zmiany, które należy wprowadzić w
projekcie w celu aktualizacji z Tuist 3 do Tuist 4.

### Porzucamy zarządzanie wersjami przez `tuistenv` {#dropped-version-management-through-tuistenv}

Przed wersją Tuist 4, skrypt instalacyjny instalował narzędzie `tuistenv`,
którego nazwa była zmieniana na `tuist` podczas instalacji. Narzędzie to
zajmowało się instalacją i zarządzaniem wersjami Tuist, zapewniając determinizm
w różnych środowiskach. Mając na celu zmniejszenie odpowiedzialności Tuist,
zdecydowaliśmy się porzucić `tuistenv` na rzecz [Mise](https://mise.jdx.dev/),
narzędzia, które wykonuje to samo zadanie, ale jest bardziej elastyczne i może
być używane dla różnych narzędzi. Jeśli korzystałeś z `tuistenv`, będziesz
musiał odinstalować bieżącą wersję Tuist, uruchamiając skrypt:
`https://uninstall.tuist.io`, a następnie zainstalować go ponownie przy użyciu
wybranej metody instalacji. Zdecydowanie zalecamy korzystanie z Mise, ponieważ
jest on w stanie instalować i zarządzać wersjami deterministycznie w różnych
środowiskach.

::: code-group

```bash [Uninstall tuistenv]
curl -Ls https://uninstall.tuist.io | bash
```
<!-- -->
:::

::: warning MISE W ŚRODOWISKACH CI I PROJEKTACH XCODE
<!-- -->
Jeśli zdecydujesz się skorzystać z determinizmu, który oferuje Mise, zalecamy
zapoznanie się z dokumentacją dotyczącą korzystania z Mise w [środowiskach
CI](https://mise.jdx.dev/continuous-integration.html) i [projektach
Xcode](https://mise.jdx.dev/ide-integration.html#xcode).
<!-- -->
:::

::: info WSPARCIE HOMEBREW
<!-- -->
Pamiętaj, że nadal możesz zainstalować Tuist za pomocą Homebrew, który jest
popularnym menedżerem narzędzi dla macOS. Instrukcje dotyczące instalacji Tuist
przy użyciu Homebrew można znaleźć w
<LocalizedLink href="/guides/quick-start/install-tuist#alternative-homebrew">przewodniku instalacji</LocalizedLink>.
<!-- -->
:::

### Porzuciliśmy konstruktory `init` z modeli `ProjectDescription` {#dropped-init-constructors-from-projectdescription-models}

W celu poprawy czytelności i ekspresyjności interfejsów API postanowiliśmy
pozbyć się konstruktorów `init` ze wszystkich modeli `ProjectDescription`. Każdy
model oferuje teraz statyczny konstruktor, którego można użyć do tworzenia
instancji modeli. Jeśli korzystałeś z konstruktorów `init`, będziesz musiał
zaktualizować swój projekt, aby zamiast tego używać konstruktorów statycznych.

::: tip NAZEWNICTWO
<!-- -->
Konwencja nazewnictwa, której przestrzegamy, polega na używaniu nazwy modelu
jako nazwy konstruktora statycznego. Na przykład, statyczny konstruktor dla
modelu `Target` to `Target.target`.
<!-- -->
:::

### Zmieniliśmy `--no-cache` na `--no-binary-cache` {#renamed-nocache-to-nobinarycache}

Ponieważ flaga `--no-cache` była niejednoznaczna, zdecydowaliśmy się zmienić jej
nazwę na `--no-binary-cache`, aby było jasne, że odnosi się ona do buforowania
binarnych produktów. Jeśli używałeś flagi `--no-cache`, będziesz musiał
zaktualizować swój projekt, aby zamiast tego użyć flagi `--no-binary-cache`.

### Zmieniliśmy `tuist fetch` na `tuist install` {#renamed-tuist-fetch-to-tuist-install}

Zmieniliśmy nazwę polecenia `tuist fetch` na `tuist install`, aby dostosować się
do ogólnej konwencji. Jeśli korzystałeś z polecenia `tuist fetch`, będziesz
musiał zaktualizować swój projekt, aby zamiast tego użyć polecenia `tuist
install`.

### [Przyjęcie `Package.swift` jako DSL dla zależności](https://github.com/tuist/tuist/pull/5862) {#adopt-packageswift-as-the-dsl-for-dependencieshttpsgithubcomtuisttuistpull5862}

Przed Tuist 4 zależności można było definiować w pliku `Dependencies.swift`. Ten
specyficzny dla Tuist format uniemożliwiał automatyczną aktualizację zależności
w narzędziach takich jak [Dependabot](https://github.com/dependabot) czy
[Renovatebot](https://github.com/renovatebot/renovate). Co więcej, wprowadzał
niepotrzebne komplikacje dla użytkowników. Dlatego zdecydowaliśmy się przyjąć
`Package.swift` jako jedyny sposób definiowania zależności w Tuist. Jeśli
korzystałeś z pliku `Dependencies.swift`, musisz przenieść zawartość z
`Tuist/Dependencies.swift` do `Package.swift` w katalogu głównym i użyć
dyrektywy `#if TUIST`, aby skonfigurować integrację. Więcej informacji na temat
integracji zależności Swift można znaleźć
<LocalizedLink href="/guides/features/projects/dependencies#swift-packages">tutaj</LocalizedLink>

### Zmieniliśmy `tuist cache warm` na `tuist cache` {#renamed-tuist-cache-warm-to-tuist-cache}

Dla zwięzłości zdecydowaliśmy się zmienić nazwę polecenia `tuist cache warm` na
`tuist cache`. Jeśli korzystałeś z polecenia `tuist cache warm`, będziesz musiał
zaktualizować swój projekt, aby zamiast tego używać polecenia `tuist cache`.


### Zmieniliśmy `tuist cache print-hashes` na `tuist cache --print-hashes` {#renamed-tuist-cache-printhashes-to-tuist-cache-printhashes}

Zdecydowaliśmy się zmienić nazwę polecenia `tuist cache print-hashes` na `tuist
cache --print-hashes`, aby było jasne, że jest to flaga polecenia `tuist cache`.
Jeśli używałeś polecenia `tuist cache print-hashes`, będziesz musiał
zaktualizować swój projekt, aby zamiast tego użyć flagi `tuist cache
--print-hashes`.

### Porzuciliśmy profile cache {#removed-caching-profiles}

Przed Tuist 4 profile cache można było definiować w pliku `Tuist/Config.swift`,
który zawierał konfigurację dla cache. Zdecydowaliśmy się usunąć tę funkcję,
ponieważ mogło to prowadzić do nieporozumień podczas korzystania z niej w
procesie generowania z profilem innym niż ten, który został użyty do
wygenerowania projektu. Co więcej, może to prowadzić do tego, że użytkownicy
używają profilu debug do budowania wersji release aplikacji, co może prowadzić
do nieoczekiwanych rezultatów. W jego miejsce wprowadziliśmy opcję
`--configuration`, której można użyć do określenia konfiguracji, której chcesz
użyć podczas generowania projektu. Jeśli korzystałeś z profili cache, będziesz
musiał zaktualizować swój projekt, aby zamiast tego użyć opcji
`--configuration`.

### Porzuciliśmy `--skip-cache` na korzyść argumentów {#removed-skipcache-in-favor-of-arguments}

Porzuciliśmy flagę `--skip-cache` z polecenia `generate` która kontrolowała
które produkty powinny zostać wygenerowane z pominięciem cache. Jeśli używałeś
flagi `--skip-cache`, będziesz musiał zaktualizować swój projekt, aby zamiast
tego użyć argumentów.

::: code-group

```bash [Before]
tuist generate --skip-cache Foo
```

```bash [After]
tuist generate Foo
```
<!-- -->
:::

### [Porzuciliśmy funkcję podpisywania aplikacji](https://github.com/tuist/tuist/pull/5716) {#dropped-signing-capabilitieshttpsgithubcomtuisttuistpull5716}

Podpisywanie aplikacji jest już obsługiwane przez narzędzia, takie jak
[Fastlane](https://fastlane.tools/) czy sam Xcode, które robią znacznie lepszą
robotę w tym zakresie. Uznaliśmy, że podpisywanie aplikacji jest w Tuist
naciąganą funkcjonalności i lepiej skupić się na podstawowych funkcjach
projektu. Jeśli korzystałeś z możliwości podpisywania poprzez Tuist, które
polegały na szyfrowaniu certyfikatów i profili w repozytorium i instalowaniu ich
we właściwych miejscach w czasie generowania, możesz chcieć powielić tę logikę
we własnych skryptach uruchamianych przed wygenerowaniem projektu. W
szczególności:
  - Skrypt, który odszyfrowuje certyfikaty i profile przy użyciu klucza
    przechowywanego w systemie plików lub w zmiennej środowiskowej i instaluje
    certyfikaty w pęku kluczy, a profile zapisuje w katalogu
    `~/Library/MobileDevice/Provisioning\ Profiles`.
  - Skrypt, który może pobrać istniejące profile i certyfikaty i je zaszyfrować.

::: tip WYMAGANIA DOTYCZĄCE PODPISYWANIA
<!-- -->
Podpisywanie aplikacji wymaga obecności odpowiednich certyfikatów w pęku kluczy
oraz profili w katalogu `~/Library/MobileDevice/Provisioning\ Profiles`. Możesz
użyć narzędzia wiersza poleceń `security`, aby zainstalować certyfikaty w pęku
kluczy i polecenia `cp`, aby skopiować profile do odpowiedniego katalogu.
<!-- -->
:::

### Porzuciliśmy wsparcie dla Carthage poprzez `Dependencies.swift` {#dropped-carthage-integration-via-dependenciesswift}

Przed Tuist 4, zależności Carthage można było zdefiniować w pliku
`Dependencies.swift`, które można było następnie pobrać uruchamiając `tuist
fetch`. Uznaliśmy, że jest to funkcjonalność nieadekwatna dla Tuist, szczególnie
biorąc pod uwagę przyszłość, w której Swift Package Manager ma zostać
preferowanym sposobem zarządzania zależnościami. Jeśli korzystałeś z zależności
Carthage, będziesz musiał użyć `Carthage` bezpośrednio, aby pobrać
prekompilowane frameworki i XCFrameworks do standardowego katalogu Carthage, a
następnie odwołać się do tych plików binarnych z tagów za pomocą
`TargetDependency.xcframework` i `TargetDependency.framework`.

::: info WCIĄŻ WSPIERAMY CARTHAGE
<!-- -->
Niektórzy użytkownicy odnieśli wrażenie, że zrezygnowaliśmy z obsługi Carthage.
Nie zrobiliśmy tego. Kontrakt między Tuist i Carthage dotyczy frameworków oraz
XCFarmework-ów przechowywanych w systemie. Jedyną rzeczą, która się zmieniła,
jest to, kto jest odpowiedzialny za pobieranie zależności. Wcześniej był to
Tuist poprzez Carthage, teraz jest to Carthage bezpośrednio.
<!-- -->
:::

### Porzuciliśmy interfejs `TargetDependency.packagePlugin` {#dropped-the-targetdependencypackageplugin-api}

Przed Tuist 4 można było zdefiniować zależność na paczkę Swift-ową za pomocą
`TargetDependency.packagePlugin`. Po wprowadzeniu przez Swift Package Manager
nowych typów paczek, zdecydowaliśmy się na zmiany w API pozwalające na większą
elastyczność i odporność na przyszłe zmiany. Jeśli korzystałeś z
`TargetDependency.packagePlugin`, musisz zamiast tego użyć
`TargetDependency.package` i przekazać rodzaj paczki który chcesz użyć jako
argument.

### [Porzuciliśmy niewspierane interfejsy](https://github.com/tuist/tuist/pull/5560) {#dropped-deprecated-apishttpsgithubcomtuisttuistpull5560}

Porzuciliśmy interfejsy, które zostały oznaczone jako przestarzałe w Tuist 3.
Jeśli korzystałeś z któregokolwiek z przestarzałych interfejsów, będziesz musiał
zaktualizować swój projekt, aby korzystać z nowych interfejsów w Tuist.
