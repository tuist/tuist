---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Rejestrowanie {#logging}

CLI rejestruje komunikaty wewnętrznie, aby pomóc w diagnozowaniu problemów.

## Diagnozowanie problemów przy użyciu dzienników {#diagnose-issues-using-logs}

Jeśli wywołanie polecenia nie przynosi zamierzonych rezultatów, można
zdiagnozować problem, sprawdzając dzienniki. CLI przekazuje logi do
[OSLog](https://developer.apple.com/documentation/os/oslog) i systemu plików.

W każdym uruchomieniu tworzy plik dziennika pod adresem
`$XDG_STATE_HOME/tuist/logs/{uuid}.log` gdzie `$XDG_STATE_HOME` przyjmuje
wartość `~/.local/state` jeśli zmienna środowiskowa nie jest ustawiona. Można
również użyć `$TUIST_XDG_STATE_HOME` do ustawienia katalogu stanu specyficznego
dla Tuist, który ma pierwszeństwo przed `$XDG_STATE_HOME`.

::: napiwek
<!-- -->
Więcej informacji na temat organizacji katalogów Tuist i sposobu konfigurowania
niestandardowych katalogów można znaleźć w dokumentacji
<LocalizedLink href="/cli/directories">Directories</LocalizedLink>.
<!-- -->
:::

Domyślnie CLI wyświetla ścieżkę dziennika, gdy wykonanie kończy się
nieoczekiwanie. Jeśli tak się nie stanie, dzienniki można znaleźć w ścieżce
wspomnianej powyżej (tj. w najnowszym pliku dziennika).

::: warning
<!-- -->
Wrażliwe informacje nie są redagowane, więc należy zachować ostrożność podczas
udostępniania dzienników.
<!-- -->
:::

### Ciągła integracja {#diagnose-issues-using-logs-ci}

W CI, gdzie środowiska są jednorazowe, warto skonfigurować potok CI tak, aby
eksportował dzienniki Tuist. Eksportowanie artefaktów jest powszechną funkcją we
wszystkich usługach CI, a konfiguracja zależy od używanej usługi. Na przykład w
GitHub Actions można użyć akcji `actions/upload-artifact`, aby przesłać
dzienniki jako artefakt:

```yaml
name: Node CI

on: [push]

env:
  TUIST_XDG_STATE_HOME: /tmp

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
      # ... other steps
      - run: tuist generate
      # ... do something with the project
      - name: Export Tuist logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: tuist-logs
          path: /tmp/tuist/logs/*.log
```

### Debugowanie demona pamięci podręcznej {#cache-daemon-debugging}

W celu debugowania problemów związanych z pamięcią podręczną, Tuist rejestruje
operacje demona pamięci podręcznej za pomocą `os_log` z podsystemem
`dev.tuist.cache`. Dzienniki te można przesyłać strumieniowo w czasie
rzeczywistym za pomocą:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Dzienniki te są również widoczne w Console.app poprzez filtrowanie podsystemu
`dev.tuist.cache`. Zapewnia to szczegółowe informacje o operacjach pamięci
podręcznej, które mogą pomóc w diagnozowaniu problemów związanych z
przesyłaniem, pobieraniem i komunikacją z pamięcią podręczną.
