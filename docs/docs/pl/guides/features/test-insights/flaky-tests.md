---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# Niesprawne testy {#flaky-tests}

::: ostrzeżenie WYMAGANIA
<!-- -->
- <LocalizedLink href="/guides/features/test-insights">Test
  Insights</LocalizedLink> musi być skonfigurowany.
<!-- -->
:::

Niespójne testy to testy, które dają różne wyniki (pozytywne lub negatywne) po
wielokrotnym uruchomieniu tego samego kodu. Podważają one zaufanie do zestawu
testów i powodują stratę czasu programistów na badanie fałszywych błędów. Tuist
automatycznie wykrywa niespójne testy i pomaga je śledzić w czasie.

![Strona Flaky
Tests](/images/guides/features/test-insights/flaky-tests-page.png)

## Jak działa wykrywanie niestabilności {#how-it-works}

Tuist wykrywa niestabilne testy na dwa sposoby:

### Ponowne próby testowe {#test-retries}

Podczas przeprowadzania testów z wykorzystaniem funkcji ponawiania prób w Xcode
(za pomocą polecenia `-retry-tests-on-failure` lub `-test-iterations`), Tuist
analizuje wyniki każdej próby. Jeśli test zakończy się niepowodzeniem w
niektórych próbach, ale zakończy się powodzeniem w innych, zostanie oznaczony
jako niestabilny.

Na przykład, jeśli test nie powiedzie się przy pierwszej próbie, ale powiedzie
się przy ponownej próbie, Tuist rejestruje to jako test niestabilny.

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -retry-tests-on-failure \
  -test-iterations 3
```

![Szczegóły niepewnego przypadku
testowego](/images/guides/features/test-insights/flaky-test-case-detail.png)

### Wykrywanie przekroczenia linii {#cross-run-detection}

Nawet bez ponawiania testów Tuist może wykrywać niestabilne testy, porównując
wyniki różnych przebiegów CI dla tego samego zatwierdzenia. Jeśli test zakończy
się powodzeniem w jednym przebiegu CI, ale zakończy się niepowodzeniem w innym
przebiegu dla tego samego zatwierdzenia, oba przebiegi zostaną oznaczone jako
niestabilne.

Jest to szczególnie przydatne w przypadku wykrywania niestabilnych testów, które
nie kończą się niepowodzeniem na tyle konsekwentnie, aby zostały wykryte przez
ponowne próby, ale nadal powodują sporadyczne awarie CI.

## Zarządzanie niestabilnymi testami {#managing-flaky-tests}

### Automatyczne czyszczenie

Tuist automatycznie usuwa flagę niestabilności z testów, które nie wykazywały
niestabilności przez 14 dni. Dzięki temu testy, które zostały naprawione, nie
pozostają oznaczone jako niestabilne przez czas nieokreślony.

### Zarządzanie ręczne

Możesz również ręcznie oznaczyć lub usunąć oznaczenie testów jako niestabilne na
stronie szczegółów przypadku testowego. Jest to przydatne, gdy:
- Chcesz potwierdzić znany niestabilny test podczas pracy nad poprawką.
- Test został nieprawidłowo oznaczony z powodu problemów infrastrukturalnych.

## Powiadomienia Slack {#slack-notifications}

Otrzymuj natychmiastowe powiadomienia, gdy test stanie się niestabilny,
konfigurując
<LocalizedLink href="/guides/integrations/slack#flaky-test-alerts">alerty o
niestabilnych testach</LocalizedLink> w integracji Slack.
