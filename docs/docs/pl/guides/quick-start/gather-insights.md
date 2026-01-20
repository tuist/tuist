---
{
  "title": "Gather insights",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to gather insights about your project."
}
---
# Zbieranie informacji {#gather-insights}

Tuist może integrować się z serwerem w celu rozszerzenia jego możliwości. Jedną
z tych możliwości jest gromadzenie informacji o projekcie i kompilacjach.
Wystarczy mieć konto z projektem na serwerze.

Przede wszystkim musisz się uwierzytelnić, uruchamiając aplikację:

```bash
tuist auth login
```

## Utwórz projekt {#create-a-project}

Następnie można utworzyć projekt, uruchamiając go:

```bash
tuist project create my-handle/MyApp

# Tuist project my-handle/MyApp was successfully created 🎉 {#tuist-project-myhandlemyapp-was-successfully-created-}
```

Skopiuj `my-handle/MyApp`, który reprezentuje pełny uchwyt projektu.

## Połącz projekty {#connect-projects}

Po utworzeniu projektu na serwerze należy połączyć go z projektem lokalnym.
Uruchom `tuist edit` i edytuj plik `tuist.swift`, aby zawierał pełny uchwyt
projektu:

```swift
import ProjectDescription

let tuist = Tuist(fullHandle: "my-handle/MyApp")
```

Voila! Jesteś teraz gotowy do zbierania informacji o swoim projekcie i
kompilacjach. Uruchom `tuist test`, aby uruchomić testy raportujące wyniki do
serwera.

:: info
<!-- -->
Tuist buforuje wyniki lokalnie i próbuje je wysłać bez blokowania polecenia. W
związku z tym wyniki mogą nie zostać wysłane natychmiast po zakończeniu
polecenia. W CI wyniki są wysyłane natychmiast.
<!-- -->
:::


![Obrazek przedstawiający listę uruchomień na
serwerze](/images/guides/quick-start/runs.png)

Posiadanie danych z projektów i kompilacji ma kluczowe znaczenie dla
podejmowania świadomych decyzji. Tuist będzie nadal rozszerzać swoje możliwości,
a Ty będziesz mógł z nich korzystać bez konieczności zmiany konfiguracji
projektu. Magia, prawda? 🪄
