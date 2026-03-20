---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Use selective testing to run only the tests that have changed since the last successful test run."
}
---
# Testy selektywne {#selective-testing}

Wraz z rozwojem projektu rośnie liczba testów. Przez długi czas uruchomienie
wszystkich testów przy każdym PR lub push do `main` zajmuje kilkadziesiąt
sekund. Jednak to rozwiązanie nie skaluje się do tysięcy testów, które może mieć
Twój zespół.

Podczas każdego przebiegu testów w CI najprawdopodobniej ponownie uruchamiasz
wszystkie testy, niezależnie od wprowadzonych zmian. Selektywne testowanie w
Tuist pomaga znacznie przyspieszyć sam proces testowania, uruchamiając tylko te
testy, które uległy zmianie od ostatniego pomyślnego przebiegu testów, w oparciu
o nasz <LocalizedLink href="/guides/features/projects/hashing">algorytm
haszujący</LocalizedLink>.

Aby uruchomić testy selektywnie z
<LocalizedLink href="/guides/features/projects">wygenerowanym
projektem</LocalizedLink>, użyj polecenia `tuist test`. Polecenie to
<LocalizedLink href="/guides/features/projects/hashing">generuje
skróty</LocalizedLink> projektu Xcode w taki sam sposób, jak w przypadku
<LocalizedLink href="/guides/features/cache/module-cache">pamięci podręcznej
modułów</LocalizedLink>, a w przypadku powodzenia zapisuje skróty, aby określić,
co uległo zmianie w przyszłych uruchomieniach. W kolejnych uruchomieniach
polecenie `tuist test` w sposób przejrzysty wykorzystuje skróty do filtrowania
testów i uruchamia tylko te, które uległy zmianie od ostatniego pomyślnego
uruchomienia testów.

`Test tuist` integruje się bezpośrednio z
<LocalizedLink href="/guides/features/cache/module-cache">pamięcią podręczną
modułów</LocalizedLink>, aby wykorzystać jak najwięcej plików binarnych z
lokalnej lub zdalnej pamięci w celu skrócenia czasu kompilacji podczas
uruchamiania zestawu testów. Połączenie selektywnego testowania z pamięcią
podręczną modułów może znacznie skrócić czas wykonywania testów w środowisku CI.

::: warning MODULE VS FILE-LEVEL GRANULARITY
<!-- -->
Ze względu na niemożność wykrycia zależności w kodzie między testami a źródłami,
maksymalna szczegółowość testowania selektywnego znajduje się na poziomie
docelowym. Dlatego zalecamy, aby cele były niewielkie i konkretne, co pozwoli
zmaksymalizować korzyści płynące z testowania selektywnego.
<!-- -->
:::

::: warning TEST COVERAGE
<!-- -->
Narzędzia do pomiaru pokrycia testowego zakładają, że cały zestaw testów jest
uruchamiany jednocześnie, co sprawia, że nie są one kompatybilne z selektywnym
uruchamianiem testów — oznacza to, że dane dotyczące pokrycia mogą nie
odzwierciedlać rzeczywistości podczas korzystania z selekcji testów. Jest to
znane ograniczenie i nie oznacza, że robisz coś źle. Zachęcamy zespoły do
zastanowienia się, czy pokrycie nadal dostarcza wartościowych informacji w tym
kontekście, a jeśli tak, to zapewniamy, że już zastanawiamy się, jak sprawić, by
pokrycie działało poprawnie przy selektywnych uruchomieniach w przyszłości.
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
[GitHub](https://github.com), a użytkownik zacznie korzystać z polecenia `tuist
test` w ramach procesu CI, Tuist zamieści komentarz bezpośrednio w żądaniach
pull/merge, zawierający informacje o tym, które testy zostały uruchomione, a
które pominięte: ![Komentarz w aplikacji GitHub z linkiem do podglądu
Tuist](/images/guides/features/selective-testing/github-app-comment.png)
