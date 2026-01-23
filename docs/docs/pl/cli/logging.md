---
{
  "title": "Logging",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Learn how to enable and configure logging in Tuist."
}
---
# Rejestrowanie {#logging}

CLI rejestruje komunikaty wewnętrznie, aby pomóc w diagnozowaniu problemów.

## Diagnozuj problemy za pomocą logów {#diagnose-issues-using-logs}

Jeśli wywołanie polecenia nie przynosi zamierzonych rezultatów, możesz
zdiagnozować problem, sprawdzając logi. CLI przekazuje logi do
[OSLog](https://developer.apple.com/documentation/os/oslog) i systemu plików.

Przy każdym uruchomieniu tworzy plik dziennika w lokalizacji
`$XDG_STATE_HOME/tuist/logs/{uuid}.log`, gdzie `$XDG_STATE_HOME` przyjmuje
wartość `~/.local/state`, jeśli zmienna środowiskowa nie jest ustawiona. Można
również użyć `$TUIST_XDG_STATE_HOME`, aby ustawić katalog stanu specyficzny dla
Tuist, który ma pierwszeństwo przed `$XDG_STATE_HOME`.

::: napiwek
<!-- -->
Dowiedz się więcej o organizacji katalogów Tuist i konfiguracji katalogów
niestandardowych w <LocalizedLink href="/cli/directories">dokumentacji
katalogów</LocalizedLink>.
<!-- -->
:::

Domyślnie CLI wyświetla ścieżkę do logów, gdy wykonanie kończy się
nieoczekiwanie. Jeśli tak się nie stanie, logi można znaleźć w ścieżce podanej
powyżej (tj. w najnowszym pliku logu).

::: warning
<!-- -->
Informacje poufne nie są redagowane, dlatego należy zachować ostrożność podczas
udostępniania logów.
<!-- -->
:::

### Ciągła integracja {#diagnose-issues-using-logs-ci}

W CI, gdzie środowiska są jednorazowego użytku, warto skonfigurować potok CI
tak, aby eksportował logi Tuist. Eksportowanie artefaktów jest powszechną
funkcją usług CI, a konfiguracja zależy od używanej usługi. Na przykład w GitHub
Actions można użyć akcji `actions/upload-artifact`, aby przesłać logi jako
artefakt:

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

W celu debugowania problemów związanych z pamięcią podręczną Tuist rejestruje
operacje demona pamięci podręcznej za pomocą `os_log` z podsystemem
`dev.tuist.cache`. Możesz przesyłać strumieniowo te logi w czasie rzeczywistym
za pomocą:

```bash
log stream --predicate 'subsystem == "dev.tuist.cache"' --debug
```

Logi te są również widoczne w aplikacji Console.app po przefiltrowaniu
podsystemu `dev.tuist.cache`. Zapewnia to szczegółowe informacje na temat
operacji pamięci podręcznej, które mogą pomóc w diagnozowaniu problemów
związanych z przesyłaniem, pobieraniem i komunikacją pamięci podręcznej.
