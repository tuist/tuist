---
{
  "title": "Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your projects to maintain a product developer environment."
}
---
# Spostrzeżenia {#insights}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto i projekt <LocalizedLink href="/guides/server/accounts-and-projects"> Tuist</LocalizedLink>
<!-- -->
:::

Praca nad dużymi projektami nie powinna być przykrym obowiązkiem. W
rzeczywistości powinna być tak przyjemna, jak praca nad projektem rozpoczętym
zaledwie dwa tygodnie temu. Jednym z powodów, dla których tak nie jest, jest to,
że wraz z rozwojem projektu cierpi na tym doświadczenie programisty. Czasy
kompilacji wydłużają się, a testy stają się powolne i zawodne. Często łatwo jest
przeoczyć te kwestie, dopóki nie dojdzie do punktu, w którym stają się nie do
zniesienia - jednak w tym momencie trudno jest się nimi zająć. Tuist Insights
zapewnia narzędzia do monitorowania kondycji projektu i utrzymania produktywnego
środowiska programistycznego w miarę skalowania projektu.

Innymi słowy, Tuist Insights pomaga odpowiedzieć na pytania takie jak:
- Czy czas kompilacji znacznie się wydłużył w ciągu ostatniego tygodnia?
- Czy moje testy stały się wolniejsze? Które z nich?

:: info
<!-- -->
Tuist Insights jest na wczesnym etapie rozwoju.
<!-- -->
:::

## Budynki {#builds}

Chociaż prawdopodobnie masz pewne dane dotyczące wydajności przepływów pracy CI,
możesz nie mieć takiego samego wglądu w lokalne środowisko programistyczne.
Czasy kompilacji lokalnych są jednak jednym z najważniejszych czynników
wpływających na wrażenia deweloperów.

Aby rozpocząć śledzenie lokalnego czasu kompilacji, można wykorzystać polecenie
`tuist inspect build`, dodając je do postakcji schematu:

![Działanie po inspekcji
kompilacji](/images/guides/features/insights/inspect-build-scheme-post-action.png)

:: info
<!-- -->
Zalecamy ustawienie opcji "Provide build settings from" na plik wykonywalny lub
główny cel kompilacji, aby umożliwić Tuist śledzenie konfiguracji kompilacji.
<!-- -->
:::

:: info
<!-- -->
Jeśli nie używasz <LocalizedLink href="/guides/features/projects"> wygenerowanych projektów</LocalizedLink>, akcja po schemacie nie zostanie
wykonana w przypadku niepowodzenia kompilacji.
<!-- -->
:::
> 
> Nieudokumentowana funkcja w Xcode pozwala na wykonanie go nawet w tym
> przypadku. Ustaw atrybut `runPostActionsOnFailure` na `YES` w schemacie
> `BuildAction` w odpowiednim pliku `project.pbxproj` w następujący sposób:
> 
> ```diff
> <BuildAction
>    buildImplicitDependencies="YES"
>    parallelizeBuildables="YES"
> +  runPostActionsOnFailure="YES">
> ```

W przypadku korzystania z [Mise](https://mise.jdx.dev/), skrypt będzie musiał
aktywować `tuist` w środowisku post-action:
```sh
# -C ensures that Mise loads the configuration from the Mise configuration
# file in the project's root directory.
$HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
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


Lokalne kompilacje są teraz śledzone tak długo, jak długo jesteś zalogowany na
swoje konto Tuist. Możesz teraz uzyskać dostęp do czasów kompilacji na pulpicie
nawigacyjnym Tuist i zobaczyć, jak zmieniają się one w czasie:


::: napiwek
<!-- -->
Aby szybko uzyskać dostęp do pulpitu nawigacyjnego, uruchom `tuist project show
--web` z CLI.
<!-- -->
:::

![Pulpit nawigacyjny z informacjami o
kompilacji](/images/guides/features/insights/builds-dashboard.png)

## Testy {#tests}

Oprócz śledzenia kompilacji można również monitorować testy. Wgląd w testy
pomaga zidentyfikować powolne testy lub szybko zrozumieć nieudane uruchomienia
CI.

Aby rozpocząć śledzenie testów, można wykorzystać polecenie `tuist inspect
test`, dodając je do testowej post-akcji schematu:

![Działanie po inspekcji
testów](/images/guides/features/insights/inspect-test-scheme-post-action.png)

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

Twoje testy są teraz śledzone tak długo, jak długo jesteś zalogowany na swoje
konto Tuist. Możesz uzyskać dostęp do swoich spostrzeżeń z testów na pulpicie
nawigacyjnym Tuist i zobaczyć, jak ewoluują one w czasie:

![Pulpit nawigacyjny z wnioskami z
testów](/images/guides/features/insights/tests-dashboard.png)

Oprócz ogólnych trendów, można również zagłębić się w poszczególne testy, na
przykład podczas debugowania awarii lub powolnych testów w CI:

![Szczegóły testu](/images/guides/features/insights/test-detail.png)

## Wygenerowane projekty {#generated-projects}

:: info
<!-- -->
Automatycznie wygenerowane schematy automatycznie zawierają zarówno `tuist
inspect build` jak i `tuist inspect test` post-actions.
<!-- -->
:::
> 
> Jeśli nie jesteś zainteresowany śledzeniem wniosków w automatycznie
> generowanych schematach, wyłącz je za pomocą opcji generowania
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>
> i
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#testinsightsdisabled">testInsightsDisabled</LocalizedLink>.

Jeśli korzystasz z wygenerowanych projektów z niestandardowymi schematami,
możesz skonfigurować post-akcje zarówno dla wglądów kompilacji, jak i testów:

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
            buildAction: .buildAction(
                targets: ["MyApp"],
                postActions: [
                    // Build insights: Track build times and performance
                    .executionAction(
                        title: "Inspect Build",
                        scriptText: """
                        $HOME/.local/bin/mise x -C $SRCROOT -- tuist inspect build
                        """,
                        target: "MyApp"
                    )
                ],
                // Run build post-actions even if the build fails
                runPostActionsOnFailure: true
            ),
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

Jeśli nie używasz Mise, twoje skrypty można uprościć do:

```swift
buildAction: .buildAction(
    targets: ["MyApp"],
    postActions: [
        .executionAction(
            title: "Inspect Build",
            scriptText: "tuist inspect build",
            target: "MyApp"
        )
    ],
    runPostActionsOnFailure: true
),
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

Aby śledzić wgląd w kompilacje i testy w CI, należy upewnić się, że CI jest
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>.

Dodatkowo będziesz musiał
- Użyj polecenia <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist xcodebuild`</LocalizedLink> podczas wywoływania akcji `xcodebuild`.
- Dodaj `-resultBundlePath` do wywołania `xcodebuild`.

Gdy `xcodebuild` buduje lub testuje projekt bez `-resultBundlePath`, wymagane
pliki dziennika aktywności i pakietu wyników nie są generowane. Zarówno `tuist
inspect build` jak i `tuist inspect test` postactions wymagają tych plików do
analizy kompilacji i testów.
