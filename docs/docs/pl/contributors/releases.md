---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Wydania

Tuist korzysta z systemu ciągłych wydań, który automatycznie publikuje nowe
wersje za każdym razem, gdy znaczące zmiany są scalane z główną gałęzią. Takie
podejście gwarantuje, że ulepszenia szybko docierają do użytkowników bez
konieczności ręcznej interwencji ze strony administratorów.

## Przegląd

Nieustannie wydajemy trzy główne komponenty:
- **Tuist CLI** - Narzędzie wiersza poleceń
- **Serwer Tuist** - Usługi zaplecza
- **Aplikacja Tuist** - Aplikacje na systemy macOS i iOS (aplikacja na iOS jest
  stale wdrażana tylko w TestFlight, więcej informacji
  [tutaj](#app-store-release)

Każdy komponent ma własny proces wydawania, który uruchamia się automatycznie
przy każdym dodaniu zmian do głównej gałęzi.

## Jak to działa

### 1. Konwencje dotyczące zatwierdzania zmian

Używamy [Conventional Commits](https://www.conventionalcommits.org/) do
strukturyzowania naszych komunikatów dotyczących zatwierdzeń. Dzięki temu nasze
narzędzia mogą zrozumieć charakter zmian, określić zmiany wersji i wygenerować
odpowiednie dzienniki zmian.

Format: `typ(zakres): opis`

#### Rodzaje commitów i ich wpływ

| Wpisz        | Opis                       | Wpływ na wersję                 | Przykłady                                                          |
| ------------ | -------------------------- | ------------------------------- | ------------------------------------------------------------------ |
| `feat`       | Nowa funkcja lub możliwość | Niewielka zmiana wersji (x.Y.z) | `feat(cli): dodano obsługę Swift 6`                                |
| `popraw`     | Poprawka błędu             | Zmiana wersji poprawki (x.y.Z)  | `fix(app): rozwiązano problem awarii podczas otwierania projektów` |
| `docs`       | Zmiany w dokumentacji      | Brak wydania                    | `docs: aktualizacja instrukcji instalacji`                         |
| `styl`       | Zmiany stylu kodu          | Brak wydania                    | `style: formatuj kod za pomocą swiftformat`                        |
| `refaktoruj` | Refaktoryzacja kodu        | Brak wydania                    | `refactor(serwer): uprość logikę uwierzytelniania`                 |
| `perf`       | Poprawa wydajności         | Zmiana wersji poprawki          | `perf(cli): optymalizacja rozwiązywania zależności`                |
| `test`       | Dodaj/zmień testy          | Brak wydania                    | `test: dodaj testy jednostkowe dla pamięci podręcznej`             |
| `chore`      | Zadania konserwacyjne      | Brak wydania                    | `zadanie: aktualizacja zależności`                                 |
| `ci`         | Zmiany CI/CD               | Brak wydania                    | `ci: dodaj przepływ pracy dla wydań`                               |

#### Zmiany wprowadzające istotne modyfikacje

Zmiany powodujące niekompatybilność powodują znaczną zmianę wersji (X.0.0) i
powinny być zaznaczone w treści zatwierdzenia:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Wykrywanie zmian

Każdy komponent używa [git cliff](https://git-cliff.org/) do:
- Przeanalizuj zmiany wprowadzone od ostatniej wersji
- Filtruj commity według zakresu (cli, app, server)
- Określ, czy istnieją zmiany, które można wprowadzić.
- Automatycznie generuj dzienniki zmian

### 3. Uwolnij potok

W przypadku wykrycia zmian, które można opublikować:

1. **Obliczanie wersji**: Potok określa numer następnej wersji.
2. **Generowanie dziennika zmian**: git cliff tworzy dziennik zmian na podstawie
   komunikatów commit.
3. **Proces tworzenia**: Komponent jest tworzony i testowany.
4. **Tworzenie wydania**: Wydanie GitHub jest tworzone wraz z artefaktami.
5. **Dystrybucja**: Aktualizacje są przesyłane do menedżerów pakietów (np.
   Homebrew dla CLI).

### 4. Filtrowanie zakresu

Każdy komponent jest publikowany tylko wtedy, gdy zawiera istotne zmiany:

- **CLI**: Commits with `(cli)` scope or no scope
- **Aplikacja**: Commits z `(app)` scope
- **Serwer**: Commits z `(serwer)` zakres

## Pisanie dobrych komunikatów commit

Ponieważ komunikaty commit mają bezpośredni wpływ na informacje o wydaniu, ważne
jest, aby pisać jasne, opisowe komunikaty:

### Należy:
- Używaj czasu teraźniejszego: „dodaj funkcję”, a nie „dodana funkcja”.
- Bądź zwięzły, ale opisowy.
- W przypadku zmian dotyczących konkretnych komponentów należy podać zakres.
- Problemy referencyjne, jeśli mają zastosowanie: `fix(cli): rozwiązanie
  problemu z pamięcią podręczną kompilacji (#1234)`

### Nie należy:
- Używaj niejasnych komunikatów, takich jak „napraw błąd” lub „zaktualizuj kod”.
- Łącz wiele niepowiązanych zmian w jednym commitcie.
- Zapomnij o dodaniu informacji o zmianach wprowadzających przełomowe zmiany.

### Zmiany wprowadzające istotne modyfikacje

W przypadku zmian wprowadzających istotne modyfikacje dodaj w treści
zatwierdzenia komunikat „ `” (ISTOTNA ZMIANA) oraz link „` ”.

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Procesy wydawania

Procesy wydawania są zdefiniowane w:
- `.github/workflows/cli-release.yml` - Wersje CLI
- `.github/workflows/app-release.yml` - Wydania aplikacji
- `.github/workflows/server-release.yml` - Wersje serwera

Każdy proces:
- Działa po przesłaniu do głównego repozytorium.
- Można uruchomić ręcznie.
- Wykorzystuje git cliff do wykrywania zmian.
- Obsługuje cały proces wydawania

## Monitorowanie wydań

Możesz monitorować wydania poprzez:
- [Strona GitHub Releases](https://github.com/tuist/tuist/releases)
- Karta GitHub Actions dla uruchomień przepływu pracy
- Pliki dziennika zmian w każdym katalogu komponentów

## Korzyści

Takie podejście oparte na ciągłym wydawaniu nowych wersji zapewnia:

- **Szybka dostawa**: Zmiany są widoczne dla użytkowników natychmiast po
  scaleniu.
- **Zmniejszone wąskie gardła**: brak konieczności oczekiwania na ręczne
  zwolnienia
- **Jasna komunikacja**: Automatyczne dzienniki zmian z komunikatów commit.
- **Spójny proces**: Ten sam przebieg wydania dla wszystkich komponentów
- **Zapewnienie jakości**: Tylko przetestowane zmiany są publikowane.

## Rozwiązywanie problemów

Jeśli wydanie nie powiedzie się:

1. Sprawdź logi GitHub Actions pod kątem nieudanego przepływu pracy.
2. Upewnij się, że komunikaty commit są zgodne z konwencjonalnym formatem.
3. Sprawdź, czy wszystkie testy zakończyły się powodzeniem.
4. Sprawdź, czy komponent został pomyślnie skompilowany.

W przypadku pilnych poprawek, które wymagają natychmiastowego wydania:
1. Upewnij się, że Twoje zatwierdzenie ma jasny zakres.
2. Po scaleniu monitoruj proces wydawania.
3. W razie potrzeby uruchom ręczne zwolnienie.

## Wydanie w App Store

Podczas gdy CLI i serwer działają zgodnie z opisaną powyżej procedurą ciągłego
wydawania aktualizacji, aplikacja **na iOS** stanowi wyjątek ze względu na
proces weryfikacji Apple App Store:

- **Ręczne publikacje**: publikacje aplikacji na iOS wymagają ręcznego
  przesłania do App Store.
- **Opóźnienia w weryfikacji**: Każda wersja musi przejść proces weryfikacji
  Apple, który może trwać od 1 do 7 dni.
- **Zmiany zbiorcze**: W każdej wersji systemu iOS zazwyczaj wprowadza się wiele
  zmian jednocześnie.
- **TestFlight**: Wersje beta mogą być dystrybuowane za pośrednictwem TestFlight
  przed wydaniem w App Store.
- **Informacje o wydaniu**: Muszą być napisane zgodnie z wytycznymi App Store.

Aplikacja na iOS nadal stosuje te same konwencje dotyczące zatwierdzania zmian i
wykorzystuje git cliff do generowania dziennika zmian, ale faktyczne
udostępnianie użytkownikom odbywa się rzadziej, zgodnie z ręcznym harmonogramem.
