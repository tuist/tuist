---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Projekt Xcode {#xcode-project}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

Testy projektów Xcode można uruchamiać selektywnie z poziomu wiersza poleceń. W
tym celu można poprzedzić polecenie `xcodebuild` poleceniem `tuist` - na
przykład `tuist xcodebuild test -scheme App`. Polecenie haszuje projekt i po
powodzeniu utrwala hasze, aby określić, co zmieniło się w przyszłych
uruchomieniach.

W przyszłych uruchomieniach `tuist xcodebuild test` transparentnie używa hashy
do filtrowania testów, aby uruchomić tylko te, które zmieniły się od ostatniego
udanego uruchomienia testu.

Na przykład, zakładając następujący graf zależności:

- `FeatureA` ma testy `FeatureATests` i zależy od `Core`
- `FeatureB` ma testy `FeatureBTests` i zależy od `Core`
- `Core` ma testy `CoreTests`

`tuist xcodebuild test` będzie zachowywać się w ten sposób:

| Działanie                         | Opis                                                              | Stan wewnętrzny                                                            |
| --------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `tuist xcodebuild test` wywołanie | Uruchamia testy w `CoreTests`, `FeatureATests` i `FeatureBTests`  | Skróty `FeatureATests`, `FeatureBTests` i `CoreTests` są przechowywane.    |
| `FunkcjaA` jest aktualizowana     | Deweloper modyfikuje kod obiektu docelowego                       | Tak jak poprzednio                                                         |
| `tuist xcodebuild test` wywołanie | Uruchamia testy w `FeatureATests`, ponieważ zmienił się ich hash. | Nowy skrót `FeatureATests` jest przechowywany                              |
| `Rdzeń` jest aktualizowany        | Deweloper modyfikuje kod obiektu docelowego                       | Tak jak poprzednio                                                         |
| `tuist xcodebuild test` wywołanie | Uruchamia testy w `CoreTests`, `FeatureATests` i `FeatureBTests`  | Nowe skróty `FeatureATests` `FeatureBTests` i `CoreTests` są przechowywane |

Aby użyć `tuist xcodebuild test` w CI, postępuj zgodnie z instrukcjami w
<LocalizedLink href="/guides/integrations/continuous-integration">Przewodniku ciągłej integracji</LocalizedLink>.

Obejrzyj poniższy film, aby zobaczyć testy selektywne w akcji:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
