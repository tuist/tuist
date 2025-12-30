---
{
  "title": "QA",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "AI-powered testing agent that tests your iOS apps automatically with comprehensive QA coverage."
}
---
# QA {#qa}

::: warning EARLY PREVIEW
<!-- -->
Tuist QA jest obecnie we wczesnej wersji zapoznawczej. Zarejestruj się na
stronie [tuist.dev/qa](https://tuist.dev/qa), aby uzyskać dostęp.
<!-- -->
:::

Tworzenie wysokiej jakości aplikacji mobilnych opiera się na kompleksowym
testowaniu, ale tradycyjne podejścia mają swoje ograniczenia. Testy jednostkowe
są szybkie i opłacalne, ale pomijają rzeczywiste scenariusze użytkownika. Testy
akceptacyjne i ręczna kontrola jakości mogą wychwycić te luki, ale wymagają
dużych zasobów i nie skalują się dobrze.

Agent QA Tuist rozwiązuje to wyzwanie, symulując autentyczne zachowanie
użytkownika. Autonomicznie bada aplikację, rozpoznaje elementy interfejsu,
wykonuje realistyczne interakcje i sygnalizuje potencjalne problemy. Takie
podejście pomaga zidentyfikować błędy i problemy z użytecznością na wczesnym
etapie rozwoju, jednocześnie unikając kosztów i obciążeń związanych z
konwencjonalnymi testami akceptacyjnymi i QA.

## Wymagania wstępne {#prerequisites}

Aby rozpocząć korzystanie z Tuist QA, należy:
- Skonfiguruj przesyłanie
  <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink> z
  przepływu pracy PR CI, którego agent może następnie użyć do testowania.
- <LocalizedLink href="/guides/integrations/gitforge/github">Zintegruj</LocalizedLink>
  z GitHub, aby móc uruchomić agenta bezpośrednio z PR.

## Użycie {#usage}

Tuist QA jest obecnie uruchamiany bezpośrednio z PR. Po skojarzeniu podglądu z
PR można uruchomić agenta QA, komentując `/qa test Chcę przetestować funkcję A`
w PR:

![Komentarz wyzwalacza QA](/images/guides/features/qa/qa-trigger-comment.png)

Komentarz zawiera link do sesji na żywo, w której można zobaczyć w czasie
rzeczywistym postępy agenta QA i wszelkie znalezione przez niego błędy. Gdy
agent zakończy swoje działanie, opublikuje podsumowanie wyników z powrotem do
PR:

![Podsumowanie testu QA](/images/guides/features/qa/qa-test-summary.png)

W ramach raportu na pulpicie nawigacyjnym, do którego odsyła komentarz PR,
otrzymasz listę problemów i oś czasu, dzięki czemu możesz sprawdzić, jak
dokładnie doszło do problemu:

![Oś czasu QA](/images/guides/features/qa/qa-timeline.png)

Możesz zobaczyć wszystkie testy QA, które wykonujemy dla naszej
<LocalizedLink href="/guides/features/previews#tuist-ios-app"> aplikacji iOS</LocalizedLink> w naszym publicznym dashboardzie:
https://tuist.dev/tuist/tuist/qa.

:: info
<!-- -->
Agent QA działa autonomicznie i nie może zostać przerwany dodatkowymi monitami
po uruchomieniu. Zapewniamy szczegółowe dzienniki podczas wykonywania, aby pomóc
Ci zrozumieć, w jaki sposób agent wchodził w interakcję z Twoją aplikacją.
Dzienniki te są cenne dla iteracji kontekstu aplikacji i testowania monitów, aby
lepiej kierować zachowaniem agenta. Jeśli masz opinie na temat działania agenta
z Twoją aplikacją, daj nam znać za pośrednictwem [GitHub
Issues](https://github.com/tuist/tuist/issues), naszej [społeczności
Slack](https://slack.tuist.dev) lub naszego [forum
społeczności](https://community.tuist.dev).
<!-- -->
:::

### Kontekst aplikacji {#app-context}

Agent może potrzebować więcej kontekstu na temat aplikacji, aby móc dobrze się
po niej poruszać. Mamy trzy rodzaje kontekstu aplikacji:
- Opis aplikacji
- Poświadczenia
- Uruchamianie grup argumentów

Wszystkie z nich można skonfigurować w ustawieniach pulpitu nawigacyjnego
projektu (`Ustawienia` > `QA`).

#### Opis aplikacji {#app-description}

Opis aplikacji służy do zapewnienia dodatkowego kontekstu na temat tego, co robi
aplikacja i jak działa. Jest to długie pole tekstowe, które jest przekazywane
jako część monitu podczas uruchamiania agenta. Przykładem może być:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Poświadczenia {#credentials}

W przypadku, gdy agent musi zalogować się do aplikacji w celu przetestowania
niektórych funkcji, można podać mu dane uwierzytelniające. Agent wypełni te
poświadczenia, jeśli rozpozna, że musi się zalogować.

#### Uruchamianie grup argumentów {#launch-argument-groups}

Grupy argumentów uruchamiania są wybierane na podstawie monitu testowego przed
uruchomieniem agenta. Na przykład, jeśli nie chcesz, aby agent wielokrotnie się
logował, marnując tokeny i minuty runnera, możesz zamiast tego określić tutaj
swoje poświadczenia. Jeśli agent rozpozna, że powinien rozpocząć sesję
zalogowany, użyje grupy argumentów uruchomienia poświadczeń podczas uruchamiania
aplikacji.

![Uruchom grupy
argumentów](/images/guides/features/qa/launch-argument-groups.png)

Te argumenty uruchamiania są standardowymi argumentami uruchamiania Xcode. Oto
przykład, jak użyć ich do automatycznego logowania:

```swift
import ArgumentParser
import SwiftUI

@main
struct TuistApp: App {
    var body: some Scene {
        ContentView()
        #if DEBUG
            .task {
                await checkForAutomaticLogin()
            }
        #endif
    }
    /// When launch arguments with credentials are passed, such as when running QA tests, we can skip the log in and
    /// automatically log in
    private func checkForAutomaticLogin() async {
        struct LaunchArguments: ParsableArguments {
            @Option var email: String?
            @Option var password: String?
        }

        do {
            let parsedArguments = try LaunchArguments.parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))

            guard let email = parsedArguments.email,
                  let password = parsedArguments.password
            else {
                return
            }

            try await authenticationService.signInWithEmailAndPassword(email: email, password: password)
        } catch {
            // Skipping automatic log in
        }
    }
}
```
