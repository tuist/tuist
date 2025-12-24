---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Edycja {#editing}

W przeciwieństwie do tradycyjnych projektów Xcode lub pakietów Swift, w których
zmiany są dokonywane za pośrednictwem interfejsu użytkownika Xcode, projekty
zarządzane przez Tuist są definiowane w kodzie Swift zawartym w plikach
manifestu **** . Jeśli znasz pakiety Swift i plik `Package.swift`, podejście
jest bardzo podobne.

Pliki te można edytować za pomocą dowolnego edytora tekstu, ale zalecamy użycie
do tego celu przepływu pracy dostarczonego przez Tuist, `tuist edit`. Przepływ
pracy tworzy projekt Xcode, który zawiera wszystkie pliki manifestu i umożliwia
ich edycję i kompilację. Dzięki korzystaniu z Xcode można uzyskać wszystkie
korzyści płynące z uzupełniania kodu **, podświetlania składni i sprawdzania
błędów**.

## Edycja projektu {#edit-the-project}

Aby edytować projekt, można uruchomić następujące polecenie w katalogu lub
podkatalogu projektu Tuist:

```bash
tuist edit
```

Polecenie tworzy projekt Xcode w katalogu globalnym i otwiera go w Xcode.
Projekt zawiera katalog `Manifests`, który można skompilować, aby upewnić się,
że wszystkie manifesty są prawidłowe.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` rozwiązuje manifesty, które mają być dołączone przy użyciu globu
`**/{Manifest}.swift` z katalogu głównego projektu (zawierającego plik
`Tuist.swift` ). Upewnij się, że w katalogu głównym projektu znajduje się
poprawny plik `Tuist.swift`.
<!-- -->
:::

### Ignorowanie plików manifestu {#ignoring-manifest-files}

Jeśli projekt zawiera pliki Swift o tej samej nazwie co pliki manifestu (np.
`Project.swift`) w podkatalogach, które nie są rzeczywistymi manifestami Tuist,
można utworzyć plik `.tuistignore` w katalogu głównym projektu, aby wykluczyć je
z edycji projektu.

Plik `.tuistignore` wykorzystuje wzorce globalne do określenia, które pliki
powinny być ignorowane:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Jest to szczególnie przydatne, gdy masz poprawki testowe lub przykładowy kod,
który używa tej samej konwencji nazewnictwa co pliki manifestu Tuist.

## Edycja i generowanie przepływu pracy {#edit-and-generate-workflow}

Jak być może zauważyłeś, edycji nie można dokonać z poziomu wygenerowanego
projektu Xcode. Ma to na celu zapobieganie zależności wygenerowanego projektu od
Tuist, zapewniając możliwość przejścia z Tuist w przyszłości przy niewielkim
wysiłku.

Podczas iteracji projektu zalecamy uruchomienie `tuist edit` z sesji terminala,
aby uzyskać projekt Xcode do edycji projektu i użyć innej sesji terminala, aby
uruchomić `tuist generate`.
