---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# Wygenerowane projekty {#generated-projects}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Projekt wygenerowany przez
  <LocalizedLink href="/guides/features/projects"></LocalizedLink>
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

Aby selektywnie uruchamiać testy w wygenerowanym projekcie, należy użyć
polecenia `tuist test`. Polecenie
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
projektu Xcode w taki sam sposób, jak w przypadku
<LocalizedLink href="/guides/features/cache#cache-warming">warming the cache</LocalizedLink>, a po powodzeniu utrwala hashe, aby określić, co zmieniło
się w przyszłych uruchomieniach.

W przyszłych uruchomieniach `tuist test` w przejrzysty sposób wykorzystuje
skróty do filtrowania testów, aby uruchomić tylko te, które zmieniły się od
ostatniego pomyślnego uruchomienia testu.

Na przykład, zakładając następujący graf zależności:

- `FeatureA` ma testy `FeatureATests` i zależy od `Core`
- `FeatureB` ma testy `FeatureBTests` i zależy od `Core`
- `Core` ma testy `CoreTests`

`tuistycznego testu` będzie zachowywać się w ten sposób:

| Działanie                     | Opis                                                              | Stan wewnętrzny                                                            |
| ----------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `tuist test` wywołanie        | Uruchamia testy w `CoreTests`, `FeatureATests` i `FeatureBTests`  | Skróty `FeatureATests`, `FeatureBTests` i `CoreTests` są przechowywane.    |
| `FunkcjaA` jest aktualizowana | Deweloper modyfikuje kod obiektu docelowego                       | Tak jak poprzednio                                                         |
| `tuist test` wywołanie        | Uruchamia testy w `FeatureATests`, ponieważ zmienił się ich hash. | Nowy skrót `FeatureATests` jest przechowywany                              |
| `Rdzeń` jest aktualizowany    | Deweloper modyfikuje kod obiektu docelowego                       | Tak jak poprzednio                                                         |
| `tuist test` wywołanie        | Uruchamia testy w `CoreTests`, `FeatureATests` i `FeatureBTests`  | Nowe skróty `FeatureATests` `FeatureBTests` i `CoreTests` są przechowywane |

`tuist test` integruje się bezpośrednio z buforowaniem binarnym, aby wykorzystać
jak najwięcej plików binarnych z lokalnej lub zdalnej pamięci masowej w celu
skrócenia czasu kompilacji podczas uruchamiania zestawu testów. Połączenie
testowania selektywnego z buforowaniem binarnym może znacznie skrócić czas
potrzebny na uruchomienie testów w CI.

## Testy interfejsu użytkownika {#ui-tests}

Tuist obsługuje selektywne testowanie testów interfejsu użytkownika. Tuist musi
jednak znać miejsce docelowe z wyprzedzeniem. Tylko po określeniu parametru
`destination`, Tuist uruchomi selektywnie testy interfejsu użytkownika, takie
jak:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
