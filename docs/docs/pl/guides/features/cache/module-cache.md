---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# Pamięć podręczna modułów {#module-cache}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Projekt wygenerowany przez
  <LocalizedLink href="/guides/features/projects"></LocalizedLink>
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

Tuist Module cache zapewnia potężny sposób na optymalizację czasu kompilacji
poprzez buforowanie modułów jako plików binarnych (`.xcframework`s) i
udostępnianie ich w różnych środowiskach. Pozwala to na wykorzystanie wcześniej
wygenerowanych plików binarnych, zmniejszając potrzebę wielokrotnej kompilacji i
przyspieszając proces rozwoju.

## Ocieplenie {#warming}

Tuist efektywnie <LocalizedLink href="/guides/features/projects/hashing"> wykorzystuje skróty </LocalizedLink> dla każdego celu w grafie zależności w celu
wykrycia zmian. Wykorzystując te dane, tworzy i przypisuje unikalne
identyfikatory do plików binarnych pochodzących z tych celów. W czasie
generowania grafu Tuist płynnie zastępuje oryginalne cele ich odpowiednimi
wersjami binarnymi.

Ta operacja, znana jako "rozgrzewanie" *,* tworzy pliki binarne do użytku
lokalnego lub do udostępniania członkom zespołu i środowiskom CI za
pośrednictwem Tuist. Proces rozgrzewania pamięci podręcznej jest prosty i można
go zainicjować za pomocą prostego polecenia:


```bash
tuist cache
```

Polecenie ponownie wykorzystuje pliki binarne, aby przyspieszyć proces.

## Użycie {#usage}

Domyślnie, gdy polecenia Tuist wymagają wygenerowania projektu, automatycznie
zastępują zależności ich binarnymi odpowiednikami z pamięci podręcznej, jeśli są
one dostępne. Dodatkowo, jeśli określisz listę celów, na których chcesz się
skupić, Tuist zastąpi również wszelkie zależne cele ich buforowanymi plikami
binarnymi, pod warunkiem, że są one dostępne. Dla tych, którzy preferują inne
podejście, istnieje opcja całkowitej rezygnacji z tego zachowania poprzez użycie
określonej flagi:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
Buforowanie binarne to funkcja przeznaczona dla przepływów pracy deweloperskiej,
takich jak uruchamianie aplikacji na symulatorze lub urządzeniu lub uruchamianie
testów. Nie jest przeznaczona do kompilacji wersji. Podczas archiwizacji
aplikacji należy wygenerować projekt ze źródłami przy użyciu flagi
`--no-binary-cache`.
<!-- -->
:::

## Profile pamięci podręcznej {#cache-profiles}

Tuist obsługuje profile pamięci podręcznej, aby kontrolować, jak agresywnie cele
są zastępowane buforowanymi plikami binarnymi podczas generowania projektów.

- Wbudowane elementy:
  - `only-external`: zastępuje tylko zewnętrzne zależności (domyślne ustawienie
    systemowe).
  - `all-possible`: zastąp jak najwięcej celów (w tym cele wewnętrzne).
  - `brak`: nigdy nie zastępuje buforowanych plików binarnych

Wybierz profil za pomocą `--cache-profile` na `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

Pierwszeństwo podczas rozwiązywania skutecznego zachowania (od najwyższego do
najniższego):

1. `--no-binary-cache` → profil `none`
2. Skupienie na celu (przekazywanie celów do `generuje`) → profil
   `wszystko-możliwe`
3. `--cache-profile `
4. Konfiguracja domyślna (jeśli ustawiona)
5. Domyślne ustawienia systemowe (`only-external`)

## Obsługiwane produkty {#supported-products}

Tylko następujące produkty docelowe mogą być buforowane przez Tuist:

- Frameworki (statyczne i dynamiczne), które nie zależą od
  [XCTest](https://developer.apple.com/documentation/xctest).
- Pakiety
- Makra Swift

Pracujemy nad obsługą bibliotek i celów, które zależą od XCTest.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Gdy cel nie jest buforowalny, powoduje to, że cele nadrzędne również nie są
buforowalne. Na przykład, jeśli mamy graf zależności `A &gt; B`, gdzie A zależy
od B, jeśli B jest niebuforowalne, A również będzie niebuforowalne.
<!-- -->
:::

## Wydajność {#efficiency}

Poziom wydajności, który można osiągnąć za pomocą buforowania binarnego, zależy
w dużej mierze od struktury grafu. Aby osiągnąć najlepsze wyniki, zalecamy
następujące rozwiązania:

1. Unikaj bardzo zagnieżdżonych grafów zależności. Im płytszy graf, tym lepiej.
2. Zdefiniuj zależności z celami protokołów/interfejsów zamiast celów
   implementacji oraz implementacje wstrzykiwania zależności z najwyższych
   celów.
3. Podziel często modyfikowane cele na mniejsze, których prawdopodobieństwo
   zmiany jest niższe.

Powyższe sugestie są częścią
<LocalizedLink href="/guides/features/projects/tma-architecture"> Architektury Modułowej</LocalizedLink>, którą proponujemy jako sposób na ustrukturyzowanie
projektów w celu zmaksymalizowania korzyści nie tylko z buforowania binarnego,
ale także z możliwości Xcode.

## Zalecana konfiguracja {#recommended-setup}

Zalecamy posiadanie zadania CI, które **uruchamia się przy każdym zatwierdzeniu
w głównej gałęzi**, aby ogrzać pamięć podręczną. Zapewni to, że pamięć podręczna
zawsze będzie zawierać pliki binarne dla zmian w `głównej`, dzięki czemu gałąź
lokalna i CI będą budować na nich przyrostowo.

::: tip CACHE WARMING USES BINARIES
<!-- -->
Polecenie `tuist cache` również korzysta z binarnej pamięci podręcznej, aby
przyspieszyć nagrzewanie.
<!-- -->
:::

Poniżej przedstawiono kilka przykładów typowych przepływów pracy:

### Deweloper rozpoczyna pracę nad nową funkcją {#a-developer-starts-to-work-on-a-new-feature}

1. Tworzą nową gałąź z `głównego`.
2. Uruchamiają `tuist generują`.
3. Tuist pobiera najnowsze pliki binarne z `main` i generuje z nich projekt.

### Deweloper przesyła zmiany w górę strumienia {#a-developer-pushes-changes-upstream}

1. Potok CI uruchomi `xcodebuild build` lub `tuist test` w celu zbudowania lub
   przetestowania projektu.
2. Przepływ pracy pobierze najnowsze pliki binarne z `main` i wygeneruje z nich
   projekt.
3. Następnie będzie budować lub testować projekt przyrostowo.

## Konfiguracja {#configuration}

### Limit współbieżności pamięci podręcznej {#cache-concurrency-limit}

Domyślnie Tuist pobiera i wysyła artefakty z pamięci podręcznej bez limitu
współbieżności, maksymalizując przepustowość. Zachowanie to można kontrolować za
pomocą zmiennej środowiskowej `TUIST_CACHE_CONCURRENCY_LIMIT`:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

Może to być przydatne w środowiskach o ograniczonej przepustowości sieci lub w
celu zmniejszenia obciążenia systemu podczas operacji pamięci podręcznej.

## Rozwiązywanie problemów {#troubleshooting}

### Nie używa binariów dla moich celów {#it-doesnt-use-binaries-for-my-targets}

Upewnij się, że skróty
<LocalizedLink href="/guides/features/projects/hashing#debugging"> są deterministyczne</LocalizedLink> w różnych środowiskach i uruchomieniach. Może
się tak zdarzyć, jeśli projekt zawiera odniesienia do środowiska, na przykład
poprzez ścieżki bezwzględne. Można użyć polecenia `diff`, aby porównać projekty
wygenerowane przez dwa kolejne wywołania `tuist generate` lub między
środowiskami lub uruchomieniami.

Upewnij się również, że cel nie zależy bezpośrednio lub pośrednio od celu
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">non-cacheable</LocalizedLink>.

### Brakujące symbole {#missing-symbols}

Podczas korzystania ze źródeł, system kompilacji Xcode, poprzez Derived Data,
może rozwiązywać zależności, które nie zostały jawnie zadeklarowane. Jeśli
jednak polegasz na binarnej pamięci podręcznej, zależności muszą być jawnie
zadeklarowane; w przeciwnym razie prawdopodobnie zobaczysz błędy kompilacji, gdy
nie można znaleźć symboli. Aby to debugować, zalecamy użycie polecenia
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> i skonfigurowanie go w CI, aby
zapobiec regresjom w niejawnym łączeniu.
