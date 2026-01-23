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
- Projekt
  <LocalizedLink href="/guides/features/projects">wygenerowany</LocalizedLink>
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

Pamięć podręczna modułów Tuist zapewnia skuteczny sposób optymalizacji czasu
kompilacji poprzez buforowanie modułów jako plików binarnych (`.xcframework`s) i
udostępnianie ich w różnych środowiskach. Funkcja ta pozwala wykorzystać
wcześniej wygenerowane pliki binarne, zmniejszając potrzebę wielokrotnej
kompilacji i przyspieszając proces tworzenia oprogramowania.

## Ostrzeżenie {#warming}

Tuist efektywnie
<LocalizedLink href="/guides/features/projects/hashing">wykorzystuje znaki
hash</LocalizedLink> dla każdego celu w grafie zależności w celu wykrywania
zmian. Wykorzystując te dane, tworzy i przypisuje unikalne identyfikatory do
plików binarnych pochodzących z tych celów. W momencie generowania grafu Tuist
płynnie zastępuje oryginalne cele ich odpowiednimi wersjami binarnymi.

Operacja ta, znana jako „rozgrzewanie” ( *),* tworzy pliki binarne do użytku
lokalnego lub do udostępniania współpracownikom i środowiskom CI za
pośrednictwem Tuist. Proces rozgrzewania pamięci podręcznej jest prosty i można
go zainicjować za pomocą prostego polecenia:


```bash
tuist cache
```

Polecenie ponownie wykorzystuje pliki binarne, aby przyspieszyć proces.

## Użycie {#usage}

Domyślnie, gdy polecenia Tuist wymagają generowania projektu, automatycznie
zastępują zależności ich binarnymi odpowiednikami z pamięci podręcznej, jeśli są
one dostępne. Dodatkowo, jeśli określisz listę celów, na których chcesz się
skupić, Tuist zastąpi również wszystkie zależne cele ich buforowanymi plikami
binarnymi, o ile są one dostępne. Dla tych, którzy preferują inne podejście,
istnieje opcja całkowitego wyłączenia tego zachowania za pomocą specjalnego
flagi:

::: code-group
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: warning
<!-- -->
Buforowanie binarne to funkcja przeznaczona do pracy programistycznej, takiej
jak uruchamianie aplikacji na symulatorze lub urządzeniu albo przeprowadzanie
testów. Nie jest ona przeznaczona do kompilacji wydawniczych. Podczas
archiwizacji aplikacji należy wygenerować projekt ze źródłami, używając
polecenia `--cache-profile none`.
<!-- -->
:::

## Profile pamięci podręcznej {#cache-profiles}

Tuist obsługuje profile pamięci podręcznej, które pozwalają kontrolować, jak
intensywnie cele są zastępowane plikami binarnymi z pamięci podręcznej podczas
generowania projektów.

- Wbudowane:
  - `only-external`: zastępuj tylko zależności zewnętrzne (ustawienie domyślne
    systemu)
  - `all-possible`: zastąp jak najwięcej celów (w tym cele wewnętrzne)
  - `brak`: nigdy nie zastępuj plików binarnych z pamięci podręcznej

Wybierz profil za pomocą polecenia ` `--cache-profile` ` na stronie `tuist
generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

::: info DEPRECATED FLAG
<!-- -->
Flaga ` `--no-binary-cache` ` jest przestarzała. Zamiast niej należy używać `
`--cache-profile none` `. Przestarzała flaga nadal działa ze względu na
kompatybilność wsteczną.
<!-- -->
:::

Priorytet przy ustalaniu rzeczywistego zachowania (od najwyższego do
najniższego):

1. `--cache-profile none`
2. Skupienie na celu (przekazywanie celów do `generuje`) → profil `wszystkie
   możliwe`
3. `--cache-profile `
4. Ustawienia domyślne (jeśli zostały skonfigurowane)
5. Domyślne ustawienie systemu (`only-external`)

## Obsługiwane produkty {#supported-products}

Tuist może buforować tylko następujące produkty docelowe:

- Frameworki (statyczne i dynamiczne), które nie są zależne od
  [XCTest](https://developer.apple.com/documentation/xctest)
- Pakiety
- Makra Swift

Pracujemy nad obsługą bibliotek i celów zależnych od XCTest.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Gdy cel nie nadaje się do buforowania, powoduje to, że cele upstream również nie
nadają się do buforowania. Na przykład, jeśli masz wykres zależności `A &gt; B`,
gdzie A zależy od B, jeśli B nie nadaje się do buforowania, A również nie będzie
nadawać się do buforowania.
<!-- -->
:::

## Wydajność {#efficiency}

Poziom wydajności, jaki można osiągnąć dzięki buforowaniu binarnemu, zależy w
dużym stopniu od struktury grafu. Aby uzyskać najlepsze wyniki, zalecamy
następujące działania:

1. Unikaj bardzo zagnieżdżonych wykresów zależności. Im płytszy wykres, tym
   lepiej.
2. Zdefiniuj zależności za pomocą celów protokołu/interfejsu zamiast celów
   implementacji i wstrzykuj implementacje zależności z najwyższych celów.
3. Podziel często modyfikowane cele na mniejsze, których prawdopodobieństwo
   zmiany jest mniejsze.

Powyższe sugestie są częścią
<LocalizedLink href="/guides/features/projects/tma-architecture">Architektury
modułowej</LocalizedLink>, którą proponujemy jako sposób strukturyzowania
projektów w celu maksymalnego wykorzystania zalet nie tylko buforowania
binarnego, ale także możliwości Xcode.

## Zalecana konfiguracja {#recommended-setup}

Zalecamy uruchomienie zadania CI, które **uruchamia się przy każdym
zatwierdzeniu w głównej gałęzi** w celu rozgrzania pamięci podręcznej. Dzięki
temu pamięć podręczna będzie zawsze zawierała pliki binarne dla zmian w `main`,
a lokalna i gałąź CI będą się stopniowo budować na ich podstawie.

::: tip CACHE WARMING USES BINARIES
<!-- -->
Polecenie `tuist cache` również wykorzystuje pamięć podręczną plików binarnych w
celu przyspieszenia rozgrzewania.
<!-- -->
:::

Poniżej przedstawiono kilka przykładów typowych procesów roboczych:

### Programista rozpoczyna pracę nad nową funkcją. {#a-developer-starts-to-work-on-a-new-feature}

1. Tworzą nową gałąź z `main`.
2. Uruchamiają `tuist generate`.
3. Tuist pobiera najnowsze pliki binarne z `main` i generuje projekt przy ich
   użyciu.

### Programista przesyła zmiany do upstreamu. {#a-developer-pushes-changes-upstream}

1. Aby zbudować lub przetestować projekt, uruchom CI pipeline: `xcodebuild
   build` lub `tuist test`.
2. Proces pracy pobierze najnowsze pliki binarne z `main` i wygeneruje projekt
   przy ich użyciu.
3. Następnie projekt zostanie zbudowany lub przetestowany stopniowo.

## Konfiguracja {#configuration}

### Limit współbieżności pamięci podręcznej {#cache-concurrency-limit}

Domyślnie Tuist pobiera i wysyła artefakty pamięci podręcznej bez żadnych
ograniczeń dotyczących współbieżności, maksymalizując przepustowość. Możesz
kontrolować to zachowanie za pomocą zmiennej środowiskowej
`TUIST_CACHE_CONCURRENCY_LIMIT`:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

Może to być przydatne w środowiskach o ograniczonej przepustowości sieci lub w
celu zmniejszenia obciążenia systemu podczas operacji buforowania.

## Rozwiązywanie problemów {#troubleshooting}

### Nie używa plików binarnych dla moich celów. {#it-doesnt-use-binaries-for-my-targets}

Upewnij się, że znaki
<LocalizedLink href="/guides/features/projects/hashing#debugging">hashes są
deterministyczne</LocalizedLink> w różnych środowiskach i uruchomieniach. Może
się to zdarzyć, jeśli projekt zawiera odniesienia do środowiska, na przykład
poprzez ścieżki bezwzględne. Możesz użyć polecenia `diff`, aby porównać projekty
wygenerowane przez dwa kolejne wywołania `tuist generate` lub w różnych
środowiskach lub uruchomieniach.

Upewnij się również, że cel nie zależy bezpośrednio ani pośrednio od
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">celu
niepodlegającego buforowaniu</LocalizedLink>.

### Brakujące symbole {#missing-symbols}

Podczas korzystania ze źródeł system kompilacji Xcode, poprzez Derived Data,
może rozwiązywać zależności, które nie są jawnie zadeklarowane. Jednak w
przypadku korzystania z pamięci podręcznej plików binarnych zależności muszą być
jawnie zadeklarowane, w przeciwnym razie mogą wystąpić błędy kompilacji
spowodowane brakiem symboli. Aby to zdebugować, zalecamy użycie polecenia
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink> i skonfigurowanie go w CI,
aby zapobiec regresji w łączeniu niejawnym.

### Pamięć podręczna modułów starszego typu {#legacy-module-cache}

W Tuist `4.128.0` wprowadziliśmy nową infrastrukturę dla pamięci podręcznej
modułów jako domyślną. Jeśli napotkasz problemy z tą nową wersją, możesz
przywrócić poprzednie zachowanie pamięci podręcznej, ustawiając zmienną
środowiskową `TUIST_LEGACY_MODULE_CACHE`.

Ta pamięć podręczna modułu legacy jest tymczasowym rozwiązaniem awaryjnym i
zostanie usunięta po stronie serwera w przyszłej aktualizacji. Należy zaplanować
migrację z tego rozwiązania.

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
