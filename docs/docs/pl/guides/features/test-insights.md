---
{
  "title": "Test Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your tests to identify slow and flaky tests."
}
---
# Wgląd w testy {#test-insights}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

Informacje o testach pomagają monitorować stan zestawu testów poprzez
identyfikację powolnych testów lub szybkie zrozumienie nieudanych przebiegów CI.
Wraz z rozwojem zestawu testów coraz trudniej jest dostrzec trendy, takie jak
stopniowe spowolnienie testów lub sporadyczne awarie. Tuist Test Insights
zapewnia widoczność niezbędną do utrzymania szybkiego i niezawodnego zestawu
testów.

Dzięki Test Insights możesz odpowiedzieć na pytania takie jak:
- Czy moje testy stały się wolniejsze? Które z nich?
- Które testy są niestabilne i wymagają uwagi?
- Dlaczego moje CI nie zadziałało?

## Konfiguracja {#setup}

Aby rozpocząć śledzenie testów, możesz skorzystać z polecenia `tuist inspect
test`, dodając je do akcji po zakończeniu testu w schemacie:

![Czynności po zakończeniu testów
inspekcyjnych](/images/guides/features/insights/inspect-test-scheme-post-action.png)

W przypadku korzystania z [Mise](https://mise.jdx.dev/), skrypt będzie musiał
aktywować `tuist` w środowisku post-action:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
```

::: tip MISE & PROJECT PATHS
<!-- -->
Zmienna środowiskowa `PATH` nie jest dziedziczona przez akcję post schematu,
dlatego należy użyć bezwzględnej ścieżki Mise, która będzie zależeć od sposobu
instalacji Mise. Co więcej, nie zapomnij o odziedziczeniu ustawień kompilacji z
celu w projekcie, tak abyś mógł uruchomić Mise z katalogu wskazywanego przez
$SRCROOT.
<!-- -->
:::

Twoje testy są teraz śledzone, o ile jesteś zalogowany na swoje konto Tuist.
Możesz uzyskać dostęp do statystyk testów w panelu Tuist i zobaczyć, jak
zmieniają się one w czasie:

![Pulpit nawigacyjny z wynikami
testów](/images/guides/features/insights/tests-dashboard.png)

Oprócz ogólnych trendów można również zagłębić się w każdy test z osobna, na
przykład podczas debugowania błędów lub powolnych testów w CI:

![Szczegóły testu](/images/guides/features/insights/test-detail.png)

## Wygenerowane projekty {#generated-projects}

:: info
<!-- -->
Automatycznie wygenerowane schematy automatycznie zawierają `tuist inspect
build` postaction.
<!-- -->
:::
> 
> Jeśli nie jesteś zainteresowany śledzeniem wniosków w automatycznie
> generowanych schematach, wyłącz je za pomocą opcji generowania
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

Jeśli korzystasz z wygenerowanych projektów z niestandardowymi schematami,
możesz skonfigurować post-akcje dla wglądu w kompilację:

```swift
let project = Project(
    name: "MyProject",
    targets: [
        // Your targets
    ],
    schemes: [
        .scheme(
            name: "MyApp",
            shared: true,
            buildAction: .buildAction(targets: ["MyApp"]),
            testAction: .testAction(
                targets: ["MyAppTests"],
                postActions: [
                    // Test insights: Track test duration and flakiness
                    .executionAction(
                        title: "Inspect Test",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect test
                        """,
                        target: "MyAppTests"
                    )
                ]
            ),
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Jeśli nie korzystasz z Mise, skrypty można uprościć do:

```swift
testAction: .testAction(
    targets: ["MyAppTests"],
    postActions: [
        .executionAction(
            title: "Inspect Test",
            scriptText: "tuist inspect test"
        )
    ]
)
```

## Ciągła integracja {#continuous-integration}

Aby śledzić informacje o kompilacji w CI, należy upewnić się, że CI jest
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>.

Dodatkowo należy:
- Użyj polecenia <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> podczas wywoływania akcji `xcodebuild`.
- Dodaj `-resultBundlePath` do wywołania `xcodebuild`.

Gdy `xcodebuild` testuje projekt bez `-resultBundlePath`, wymagane pliki pakietu
wyników nie są generowane. `tuist inspect test` post-action wymaga tych plików
do analizy testów.
