---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Testowanie wybiórcze {#selective-testing}

Wraz z rozwojem projektu rośnie liczba testów. Przez długi czas uruchamianie
wszystkich testów dla każdego PR lub push do `main` zajmuje dziesiątki sekund.
Jednak rozwiązanie to nie jest skalowalne do tysięcy testów, które może mieć
Twój zespół.

Podczas każdego testu w CI najprawdopodobniej ponownie uruchamiasz wszystkie
testy, niezależnie od zmian. Selektywne testowanie Tuist pomaga znacznie
przyspieszyć samo uruchamianie testów, uruchamiając tylko te testy, które uległy
zmianie od ostatniego pomyślnego uruchomienia testu w oparciu o nasz algorytm
haszujący <LocalizedLink href="/guides/features/projects/hashing">.

Testowanie selektywne działa z `xcodebuild`, które obsługuje dowolny projekt
Xcode, lub jeśli generujesz swoje projekty za pomocą Tuist, możesz użyć
polecenia `tuist test`, które zapewnia dodatkowe udogodnienia, takie jak
integracja z <LocalizedLink href="/guides/features/cache">binary
cache</LocalizedLink>. Aby rozpocząć testowanie selektywne, postępuj zgodnie z
instrukcjami dostosowanymi do konfiguracji Twojego projektu:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Wygenerowany
  projekt</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Ze względu na niemożność wykrycia zależności między testami a źródłami w kodzie,
maksymalna szczegółowość testów selektywnych znajduje się na poziomie docelowym.
Dlatego zalecamy, aby cele były niewielkie i skoncentrowane, aby zmaksymalizować
korzyści płynące z testów selektywnych.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Narzędzia do testowania pokrycia zakładają, że cały zestaw testów jest
uruchamiany jednocześnie, co sprawia, że nie są one kompatybilne z selektywnym
uruchamianiem testów — oznacza to, że dane dotyczące pokrycia mogą nie
odzwierciedlać rzeczywistości w przypadku korzystania z selekcji testów. Jest to
znane ograniczenie i nie oznacza, że robisz coś źle. Zachęcamy zespoły do
zastanowienia się, czy pokrycie nadal dostarcza znaczących informacji w tym
kontekście, a jeśli tak, to zapewniamy, że już zastanawiamy się, jak sprawić, by
pokrycie działało poprawnie z selektywnymi uruchomieniami w przyszłości.
<!-- -->
:::


## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Aby uzyskać automatyczne komentarze do pull/merge request, zintegruj swój
<LocalizedLink href="/guides/server/accounts-and-projects">projekt
Tuist</LocalizedLink> z
<LocalizedLink href="/guides/server/authentication">platformą
Git</LocalizedLink>.
<!-- -->
:::

Po połączeniu projektu Tuist z platformą Git, taką jak
[GitHub](https://github.com), i rozpoczęciu korzystania z poleceń `tuist
xcodebuild test` lub `tuist test` w ramach przepływu pracy CI, Tuist opublikuje
komentarz bezpośrednio w żądaniach pull/merge, zawierający informacje o tym,
które testy zostały przeprowadzone, a które pominięte: ![Komentarz w aplikacji
GitHub z linkiem do podglądu
Tuist](/images/guides/features/selective-testing/github-app-comment.png)
