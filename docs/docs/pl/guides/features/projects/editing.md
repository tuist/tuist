---
{
  "title": "Editing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use Tuist's edit workflow to declare your project leveraging Xcode's build system and editor capabilities."
}
---
# Edycja {#editing}

W przeciwieństwie do tradycyjnych projektów Xcode lub pakietów Swift, w których
zmiany są wprowadzane za pośrednictwem interfejsu użytkownika Xcode, projekty
zarządzane przez Tuist są definiowane w kodzie Swift zawartym w plikach
manifestu **** . Jeśli znasz pakiety Swift i plik `Package.swift`, podejście
jest bardzo podobne.

Możesz edytować te pliki za pomocą dowolnego edytora tekstu, ale zalecamy
skorzystanie z przepływu pracy dostarczonego przez Tuist, `tuist edit`. Przepływ
pracy tworzy projekt Xcode, który zawiera wszystkie pliki manifestu i umożliwia
ich edycję oraz kompilację. Dzięki użyciu Xcode zyskujesz wszystkie zalety
**autouzupełniania kodu, podświetlania składni i sprawdzania błędów**.

## Edytuj projekt {#edit-the-project}

Aby edytować projekt, możesz uruchomić następujące polecenie w katalogu projektu
Tuist lub podkatalogu:

```bash
tuist edit
```

Polecenie tworzy projekt Xcode w katalogu globalnym i otwiera go w Xcode.
Projekt zawiera katalog `Manifests`, który można skompilować, aby upewnić się,
że wszystkie manifesty są prawidłowe.

::: info GLOB-RESOLVED MANIFESTS
<!-- -->
`tuist edit` rozwiązuje manifesty, które mają zostać dołączone, używając globu
`**/{Manifest}.swift` z katalogu głównego projektu (tego, który zawiera plik
`Tuist.swift` ). Upewnij się, że w katalogu głównym projektu znajduje się
prawidłowy plik `Tuist.swift`.
<!-- -->
:::

### Ignorowanie plików manifestu {#ignoring-manifest-files}

Jeśli projekt zawiera pliki Swift o tej samej nazwie co pliki manifestu (np.
`Project.swift`) w podkatalogach, które nie są rzeczywistymi manifestami Tuist,
można utworzyć plik `.tuistignore` w katalogu głównym projektu, aby wykluczyć je
z edytowanego projektu.

Plik `.tuistignore` wykorzystuje wzorce glob do określenia, które pliki powinny
zostać pominięte:

```gitignore
# Ignore all Project.swift files in the Sources directory
Sources/**/Project.swift

# Ignore specific subdirectories
Tests/Fixtures/**/Workspace.swift
```

Jest to szczególnie przydatne, gdy masz testowe fixtury lub przykładowy kod,
który używa tej samej konwencji nazewnictwa co pliki manifestu Tuist.

## Edytuj i generuj przepływ pracy {#edit-and-generate-workflow}

Jak zapewne zauważyłeś, edycji nie można wykonać z poziomu wygenerowanego
projektu Xcode. Jest to zamierzone działanie, które ma na celu zapobieżenie
uzależnieniu wygenerowanego projektu od Tuist, zapewniając możliwość przejścia z
Tuist w przyszłości przy minimalnym wysiłku.

Podczas iteracji projektu zalecamy uruchomienie polecenia `tuist edit` z sesji
terminala, aby uzyskać projekt Xcode do edycji, a następnie użycie innej sesji
terminala do uruchomienia polecenia `tuist generate`.
