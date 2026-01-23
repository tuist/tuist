---
{
  "title": "CLI",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist CLI."
}
---
# CLI {#cli}

Źródło:
[github.com/tuist/tuist/tree/main/Tuist](https://github.com/tuist/tuist/tree/main/Tuist)
i
[github.com/tuist/tuist/tree/main/cli](https://github.com/tuist/tuist/tree/main/cli)

## Do czego służy {#what-it-is-for}

CLI jest sercem Tuist. Obsługuje generowanie projektów, automatyzację przepływu
pracy (testowanie, uruchamianie, tworzenie wykresów i sprawdzanie) oraz zapewnia
interfejs do serwera Tuist dla funkcji takich jak uwierzytelnianie, pamięć
podręczna, statystyki, podgląd, rejestr i testowanie selektywne.

## Jak wnieść swój wkład {#how-to-contribute}

### Wymagania {#requirements}

- macOS 14.0+
- Xcode 26+

### Skonfiguruj lokalnie {#set-up-locally}

- Sklonuj repozytorium: `git clone git@github.com:tuist/tuist.git`
- Zainstaluj Mise za pomocą [oficjalnego skryptu
  instalacyjnego](https://mise.jdx.dev/getting-started.html) (nie Homebrew) i
  uruchom `mise install`
- Zainstaluj zależności Tuist: `tuist install`
- Utwórz obszar roboczy: `tuist generate`

Wygenerowany projekt otwiera się automatycznie. Jeśli chcesz go ponownie
otworzyć później, uruchom `open Tuist.xcworkspace`.

::: info XED .
<!-- -->
Jeśli spróbujesz otworzyć projekt za pomocą polecenia „ `xed.` ”, otworzy się
pakiet, a nie obszar roboczy wygenerowany przez Tuist. Użyj polecenia „
`Tuist.xcworkspace` ”.
<!-- -->
:::

### Uruchom Tuist {#run-tuist}

#### Z Xcode {#from-xcode}

Edytuj plik `tuist` scheme i ustaw argumenty, takie jak `generate --no-open`.
Ustaw katalog roboczy na katalog główny projektu (lub użyj `--path`).

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
CLI zależy od `ProjectDescription`. Jeśli nie działa, najpierw zbuduj
`Tuist-Workspace`.
<!-- -->
:::

#### Z terminala {#from-the-terminal}

Najpierw utwórz obszar roboczy:

```bash
tuist generate --no-open
```

Następnie skompiluj plik wykonywalny `tuist` za pomocą Xcode i uruchom go z
DerivedData:

```bash
tuist_build_dir="$(xcodebuild -workspace Tuist.xcworkspace -scheme tuist -configuration Debug -destination 'platform=macOS' -showBuildSettings | awk -F' = ' '/BUILT_PRODUCTS_DIR/{print $2; exit}')"

"$tuist_build_dir/tuist" generate --path /path/to/project --no-open
```

Lub za pośrednictwem menedżera pakietów Swift:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
