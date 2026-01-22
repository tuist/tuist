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

To run tests selectively with your
<LocalizedLink href="/guides/features/projects">generated
project</LocalizedLink>, use the `tuist test` command. The command
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
your Xcode project the same way it does for the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink>, and on success, it persists the hashes to determine what
has changed in future runs. In future runs, `tuist test` transparently uses the
hashes to filter down the tests and run only the ones that have changed since
the last successful test run.

`tuist test` integrates directly with the
<LocalizedLink href="/guides/features/cache/module-cache">module
cache</LocalizedLink> to use as many binaries from your local or remote storage
to improve the build time when running your test suite. The combination of
selective testing with module caching can dramatically reduce the time it takes
to run tests on your CI.

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

Once your Tuist project is connected with your Git platform such as
[GitHub](https://github.com), and you start using `tuist test` as part of your
CI workflow, Tuist will post a comment directly in your pull/merge requests,
including which tests were run and which skipped: ![GitHub app comment with a
Tuist Preview
link](/images/guides/features/selective-testing/github-app-comment.png)
