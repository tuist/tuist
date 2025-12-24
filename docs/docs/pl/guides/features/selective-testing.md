---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Testowanie selektywne {#selective-testing}

Wraz z rozwojem projektu rośnie liczba testów. Przez długi czas uruchamianie
wszystkich testów przy każdym PR lub push na `main` zajmowało dziesiątki sekund.
Ale to rozwiązanie nie skaluje się do tysięcy testów, które może mieć Twój
zespół.

Przy każdym uruchomieniu testów w CI najprawdopodobniej ponownie uruchamiasz
wszystkie testy, niezależnie od zmian. Selektywne testowanie Tuist pomaga
drastycznie przyspieszyć uruchamianie samych testów, uruchamiając tylko te
testy, które zmieniły się od ostatniego udanego uruchomienia testowego w oparciu
o nasz algorytm
<LocalizedLink href="/guides/features/projects/hashing">hashing</LocalizedLink>.

Testowanie selektywne działa z `xcodebuild`, który obsługuje dowolny projekt
Xcode, lub jeśli generujesz swoje projekty za pomocą Tuist, możesz zamiast tego
użyć polecenia `tuist test`, które zapewnia dodatkowe udogodnienia, takie jak
integracja z <LocalizedLink href="/guides/features/cache">binary cache</LocalizedLink>. Aby rozpocząć testowanie selektywne, postępuj zgodnie z
instrukcjami opartymi na konfiguracji projektu:

- <LocalizedLink href="/guides/features/selective-testing/xcode-project">xcodebuild</LocalizedLink>
- <LocalizedLink href="/guides/features/selective-testing/generated-project">Wygenerowany projekt</LocalizedLink>

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Ze względu na brak możliwości wykrycia wewnątrzkodowych zależności między
testami i źródłami, maksymalna ziarnistość testowania selektywnego znajduje się
na poziomie celu. Dlatego zalecamy, aby cele były małe i skoncentrowane, aby
zmaksymalizować korzyści płynące z testowania selektywnego.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Narzędzia pokrycia testów zakładają, że cały zestaw testów jest uruchamiany
jednocześnie, co czyni je niekompatybilnymi z selektywnym uruchamianiem testów -
oznacza to, że dane pokrycia mogą nie odzwierciedlać rzeczywistości podczas
korzystania z selekcji testów. Jest to znane ograniczenie i nie oznacza, że
robisz coś źle. Zachęcamy zespoły do zastanowienia się nad tym, czy pokrycie
nadal przynosi znaczące informacje w tym kontekście, a jeśli tak, to zapewniamy,
że już myślimy o tym, jak sprawić, by pokrycie działało poprawnie z selektywnymi
przebiegami w przyszłości.
<!-- -->
:::


## Komentarze do żądań ściągnięcia/łączenia {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Aby uzyskać automatyczne komentarze do pull/merge requestów, zintegruj projekt
<LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
z platformą
<LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.
<!-- -->
:::

Po połączeniu projektu Tuist z platformą Git, taką jak
[GitHub](https://github.com), i rozpoczęciu korzystania z `tuist xcodebuild
test` lub `tuist test` jako części przepływu CI, Tuist opublikuje komentarz
bezpośrednio w żądaniach ściągnięcia/łączenia, w tym informacje o tym, które
testy zostały uruchomione, a które pominięte: ![Komentarz aplikacji GitHub z
linkiem do podglądu
Tuist](/images/guides/features/selective-testing/github-app-comment.png).
