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
Tuist QA jest obecnie w fazie wczesnej wersji zapoznawczej. Zarejestruj się na
stronie [tuist.dev/qa](https://tuist.dev/qa), aby uzyskać dostęp.
<!-- -->
:::

Tworzenie wysokiej jakości aplikacji mobilnych opiera się na kompleksowych
testach, ale tradycyjne podejścia mają swoje ograniczenia. Testy jednostkowe są
szybkie i opłacalne, ale nie uwzględniają rzeczywistych scenariuszy użytkowania.
Testy akceptacyjne i ręczna kontrola jakości mogą wypełnić te luki, ale są one
zasobochłonne i nie skalują się dobrze.

Agent QA firmy Tuist rozwiązuje to wyzwanie poprzez symulację autentycznego
zachowania użytkownika. Samodzielnie eksploruje aplikację, rozpoznaje elementy
interfejsu, wykonuje realistyczne interakcje i sygnalizuje potencjalne problemy.
Takie podejście pomaga zidentyfikować błędy i problemy z użytecznością na
wczesnym etapie rozwoju, unikając jednocześnie nakładów i obciążenia związanego
z konserwacją wynikających z konwencjonalnych testów akceptacyjnych i testów
jakości.

## Wymagania wstępne {#prerequisites}

Aby rozpocząć korzystanie z Tuist QA, musisz:
- Skonfiguruj przesyłanie
  <LocalizedLink href="/guides/features/previews">podglądów</LocalizedLink> z
  przepływu pracy PR CI, które agent może następnie wykorzystać do testowania
- <LocalizedLink href="/guides/integrations/gitforge/github">Zintegruj
  </LocalizedLink> z GitHubem, aby móc uruchamiać agenta bezpośrednio z PR

## Użycie {#usage}

Tuist QA jest obecnie uruchamiany bezpośrednio z PR. Gdy masz już podgląd
powiązany z PR, możesz uruchomić agenta QA, dodając komentarz `/qa test Chcę
przetestować funkcję A` w PR:

![Komentarz wyzwalający QA](/images/guides/features/qa/qa-trigger-comment.png)

Komentarz zawiera link do sesji na żywo, gdzie można w czasie rzeczywistym
obserwować postępy agenta QA oraz wszelkie wykryte przez niego problemy. Gdy
agent zakończy działanie, opublikuje podsumowanie wyników z powrotem w PR:

![Podsumowanie testu QA](/images/guides/features/qa/qa-test-summary.png)

W ramach raportu w panelu, do którego prowadzi link w komentarzu PR, otrzymasz
listę problemów oraz oś czasu, dzięki czemu będziesz mógł sprawdzić, jak
dokładnie doszło do danego problemu:

![Oś czasu QA](/images/guides/features/qa/qa-timeline.png)

Wszystkie przebiegi kontroli jakości, które przeprowadzamy dla naszej
<LocalizedLink href="/guides/features/previews#tuist-ios-app">aplikacji na
iOS</LocalizedLink>, można zobaczyć na naszym publicznym pulpicie nawigacyjnym:
https://tuist.dev/tuist/tuist/qa

:: info
<!-- -->
Agent QA działa autonomicznie i po uruchomieniu nie można go przerwać
dodatkowymi poleceniami. Zapewniamy szczegółowe logi z całego procesu, które
pomogą Ci zrozumieć, jak agent współpracował z Twoją aplikacją. Logi te są
przydatne do iteracji kontekstu aplikacji i testowania poleceń, aby lepiej
kierować zachowaniem agenta. Jeśli masz uwagi na temat działania agenta w Twojej
aplikacji, daj nam znać przez [GitHub
Issues](https://github.com/tuist/tuist/issues), naszą [społeczność na
Slacku](https://slack.tuist.dev) lub nasze [forum
społeczności](https://community.tuist.dev).
<!-- -->
:::

### Kontekst aplikacji {#app-context}

Agent może potrzebować więcej informacji o Twojej aplikacji, aby móc się w niej
dobrze poruszać. Mamy trzy rodzaje informacji o aplikacji:
- Opis aplikacji
- Poświadczenia
- Grupy argumentów uruchamiania

Wszystkie te opcje można skonfigurować w ustawieniach pulpitu nawigacyjnego
projektu (`Settings` > `QA`).

#### Opis aplikacji {#app-description}

Opis aplikacji służy do przekazania dodatkowych informacji na temat tego, co
robi Twoja aplikacja i jak działa. Jest to długie pole tekstowe, które jest
przekazywane jako część monitu podczas uruchamiania agenta. Przykładem może być:

```
Tuist iOS app is an app that gives users easy access to previews, which are specific builds of apps. The app contains metadata about the previews, such as the version and build number, and allows users to run previews directly on their device.

The app additionally includes a profile tab to surface about information about the currently signed-in profile and includes capabilities like signing out.
```

#### Dane uwierzytelniające {#credentials}

Jeśli agent musi zalogować się do aplikacji, aby przetestować niektóre funkcje,
możesz podać mu dane logowania. Agent wprowadzi te dane, jeśli stwierdzi, że
konieczne jest zalogowanie się.

#### Uruchom grupy argumentów {#launch-argument-groups}

Grupy argumentów uruchamiania są wybierane na podstawie monitu testowego przed
uruchomieniem agenta. Na przykład, jeśli nie chcesz, aby agent wielokrotnie się
logował, marnując tokeny i minuty uruchomienia, możesz zamiast tego podać tutaj
swoje poświadczenia. Jeśli agent rozpozna, że powinien rozpocząć sesję po
zalogowaniu, użyje grupy argumentów uruchamiania z poświadczeniami podczas
uruchamiania aplikacji.

![Uruchom grupy
argumentów](/images/guides/features/qa/launch-argument-groups.png)

Te argumenty uruchamiania są standardowymi argumentami uruchamiania Xcode. Oto
przykład, jak używać ich do automatycznego logowania:

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
