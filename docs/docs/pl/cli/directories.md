---
{
  "title": "Directories",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how Tuist organizes its configuration, cache, and state directories."
}
---
# Katalogi {#directories}

Tuist organizuje swoje pliki w kilku katalogach w systemie, zgodnie ze
specyfikacją [XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).
Zapewnia to czysty, standardowy sposób zarządzania konfiguracją, pamięcią
podręczną i plikami stanu.

## Obsługiwane zmienne środowiskowe {#supported-environment-variables}

Tuist obsługuje zarówno standardowe zmienne XDG, jak i prefiksowane warianty
specyficzne dla Tuist. Warianty specyficzne dla Tuist (z prefiksem `TUIST_`)
mają pierwszeństwo, umożliwiając konfigurację Tuist niezależnie od innych
aplikacji.

### Katalog konfiguracji {#configuration-directory}

**Zmienne środowiskowe:**
- `TUIST_XDG_CONFIG_HOME` (ma pierwszeństwo)
- `XDG_CONFIG_HOME`

**Domyślnie:** `~/.config/tuist`

**Używany do:**
- Poświadczenia serwera (`credentials/{host}.json`)

**Przykład:**
```bash
# Set Tuist-specific config directory
export TUIST_XDG_CONFIG_HOME=/custom/config
tuist auth login

# Or use standard XDG variable
export XDG_CONFIG_HOME=/custom/config
tuist auth login
```

### Katalog pamięci podręcznej {#cache-directory}

**Zmienne środowiskowe:**
- `TUIST_XDG_CACHE_HOME` (ma pierwszeństwo)
- `XDG_CACHE_HOME`

**Domyślnie:** `~/.cache/tuist`

**Używany do:**
- **Wtyczki**: Pobrana i skompilowana pamięć podręczna wtyczek
- **ProjectDescriptionHelpers**: Skompilowane narzędzia pomocnicze opisu
  projektu
- **Manifesty**: Pliki manifestu w pamięci podręcznej
- **Projekty**: Wygenerowana pamięć podręczna projektu automatyzacji
- **EditProjects**: Pamięć podręczna dla polecenia edycji
- **Uruchomienia**: Testowanie i tworzenie danych analitycznych uruchomień
- **Pliki binarne**: Pliki binarne artefaktów kompilacji (nieudostępniane w
  różnych środowiskach)
- **SelectiveTests**: Pamięć podręczna testów selektywnych

**Przykład:**
```bash
# Set Tuist-specific cache directory
export TUIST_XDG_CACHE_HOME=/tmp/tuist-cache
tuist cache

# Or use standard XDG variable
export XDG_CACHE_HOME=/tmp/cache
tuist cache
```

### Katalog państw {#state-directory}

**Zmienne środowiskowe:**
- `TUIST_XDG_STATE_HOME` (ma pierwszeństwo)
- `XDG_STATE_HOME`

**Domyślnie:** `~/.local/state/tuist`

**Używany do:**
- **Dzienniki**: Pliki dziennika (`logs/{uuid}.log`)
- **Blokady**: Pliki blokady uwierzytelniania (`{handle}.sock`)

**Przykład:**
```bash
# Set Tuist-specific state directory
export TUIST_XDG_STATE_HOME=/var/log/tuist
tuist generate

# Or use standard XDG variable
export XDG_STATE_HOME=/var/log
tuist generate
```

## Kolejność pierwszeństwa {#precedence-order}

Podczas określania, który katalog ma zostać użyty, Tuist sprawdza zmienne
środowiskowe w następującej kolejności:

1. **Zmienna specyficzna dla Tuist** (np. `TUIST_XDG_CONFIG_HOME`).
2. **Standardowa zmienna XDG** (np. `XDG_CONFIG_HOME`)
3. **Domyślna lokalizacja** (np. `~/.config/tuist`)

Pozwala to na:
- Użyj standardowych zmiennych XDG, aby spójnie zorganizować wszystkie aplikacje
- Zastąp zmiennymi specyficznymi dla Tuist, gdy potrzebujesz różnych lokalizacji
  dla Tuist
- Poleganie na rozsądnych ustawieniach domyślnych bez żadnej konfiguracji

## Typowe przypadki użycia {#common-use-cases}

### Izolowanie Tuist dla każdego projektu {#isolating-tuist-per-project}

Warto odizolować pamięć podręczną i stan Tuist dla każdego projektu:

```bash
# In your project's .envrc (using direnv)
export TUIST_XDG_CACHE_HOME="$PWD/.tuist/cache"
export TUIST_XDG_STATE_HOME="$PWD/.tuist/state"
export TUIST_XDG_CONFIG_HOME="$PWD/.tuist/config"
```

### Środowiska CI/CD {#ci-cd-environments}

W środowiskach CI warto korzystać z katalogów tymczasowych:

```yaml
# GitHub Actions example
env:
  TUIST_XDG_CACHE_HOME: /tmp/tuist-cache
  TUIST_XDG_STATE_HOME: /tmp/tuist-state

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: tuist generate
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist-state/logs/*.log
```

### Debugowanie z izolowanymi katalogami {#debugging-with-isolated-directories}

Podczas debugowania błędów warto mieć czyste konto:

```bash
# Create temporary directories for debugging
export TUIST_XDG_CACHE_HOME=$(mktemp -d)
export TUIST_XDG_STATE_HOME=$(mktemp -d)
export TUIST_XDG_CONFIG_HOME=$(mktemp -d)

# Run Tuist commands
tuist generate

# Clean up when done
rm -rf $TUIST_XDG_CACHE_HOME $TUIST_XDG_STATE_HOME $TUIST_XDG_CONFIG_HOME
```
