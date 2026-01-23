---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Zbieraj spostrzeżenia {#gather-insights}

Tuist może zintegrować się z serwerem, aby rozszerzyć swoje możliwości. Jedną z
tych możliwości jest gromadzenie informacji o projekcie i kompilacjach.
Wystarczy mieć konto z projektem na serwerze.

Najpierw musisz się uwierzytelnić, uruchamiając:

```bash
tuist auth login
```

## Utwórz projekt {#create-a-project}

Następnie możesz utworzyć projekt, uruchamiając:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Skopiuj `my-handle/MyApp`, który reprezentuje pełny identyfikator projektu.

## Połącz projekty {#connect-projects}

Po utworzeniu projektu na serwerze należy połączyć go z lokalnym projektem.
Uruchom `tuist edit` i edytuj plik `Tuist.swift`, aby uwzględnić pełną nazwę
projektu:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Voilà! Teraz jesteś gotowy, aby zebrać informacje o swoim projekcie i
kompilacjach. Uruchom `tuist test`, aby uruchomić testy i przesłać wyniki do
serwera.

:: info
<!-- -->
Tuist umieszcza wyniki w kolejce lokalnej i próbuje je wysłać bez blokowania
polecenia. Dlatego mogą one nie zostać wysłane natychmiast po zakończeniu
polecenia. W CI wyniki są wysyłane natychmiast.
<!-- -->
:::


![Obraz przedstawiający listę uruchomień na
serwerze](/images/guides/quick-start/runs.png)

Dane z projektów i kompilacji mają kluczowe znaczenie dla podejmowania
świadomych decyzji. Tuist będzie nadal rozszerzać swoje możliwości, a Ty
będziesz mógł z nich korzystać bez konieczności zmiany konfiguracji projektu.
Magiczne, prawda? 🪄
