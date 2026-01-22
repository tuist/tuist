---
{
  "title": "Continuous integration",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in continuous integration."
}
---
# Ciągła integracja (CI) {#continuous-integration-ci}

Aby korzystać z rejestru w CI, należy upewnić się, że zalogowano się do
rejestru, uruchamiając `tuist registry login` w ramach przepływu pracy.

::: info ONLY XCODE INTEGRATION
<!-- -->
Utworzenie nowego, wstępnie odblokowanego pęku kluczy jest wymagane tylko w
przypadku korzystania z integracji pakietów Xcode.
<!-- -->
:::

Ponieważ poświadczenia rejestru są przechowywane w pęku kluczy, należy upewnić
się, że pęk kluczy jest dostępny w środowisku CI. Należy pamiętać, że niektórzy
dostawcy CI lub narzędzia do automatyzacji, takie jak
[Fastlane](https://fastlane.tools/), już tworzą tymczasowy pęk kluczy lub
zapewniają wbudowany sposób jego tworzenia. Można go jednak również utworzyć,
tworząc niestandardowy krok z następującym kodem:
```bash
TMP_DIRECTORY=$(mktemp -d)
KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
KEYCHAIN_PASSWORD=$(uuidgen)
security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
security default-keychain -s $KEYCHAIN_PATH
security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
```

`tuist registry login` następnie zapisze dane uwierzytelniające w domyślnym pęku
kluczy. Upewnij się, że domyślny pęk kluczy został utworzony i odblokowany
_przed uruchomieniem_ `tuist registry login`.

Dodatkowo należy upewnić się, że zmienna środowiskowa `TUIST_TOKEN` jest
ustawiona. Można ją utworzyć, postępując zgodnie z instrukcją
<LocalizedLink href="/guides/server/authentication#as-a-project">tutaj</LocalizedLink>.

Przykładowy przebieg pracy dla GitHub Actions mógłby wyglądać następująco:
```yaml
name: Build

jobs:
  build:
    steps:
      - # Your set up steps...
      - name: Create keychain
        run: |
        TMP_DIRECTORY=$(mktemp -d)
        KEYCHAIN_PATH=$TMP_DIRECTORY/keychain.keychain
        KEYCHAIN_PASSWORD=$(uuidgen)
        security create-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
        security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
        security default-keychain -s $KEYCHAIN_PATH
        security unlock-keychain -p $KEYCHAIN_PASSWORD $KEYCHAIN_PATH
      - name: Log in to the Tuist Registry
        env:
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
        run: tuist registry login
      - # Your build steps
```

### Stopniowe rozwiązywanie problemów w różnych środowiskach {#incremental-resolution-across-environments}

Rozwiązania typu „clean/cold” działają nieco szybciej dzięki naszemu rejestrowi,
a jeszcze większą poprawę można uzyskać, jeśli zachowasz rozwiązane zależności w
kompilacjach CI. Należy pamiętać, że dzięki rejestrowi rozmiar katalogu, który
należy przechowywać i przywracać, jest znacznie mniejszy niż bez rejestru, co
znacznie skraca czas. Aby buforować zależności podczas korzystania z domyślnej
integracji pakietów Xcode, najlepszym sposobem jest określenie niestandardowego
`clonedSourcePackagesDirPath` podczas rozwiązywania zależności za pomocą
`xcodebuild`. Można to zrobić, dodając następujący wpis do pliku `Config.swift`:

```swift
import ProjectDescription

let config = Config(
    generationOptions: .options(
        additionalPackageResolutionArguments: ["-clonedSourcePackagesDirPath", ".build"]
    )
)
```

Dodatkowo należy znaleźć ścieżkę do pliku `Package.resolved`. Ścieżkę można
uzyskać, uruchamiając `ls **/Package.resolved`. Ścieżka powinna wyglądać mniej
więcej tak:
`App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

W przypadku pakietów Swift i integracji opartej na XcodeProj możemy użyć
domyślnego katalogu `.build` znajdującego się w katalogu głównym projektu lub w
katalogu `Tuist`. Upewnij się, że ścieżka jest poprawna podczas konfigurowania
potoku.

Oto przykładowy przebieg pracy GitHub Actions w celu rozwiązywania i buforowania
zależności przy użyciu domyślnej integracji pakietu Xcode:
```yaml
- name: Restore cache
  id: cache-restore
  uses: actions/cache/restore@v4
  with:
    path: .build
    key: ${{ runner.os }}-${{ hashFiles('App.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
- name: Resolve dependencies
  if: steps.cache-restore.outputs.cache-hit != 'true'
  run: xcodebuild -resolvePackageDependencies -clonedSourcePackagesDirPath .build
- name: Save cache
  id: cache-save
  uses: actions/cache/save@v4
  with:
    path: .build
    key: ${{ steps.cache-restore.outputs.cache-primary-key }}
```
