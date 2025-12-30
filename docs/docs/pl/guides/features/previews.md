---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Zapowiedzi {#previews}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

Podczas tworzenia aplikacji możesz chcieć udostępnić ją innym, aby uzyskać
opinie. Tradycyjnie, zespoły robią to poprzez tworzenie, podpisywanie i
wysyłanie swoich aplikacji na platformy takie jak
[TestFlight](https://developer.apple.com/testflight/) firmy Apple. Proces ten
może być jednak uciążliwy i powolny, zwłaszcza gdy zależy nam jedynie na
szybkiej informacji zwrotnej od współpracownika lub znajomego.

Aby usprawnić ten proces, Tuist zapewnia sposób generowania i udostępniania
podglądów aplikacji każdemu.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
Podczas tworzenia aplikacji na urządzenie użytkownik jest obecnie odpowiedzialny
za prawidłowe podpisanie aplikacji. Planujemy usprawnić to w przyszłości.
<!-- -->
:::

::: code-group
```bash [Tuist Project]
tuist generate App
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -sdk iphonesimulator # Build the app for the simulator
xcodebuild build -scheme App -workspace App.xcworkspace -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App
```
```bash [Xcode Project]
xcodebuild -scheme App -project App.xcodeproj -configuration Debug # Build the app for the simulator
xcodebuild -scheme App -project App.xcodeproj -configuration Debug -destination 'generic/platform=iOS' # Build the app for the device
tuist share App --configuration Debug --platforms iOS
tuist share App.ipa # Share an existing .ipa file
```
<!-- -->
:::

Polecenie wygeneruje link, który można udostępnić każdemu, aby uruchomić
aplikację - na symulatorze lub rzeczywistym urządzeniu. Wszystko, co będą
musieli zrobić, to uruchomić poniższe polecenie:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Podczas udostępniania pliku `.ipa` można pobrać aplikację bezpośrednio z
urządzenia mobilnego za pomocą łącza Podgląd. Łącza do podglądów `.ipa` są
domyślnie _publiczne_. W przyszłości będzie można ustawić je jako prywatne, tak
aby odbiorca linku musiał uwierzytelnić się za pomocą swojego konta Tuist, aby
pobrać aplikację.

`tuist run` umożliwia również uruchomienie najnowszego podglądu na podstawie
specyfikatora, takiego jak `latest`, nazwy gałęzi lub określonego skrótu
zatwierdzenia:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Upewnij się, że `CFBundleVersion` (wersja kompilacji) jest unikalna,
wykorzystując numer przebiegu CI, który ujawnia większość dostawców CI. Na
przykład w GitHub Actions można ustawić `CFBundleVersion` na zmienną
<code v-pre>${{ github.run_number }}</code>.

Przesłanie podglądu z tą samą wersją binarną (kompilacją) i tą samą
`CFBundleVersion` nie powiedzie się.
<!-- -->
:::

## Utwory {#tracks}

Ścieżki pozwalają organizować podglądy w nazwane grupy. Na przykład, możesz mieć
ścieżkę `beta` dla wewnętrznych testerów i ścieżkę `nightly` dla automatycznych
kompilacji. Ścieżki są tworzone leniwie - wystarczy określić nazwę ścieżki
podczas udostępniania, a zostanie ona utworzona automatycznie, jeśli nie
istnieje.

Aby udostępnić podgląd określonej ścieżki, należy użyć opcji `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Jest to przydatne dla:
- **Organizowanie podglądów**: Grupowanie podglądów według przeznaczenia (np.
  `beta`, `nightly`, `internal`)
- **Aktualizacje w aplikacji**: Tuist SDK używa ścieżek do określenia, o których
  aktualizacjach powiadamiać użytkowników.
- **Filtrowanie**: Łatwe wyszukiwanie i zarządzanie podglądami według utworów na
  pulpicie nawigacyjnym Tuist.

::: warning PREVIEWS' VISIBILITY
<!-- -->
Tylko osoby z dostępem do organizacji, do której należy projekt, mogą uzyskać
dostęp do podglądu. Planujemy dodać obsługę wygasających linków.
<!-- -->
:::

## Aplikacja Tuist macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Aby jeszcze bardziej ułatwić uruchamianie Tuist Previews, opracowaliśmy
aplikację Tuist na pasek menu macOS. Zamiast uruchamiać Previews za pomocą Tuist
CLI, można [pobrać](https://tuist.dev/download) aplikację na macOS. Aplikację
można również zainstalować, uruchamiając `brew install --cask
tuist/tuist/tuist`.

Po kliknięciu przycisku "Uruchom" na stronie podglądu, aplikacja macOS
automatycznie uruchomi się na aktualnie wybranym urządzeniu.

::: ostrzeżenie WYMAGANIA
<!-- -->
Musisz mieć zainstalowany lokalnie Xcode i korzystać z systemu macOS 14 lub
nowszego.
<!-- -->
:::

## Aplikacja Tuist iOS {#tuist-ios-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/images/guides/features/ios-icon.png" style="height: 100px;" />
    <h1 style="padding-top: 2px;">Tuist</h1>
    <img src="/images/guides/features/tuist-app.png" style="width: 300px; padding-top: 8px;" />
    <a href="https://apps.apple.com/us/app/tuist/id6748460335" target="_blank" style="padding-top: 10px;">
        <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" style="height: 40px;">
    </a>
</div>

Podobnie jak aplikacja na macOS, aplikacje Tuist na iOS usprawniają dostęp do
podglądów i ich uruchamianie.

## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Aby uzyskać automatyczne komentarze do pull/merge requestów, zintegruj swój
<LocalizedLink href="/guides/server/accounts-and-projects"> zdalny projekt</LocalizedLink> z platformą
<LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.
<!-- -->
:::

Testowanie nowych funkcji powinno być częścią każdego przeglądu kodu. Jednak
konieczność tworzenia aplikacji lokalnie zwiększa niepotrzebne tarcia, często
prowadząc do tego, że programiści w ogóle pomijają testowanie funkcjonalności na
swoich urządzeniach. Ale *co by było, gdyby każde żądanie ściągnięcia zawierało
link do kompilacji, która automatycznie uruchamiałaby aplikację na urządzeniu
wybranym w aplikacji Tuist macOS?*

Po połączeniu projektu Tuist z platformą Git, taką jak
[GitHub](https://github.com), dodaj <LocalizedLink href="/cli/share">`tuist share MyApp`</LocalizedLink> do przepływu pracy CI. Następnie Tuist opublikuje
link do podglądu bezpośrednio w żądaniach ściągnięcia: ![Komentarz do aplikacji
GitHub z linkiem do podglądu
Tuist](/images/guides/features/github-app-with-preview.png)


## Powiadomienia o aktualizacjach w aplikacji {#in-app-update-notifications}

Zestaw [Tuist SDK](https://github.com/tuist/sdk) umożliwia aplikacji wykrywanie,
kiedy dostępna jest nowsza wersja podglądu i powiadamianie o tym użytkowników.
Jest to przydatne do utrzymywania testerów w najnowszej wersji.

Zestaw SDK sprawdza aktualizacje w ramach tej samej **ścieżki podglądu**. Po
udostępnieniu podglądu z wyraźną ścieżką za pomocą `--track`, SDK będzie szukać
aktualizacji na tej ścieżce. Jeśli nie określono ścieżki, gałąź git jest używana
jako ścieżka - więc podgląd zbudowany z gałęzi `main` powiadomi tylko o nowszych
podglądach również zbudowanych z `main`.

### Instalacja {#sdk-installation}

Dodaj Tuist SDK jako zależność pakietu Swift:

```swift
.package(url: "https://github.com/tuist/sdk", .upToNextMajor(from: "0.1.0"))
```

### Monitorowanie aktualizacji {#sdk-monitor-updates}

Użyj `monitorPreviewUpdates`, aby okresowo sprawdzać dostępność nowych wersji
podglądu:

```swift
import TuistSDK

struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    TuistSDK(
                        fullHandle: "myorg/myapp",
                        apiKey: "your-api-key"
                    )
                    .monitorPreviewUpdates()
                }
        }
    }
}
```

### Kontrola pojedynczej aktualizacji {#sdk-single-check}

Do ręcznego sprawdzania aktualizacji:

```swift
let sdk = TuistSDK(
    fullHandle: "myorg/myapp",
    apiKey: "your-api-key"
)

if let preview = try await sdk.checkForUpdate() {
    print("New version available: \(preview.version ?? "unknown")")
}
```

### Zatrzymywanie monitorowania aktualizacji {#sdk-stop-monitoring}

`monitorPreviewUpdates` zwraca zadanie `` , które można anulować:

```swift
let task = sdk.monitorPreviewUpdates { preview in
    // Handle update
}

// Later, to stop monitoring:
task.cancel()
```

:: info
<!-- -->
Sprawdzanie aktualizacji jest automatycznie wyłączane w symulatorach i
kompilacjach App Store.
<!-- -->
:::

## Identyfikator README {#readme-badge}

Aby zwiększyć widoczność podglądów Tuist w repozytorium, można dodać plakietkę
do pliku `README`, która wskazuje na najnowszy podgląd Tuist:

[![Tuist
Preview](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Aby dodać plakietkę do swojego pliku `README`, użyj poniższego znacznika i
zastąp uchwyty konta i projektu własnymi:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Jeśli projekt zawiera wiele aplikacji z różnymi identyfikatorami pakietów, można
określić, do którego podglądu aplikacji ma prowadzić łącze, dodając parametr
zapytania `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatyzacja {#automations}

Można użyć flagi `--json`, aby uzyskać dane wyjściowe JSON z polecenia `tuist
share`:
```
tuist share --json
```

Dane wyjściowe JSON są przydatne do tworzenia niestandardowych automatyzacji,
takich jak publikowanie wiadomości Slack przy użyciu dostawcy CI. JSON zawiera
klucz `url` z pełnym linkiem do podglądu oraz klucz `qrCodeURL` z adresem URL do
obrazu kodu QR, aby ułatwić pobieranie podglądów z rzeczywistego urządzenia.
Przykład danych wyjściowych JSON znajduje się poniżej:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
