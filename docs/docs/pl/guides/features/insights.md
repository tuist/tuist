---
{
  "title": "Build Insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Get insights into your builds to maintain a productive developer environment."
}
---
# Build Insights {#build-insights}

::: ostrzeżenie WYMAGANIA
<!-- -->
- Konto <LocalizedLink href="/guides/server/accounts-and-projects">Tuist i
  projekt</LocalizedLink>
<!-- -->
:::

Praca nad dużymi projektami nie powinna być uciążliwa. W rzeczywistości powinna
być tak samo przyjemna, jak praca nad projektem, który rozpocząłeś zaledwie dwa
tygodnie temu. Jednym z powodów, dla których tak nie jest, jest to, że wraz z
rozwojem projektu pogarsza się komfort pracy programistów. Czas kompilacji
wydłuża się, a testy stają się powolne i zawodne. Często łatwo jest przeoczyć te
problemy, dopóki nie osiągną one punktu, w którym stają się nie do zniesienia —
jednak w tym momencie trudno jest je rozwiązać. Tuist Insights zapewnia
narzędzia do monitorowania stanu projektu i utrzymania produktywnego środowiska
programistycznego w miarę jego rozwoju.

Innymi słowy, Tuist Insights pomaga odpowiedzieć na takie pytania, jak:
- Czy czas kompilacji znacznie wzrósł w ciągu ostatniego tygodnia?
- Czy moje kompilacje są wolniejsze na CI w porównaniu do rozwoju lokalnego?

Chociaż prawdopodobnie dysponujesz pewnymi wskaźnikami wydajności procesów CI,
możesz nie mieć takiego samego wglądu w lokalne środowisko programistyczne.
Jednak czas lokalnej kompilacji jest jednym z najważniejszych czynników
wpływających na komfort pracy programistów.

Aby rozpocząć śledzenie lokalnych czasów kompilacji, możesz skorzystać z
polecenia `tuist inspect build`, dodając je do akcji po zakończeniu schematu:

![Czynności po zakończeniu inspekcji
kompilacji](/images/guides/features/insights/inspect-build-scheme-post-action.png)

:: info
<!-- -->
Zalecamy ustawienie opcji „Provide build settings from” (Podaj ustawienia
kompilacji z) na plik wykonywalny lub główny cel kompilacji, aby umożliwić Tuist
śledzenie konfiguracji kompilacji.
<!-- -->
:::

:: info
<!-- -->
Jeśli nie używasz <LocalizedLink href="/guides/features/projects">wygenerowanych
projektów</LocalizedLink>, akcja po schemacie nie zostanie wykonana w przypadku
niepowodzenia kompilacji.
<!-- -->
:::
> 
> Nieudokumentowana funkcja w Xcode pozwala na wykonanie tego nawet w tym
> przypadku. Ustaw atrybut `runPostActionsOnFailure` na `YES` w schemacie
> `BuildAction` w odpowiednim `project.pbxproj` pliku w następujący sposób:
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


Twoje lokalne kompilacje są teraz śledzone, o ile jesteś zalogowany na swoje
konto Tuist. Możesz teraz uzyskać dostęp do czasów kompilacji w panelu Tuist i
zobaczyć, jak zmieniają się one w czasie:


::: napiwek
<!-- -->
Aby szybko uzyskać dostęp do pulpitu nawigacyjnego, uruchom `tuist project show
--web` z poziomu CLI.
<!-- -->
:::

![Pulpit nawigacyjny z informacjami o
kompilacji](/images/guides/features/insights/builds-dashboard.png)

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
> <LocalizedLink href="/references/project-description/structs/tuist.generationoptions#buildinsightsdisabled">buildInsightsDisabled</LocalizedLink>.

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
            runAction: .runAction(configuration: "Debug")
        )
    ]
)
```

Jeśli nie korzystasz z Mise, skrypty można uprościć do:

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
)
```

## Ciągła integracja {#continuous-integration}

Aby śledzić informacje o kompilacji w CI, należy upewnić się, że CI jest
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">uwierzytelniony</LocalizedLink>.

Dodatkowo należy:
- Użyj polecenia <LocalizedLink href="/cli/xcodebuild#tuist-xcodebuild">`tuist
  xcodebuild`</LocalizedLink> podczas wywoływania akcji `xcodebuild`.
- Dodaj `-resultBundlePath` do wywołania `xcodebuild`.

Gdy `xcodebuild` buduje projekt bez `-resultBundlePath`, wymagane pliki
dziennika aktywności i pakietu wyników nie są generowane. Funkcja `tuist inspect
build` post-action wymaga tych plików do analizy kompilacji.
