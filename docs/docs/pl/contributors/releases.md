---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Wydania

Tuist korzysta z systemu ciągłego wydawania, który automatycznie publikuje nowe
wersje za każdym razem, gdy znaczące zmiany zostaną scalone z główną gałęzią.
Takie podejście zapewnia, że ulepszenia szybko docierają do użytkowników bez
ręcznej interwencji opiekunów.

## Przegląd

Stale wydajemy trzy główne komponenty:
- **Tuist CLI** - Narzędzie wiersza poleceń
- **Serwer Tuist** - Usługi zaplecza
- **Tuist App** - Aplikacje macOS i iOS (aplikacja iOS jest stale wdrażana tylko
  w TestFlight, zobacz więcej [tutaj](#app-store-release).

Każdy komponent ma swój własny potok wydań, który działa automatycznie przy
każdym wypchnięciu do głównej gałęzi.

## Jak to działa

### 1. Konwencje zobowiązań

Używamy [Conventional Commits](https://www.conventionalcommits.org/) do
strukturyzowania naszych komunikatów commit. Pozwala to naszym narzędziom
zrozumieć naturę zmian, określić skoki wersji i wygenerować odpowiednie
dzienniki zmian.

Format: `typ(zakres): opis`

#### Rodzaje zobowiązań i ich wpływ

| Typ              | Opis                       | Wersja Impact                     | Przykłady                                                   |
| ---------------- | -------------------------- | --------------------------------- | ----------------------------------------------------------- |
| `wyczyn`         | Nowa funkcja lub możliwość | Drobna zmiana wersji (x.Y.z)      | `feat(cli): dodanie wsparcia dla Swift 6`                   |
| `poprawka`       | Poprawka błędu             | Uderzenie wersji poprawki (x.y.Z) | `fix(app): usunięcie awarii podczas otwierania projektów`   |
| `dokumenty`      | Zmiany w dokumentacji      | Brak wydania                      | `dokumenty: instrukcja instalacji aktualizacji`             |
| `styl`           | Zmiany w stylu kodu        | Brak wydania                      | `style: formatowanie kodu za pomocą swiftformat`            |
| `refaktoryzacja` | Refaktoryzacja kodu        | Brak wydania                      | `refactor(server): uproszczenie logiki autoryzacji`         |
| `perf`           | Ulepszenia wydajności      | Ulepszenie wersji łatki           | `perf(cli): optymalizacja rozdzielczości zależności`        |
| `test`           | Dodatki/zmiany testowe     | Brak wydania                      | `test: dodanie testów jednostkowych dla pamięci podręcznej` |
| `chore`          | Zadania konserwacyjne      | Brak wydania                      | `chore: aktualizacja zależności`                            |
| `ci`             | Zmiany CI/CD               | Brak wydania                      | `ci: dodanie przepływu pracy dla wydań`                     |

#### Przełomowe zmiany

Zmiany przełomowe powodują zwiększenie wersji (X.0.0) i powinny być wskazane w
treści zatwierdzenia:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Wykrywanie zmian

Każdy komponent używa [git cliff](https://git-cliff.org/) do:
- Analiza zatwierdzeń od ostatniego wydania
- Filtrowanie zatwierdzeń według zakresu (cli, aplikacja, serwer)
- Określenie, czy istnieją zmiany, które można zwolnić
- Automatyczne generowanie dzienników zmian

### 3. Rurociąg zwalniający

Po wykryciu zmian, które można zwolnić:

1. **Obliczanie wersji**: Potok określa następny numer wersji
2. **Generowanie dziennika zmian**: git cliff tworzy dziennik zmian z wiadomości
   o zatwierdzeniu
3. **Proces kompilacji**: Komponent jest budowany i testowany
4. **Tworzenie wydania**: Wydanie GitHub jest tworzone z artefaktami
5. **Dystrybucja**: Aktualizacje są przekazywane do menedżerów pakietów (np.
   Homebrew dla CLI).

### 4. Filtrowanie zakresu

Każdy komponent jest wydawany tylko wtedy, gdy wprowadzi odpowiednie zmiany:

- **CLI**: zatwierdzenia z zakresem `(cli)` lub bez zakresu
- **Aplikacja**: Zatwierdzenia z zakresem `(aplikacja)`
- **Serwer**: Zatwierdzenia z zakresem `(serwer)`

## Pisanie dobrych wiadomości commit

Ponieważ komunikaty o zatwierdzeniach mają bezpośredni wpływ na informacje o
wydaniu, ważne jest, aby pisać jasne, opisowe komunikaty:

### Do:
- Używaj czasu teraźniejszego: "dodaj funkcję", a nie "dodano funkcję".
- Bądź zwięzły, ale opisowy
- Uwzględnienie zakresu, gdy zmiany są specyficzne dla komponentów
- Zagadnienia referencyjne, jeśli mają zastosowanie: `fix(cli): rozwiązanie
  problemu z pamięcią podręczną kompilacji (#1234)`

### Nie rób tego:
- Używaj niejasnych komunikatów, takich jak "napraw błąd" lub "zaktualizuj kod".
- Łączenie wielu niepowiązanych zmian w jednym zatwierdzeniu
- Zapomnij dołączyć informacje o zmianach awaryjnych

### Przełomowe zmiany

W przypadku zmian przełomowych należy dołączyć `BREAKING CHANGE:` w treści
zatwierdzenia:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Przepływy pracy wydania

Przepływy pracy wydania są zdefiniowane w:
- `.github/workflows/cli-release.yml` - wydania CLI
- `.github/workflows/app-release.yml` - Wydania aplikacji
- `.github/workflows/server-release.yml` - Wydania serwera

Każdy przepływ pracy:
- Działa po naciśnięciu przycisku głównego
- Może być wyzwalany ręcznie
- Używa git cliff do wykrywania zmian
- Obsługuje cały proces wydania

## Monitorowanie wydań

Możesz monitorować wydania poprzez:
- [strona GitHub Releases](https://github.com/tuist/tuist/releases).
- Karta GitHub Actions dla przepływów pracy
- Pliki dziennika zmian w każdym katalogu komponentów

## Korzyści

Podejście ciągłego wydawania zapewnia:

- **Szybka dostawa**: Zmiany docierają do użytkowników natychmiast po scaleniu
- **Redukcja wąskich gardeł**: Brak oczekiwania na ręczne wydania
- **Przejrzysta komunikacja**: Zautomatyzowane dzienniki zmian z wiadomości
  commit
- **Spójny proces**: Ten sam przepływ wersji dla wszystkich komponentów
- **Zapewnienie jakości**: Wydawane są tylko przetestowane zmiany

## Rozwiązywanie problemów

Jeśli zwolnienie nie powiedzie się:

1. Sprawdź dzienniki GitHub Actions pod kątem nieudanego przepływu pracy
2. Upewnij się, że wiadomości commit są zgodne z konwencjonalnym formatem
3. Sprawdź, czy wszystkie testy zakończyły się pomyślnie
4. Sprawdź, czy komponent został pomyślnie skompilowany

Dla pilnych poprawek, które wymagają natychmiastowego wydania:
1. Upewnij się, że Twój commit ma jasny zakres
2. Po scaleniu monitoruj przepływ pracy wydania
3. W razie potrzeby uruchom zwolnienie ręczne

## Wydanie App Store

Podczas gdy CLI i Server są zgodne z opisanym powyżej procesem ciągłego
wydawania, aplikacja **iOS** jest wyjątkiem ze względu na proces weryfikacji App
Store firmy Apple:

- **Ręczne wersje**: Wersje aplikacji iOS wymagają ręcznego przesłania do App
  Store.
- **Opóźnienia w przeglądzie**: Każda wersja musi przejść przez proces
  weryfikacji Apple, który może potrwać od 1 do 7 dni.
- **Zmiany zbiorcze**: Wiele zmian jest zazwyczaj łączonych w każdym wydaniu
  iOS.
- **TestFlight**: Wersje beta mogą być dystrybuowane za pośrednictwem TestFlight
  przed wydaniem w App Store.
- **Informacje o wersji**: Musi być napisana specjalnie dla wytycznych App Store

Aplikacja na iOS nadal przestrzega tych samych konwencji zatwierdzania i używa
git cliff do generowania dziennika zmian, ale faktyczne wydanie dla użytkowników
odbywa się w rzadszym, ręcznym harmonogramie.
