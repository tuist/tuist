---
{
  "title": "Previews",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to generate and share previews of your apps with anyone."
}
---
# Podgląd {#previews}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

Podczas tworzenia aplikacji możesz chcieć udostępnić ją innym, aby uzyskać
opinie. Zazwyczaj zespoły robią to, kompilując, podpisując i przesyłając swoje
aplikacje na platformy takie jak
[TestFlight](https://developer.apple.com/testflight/) firmy Apple. Proces ten
może jednak być uciążliwy i powolny, zwłaszcza gdy szukasz tylko szybkiej opinii
od kolegi lub znajomego.

Aby usprawnić ten proces, Tuist oferuje możliwość generowania i udostępniania
podglądów aplikacji dowolnym osobom.

::: warning DEVICE BUILDS NEED TO BE SIGNED
<!-- -->
Podczas kompilacji aplikacji na urządzenie użytkownik jest obecnie
odpowiedzialny za prawidłowe podpisanie aplikacji. Planujemy usprawnić ten
proces w przyszłości.
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

Polecenie wygeneruje link, który możesz udostępnić dowolnej osobie, aby
uruchomiła aplikację – na symulatorze lub rzeczywistym urządzeniu. Wystarczy, że
uruchomi poniższe polecenie:

```bash
tuist run {url}
tuist run --device "My iPhone" {url} # Run the app on a specific device
```

Udostępniając plik `.ipa`, możesz pobrać aplikację bezpośrednio z urządzenia
mobilnego, korzystając z linku podglądu. Linki do podglądów `.ipa` są domyślnie
_prywatne_, co oznacza, że odbiorca musi uwierzytelnić się za pomocą swojego
konta Tuist, aby pobrać aplikację. Jeśli chcesz udostępnić aplikację dowolnej
osobie, możesz zmienić to ustawienie na publiczne w ustawieniach projektu.

`Komenda `tuist run` ` umożliwia również uruchomienie najnowszego podglądu na
podstawie specyfikatora, takiego jak ` `latest``, nazwa gałęzi lub konkretny
hash commitu:

```bash
tuist run App@latest # Runs latest App preview associated with the project's default branch
tuist run App@my-feature-branch # Runs latest App preview associated with a given branch
tuist run App@00dde7f56b1b8795a26b8085a781fb3715e834be # Runs latest App preview associated with a given git commit sha
```

::: warning UNIQUE BUILD NUMBERS IN CI
<!-- -->
Upewnij się, że `CFBundleVersion` (wersja kompilacji) jest unikalna,
wykorzystując numer przebiegu CI, który udostępnia większość dostawców CI. Na
przykład w GitHub Actions możesz ustawić `CFBundleVersion` na zmienną
<code v-pre>${{ github.run_number }}</code>.

Przesyłanie podglądu z tym samym plikiem binarnym (kompilacją) i tą samą wersją
CFBundleVersion `` zakończy się niepowodzeniem.
<!-- -->
:::

## Utwory {#tracks}

Ścieżki pozwalają organizować podglądy w nazwane grupy. Na przykład możesz mieć
ścieżkę `beta` dla wewnętrznych testerów oraz ścieżkę `nightly` dla
automatycznych kompilacji. Ścieżki są tworzone w trybie leniwym — wystarczy
podać nazwę ścieżki podczas udostępniania, a zostanie ona utworzona
automatycznie, jeśli jeszcze nie istnieje.

Aby udostępnić podgląd konkretnego utworu, użyj opcji `--track`:

```bash
tuist share App --track beta
tuist share App --track nightly
```

Jest to przydatne w przypadku:
- **Porządkowanie podglądów**: Grupuj podglądy według przeznaczenia (np. `beta`,
  `nightly`, `internal`)
- **Aktualizacje w aplikacji**: Tuist SDK wykorzystuje ścieżki do określenia, o
  których aktualizacjach należy powiadomić użytkowników
- **Filtrowanie**: Łatwe wyszukiwanie i zarządzanie podglądami według ścieżek w
  panelu Tuist

::: warning PREVIEWS' VISIBILITY
<!-- -->
Dostęp do podglądów mają wyłącznie osoby z uprawnieniami w organizacji, do
której należy projekt. Planujemy dodać obsługę linków z wygasającym terminem
ważności.
<!-- -->
:::

## Aplikacja Tuist na macOS {#tuist-macos-app}

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <h1>Tuist</h1>
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Aby jeszcze bardziej ułatwić uruchamianie podglądów Tuist, stworzyliśmy
aplikację Tuist dla paska menu systemu macOS. Zamiast uruchamiać podglądy za
pomocą wiersza poleceń Tuist, możesz [pobrać](https://tuist.dev/download)
aplikację dla systemu macOS. Aplikację można również zainstalować, uruchamiając
polecenie `brew install --cask tuist/tuist/tuist`.

Po kliknięciu przycisku „Uruchom” na stronie podglądu aplikacja macOS
automatycznie uruchomi go na aktualnie wybranym urządzeniu.

::: ostrzeżenie WYMAGANIA
<!-- -->
Musisz mieć lokalnie zainstalowany program Xcode i korzystać z systemu macOS 14
lub nowszego.
<!-- -->
:::

## Aplikacja Tuist na iOS {#tuist-ios-app}

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
Aby uzyskać automatyczne komentarze do pull requestów/merge requestów, zintegruj
swój <LocalizedLink href="/guides/server/accounts-and-projects">projekt
zdalny</LocalizedLink> z
<LocalizedLink href="/guides/server/authentication">platformą
Git</LocalizedLink>.
<!-- -->
:::

Testowanie nowych funkcji powinno być częścią każdego przeglądu kodu. Jednak
konieczność kompilowania aplikacji lokalnie powoduje niepotrzebne utrudnienia,
co często prowadzi do tego, że programiści całkowicie pomijają testowanie
funkcji na swoich urządzeniach. Ale *co by było, gdyby każde zgłoszenie pull
request zawierało link do kompilacji, która automatycznie uruchamiałaby
aplikację na urządzeniu wybranym w aplikacji Tuist na macOS?*

Gdy projekt Tuist zostanie połączony z platformą Git, taką jak
[GitHub](https://github.com), dodaj <LocalizedLink href="/cli/share">`tuist
share MyApp`</LocalizedLink> do swojego przepływu pracy CI. Tuist opublikuje
wtedy link podglądu bezpośrednio w twoich pull requestach: ![Komentarz w
aplikacji GitHub z linkiem podglądu
Tuist](/images/guides/features/github-app-with-preview.png)


## Powiadomienia o aktualizacjach w aplikacji {#in-app-update-notifications}

[Tuist SDK](https://github.com/tuist/sdk) umożliwia Twojej aplikacji wykrywanie
dostępności nowszej wersji zapoznawczej i powiadamianie o tym użytkowników. Jest
to przydatne do zapewnienia testerom dostępu do najnowszej kompilacji.

SDK sprawdza dostępność aktualizacji w ramach tej samej ścieżki podglądu **** .
Gdy udostępniasz podgląd z wyraźnie określoną ścieżką za pomocą `--track`, SDK
będzie szukać aktualizacji na tej ścieżce. Jeśli nie określono żadnej ścieżki,
jako ścieżka wykorzystywana jest gałąź git — więc podgląd zbudowany z gałęzi
`main` będzie powiadamiał tylko o nowszych podglądach zbudowanych również z
gałęzi `main`.

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

W przypadku ręcznego sprawdzania aktualizacji:

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
Sprawdzanie aktualizacji jest automatycznie wyłączone na symulatorach i w
kompilacjach App Store.
<!-- -->
:::

## Plakietka README {#readme-badge}

Aby podglądy Tuist były bardziej widoczne w Twoim repozytorium, możesz dodać
znacznik do pliku README `` , który odsyła do najnowszego podglądu Tuist:

[![Podgląd
Tuist](https://tuist.dev/Dimillian/IcySky/previews/latest/badge.svg)](https://tuist.dev/Dimillian/IcySky/previews/latest)

Aby dodać odznakę do pliku README projektu `` , użyj poniższego kodu Markdown i
zastąp nazwy konta oraz projektu własnymi:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest)
```

Jeśli projekt zawiera wiele aplikacji o różnych identyfikatorach pakietów, można
określić, do podglądu której aplikacji ma prowadzić link, dodając parametr
zapytania `bundle-id`:
```
[![Tuist Preview](https://tuist.dev/{account-handle}/{project-handle}/previews/latest/badge.svg)](https://tuist.dev/{account-handle}/{project-handle}/previews/latest?bundle-id=com.example.app)
```

## Automatyzacja {#automations}

Możesz użyć flagi `--json`, aby uzyskać wynik w formacie JSON z polecenia `tuist
share`:
```
tuist share --json
```

Wynik w formacie JSON jest przydatny do tworzenia niestandardowych
automatyzacji, takich jak publikowanie wiadomości w Slacku za pomocą dostawcy
CI. Plik JSON zawiera klucz `url` z pełnym linkiem do podglądu oraz klucz
`qrCodeURL` z adresem URL obrazu kodu QR, aby ułatwić pobieranie podglądów z
prawdziwego urządzenia. Przykładowy wynik w formacie JSON znajduje się poniżej:
```json
{
  "id": 1234567890,
  "url": "https://cloud.tuist.io/preview/1234567890",
  "qrCodeURL": "https://cloud.tuist.io/preview/1234567890/qr-code.svg"
}
```
