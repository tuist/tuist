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

Aby uruchomić testy selektywnie z
<LocalizedLink href="/guides/features/projects">wygenerowanym
projektem</LocalizedLink>, użyj polecenia `tuist test`. Polecenie to
<LocalizedLink href="/guides/features/projects/hashing">haszuje</LocalizedLink>
projekt Xcode w taki sam sposób, jak
<LocalizedLink href="/guides/features/cache/module-cache">pamięć podręczną
modułu</LocalizedLink>, a po pomyślnym zakończeniu zachowuje skróty, aby
określić, co uległo zmianie w przyszłych uruchomieniach. W przyszłych
uruchomieniach `tuist test` w sposób przejrzysty wykorzystuje skróty do
filtrowania testów i uruchamiania tylko tych, które uległy zmianie od ostatniego
pomyślnego uruchomienia testów.

`tuist test` integruje się bezpośrednio z
<LocalizedLink href="/guides/features/cache/module-cache">modułową pamięcią
podręczną</LocalizedLink>, aby wykorzystać jak najwięcej plików binarnych z
lokalnej lub zdalnej pamięci masowej w celu skrócenia czasu kompilacji podczas
uruchamiania zestawu testów. Połączenie selektywnego testowania z buforowaniem
modułów może znacznie skrócić czas potrzebny do przeprowadzenia testów w ramach
ciągłej integracji.

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

Gdy projekt Tuist zostanie połączony z platformą Git, taką jak
[GitHub](https://github.com), i zaczniesz używać `tuist test` w ramach przepływu
pracy CI, Tuist opublikuje komentarz bezpośrednio w żądaniach pull/merge,
zawierający informacje o tym, które testy zostały przeprowadzone, a które
pominięte: ![Komentarz w aplikacji GitHub z linkiem do podglądu
Tuist](/images/guides/features/selective-testing/github-app-comment.png)
