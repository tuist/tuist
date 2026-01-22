---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# Testowanie wybiórcze {#selective-testing}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Projekt
  <LocalizedLink href="/guides/features/projects">wygenerowany</LocalizedLink>
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

Aby uruchomić testy selektywnie z wygenerowanym projektem, użyj polecenia `tuist
test`. Polecenie to
<LocalizedLink href="/guides/features/projects/hashing">haszuje</LocalizedLink>
projekt Xcode w taki sam sposób, jak
<LocalizedLink href="/guides/features/cache#cache-warming">rozgrzewanie pamięci
podręcznej</LocalizedLink>, a po pomyślnym zakończeniu zachowuje skróty, aby
określić, co uległo zmianie w przyszłych uruchomieniach.

W przyszłych uruchomieniach `tuist test` w przejrzysty sposób wykorzystuje znaki
hash do filtrowania testów, aby uruchamiać tylko te, które uległy zmianie od
ostatniego pomyślnego uruchomienia testów.

Na przykład, zakładając następujący wykres zależności:

- `Funkcja „` ” ma testy `Funkcja „ATests”` i zależy od `Core`
- `FunkcjaB` zawiera testy `FunkcjaBTesty` i zależy od `Core`
- `Core` zawiera testy `CoreTests`

`tuist test` będzie działać w następujący sposób:

| Działanie                             | Opis                                                                | Stan wewnętrzny                                                         |
| ------------------------------------- | ------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `tuist test` invocation               | Uruchamia testy w `CoreTests`, `FeatureATests` oraz `FeatureBTests` | Hashy `FeatureATests`, `FeatureBTests` i `CoreTests` są zachowywane.    |
| `Funkcja „` ” została zaktualizowana. | Programista modyfikuje kod docelowy.                                | Tak samo jak poprzednio.                                                |
| `tuist test` invocation               | Uruchamia testy w `FeatureATests`, ponieważ zmienił się hash.       | Nowy hash `FeatureATests` jest zachowywany.                             |
| `Zaktualizowano rdzeń`                | Programista modyfikuje kod docelowy.                                | Tak samo jak poprzednio.                                                |
| `tuist test` invocation               | Uruchamia testy w `CoreTests`, `FeatureATests` oraz `FeatureBTests` | Nowy hash `FeatureATests` `FeatureBTests` oraz `CoreTests` jest trwały. |

`tuist test` integruje się bezpośrednio z buforowaniem plików binarnych, aby
wykorzystać jak najwięcej plików binarnych z lokalnej lub zdalnej pamięci
masowej w celu skrócenia czasu kompilacji podczas uruchamiania zestawu testów.
Połączenie selektywnego testowania z buforowaniem plików binarnych może znacznie
skrócić czas potrzebny do przeprowadzenia testów w ramach ciągłej integracji.

## Testy interfejsu użytkownika {#ui-tests}

Tuist obsługuje selektywne testowanie interfejsu użytkownika. Jednak Tuist musi
znać miejsce docelowe z wyprzedzeniem. Tylko po określeniu miejsca docelowego ``
parametr, Tuist uruchomi testy interfejsu użytkownika selektywnie, na przykład:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
