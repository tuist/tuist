---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Struktura katalogów {#directory-structure}

Chociaż projekty Tuist są powszechnie używane do zastępowania projektów Xcode,
nie są one ograniczone do tego przypadku użycia. Projekty Tuist są również
wykorzystywane do generowania innych typów projektów, takich jak pakiety SPM,
szablony, wtyczki i zadania. Niniejszy dokument opisuje strukturę projektów
Tuist i sposób ich organizacji. W późniejszych sekcjach omówimy sposób
definiowania szablonów, wtyczek i zadań.

## Standardowe projekty Tuist {#standard-tuist-projects}

Projekty Tuist to **najpopularniejszy typ projektów generowanych przez Tuist.**
Są one wykorzystywane między innymi do tworzenia aplikacji, frameworków i
bibliotek. W przeciwieństwie do projektów Xcode, projekty Tuist są definiowane w
języku Swift, co czyni je bardziej elastycznymi i łatwiejszymi w utrzymaniu.
Projekty Tuist są również bardziej deklaratywne, co ułatwia ich zrozumienie i
wnioskowanie. Poniższa struktura przedstawia typowy projekt Tuist, który
generuje projekt Xcode:

```bash
Tuist.swift
Tuist/
  Package.swift
  ProjectDescriptionHelpers/
Projects/
  App/
    Project.swift
  Feature/
    Project.swift
Workspace.swift
```

- **Katalog Tuist:** Ten katalog ma dwa cele. Po pierwsze, sygnalizuje **, gdzie
  znajduje się korzeń projektu**. Umożliwia to konstruowanie ścieżek względem
  katalogu głównego projektu, a także uruchamianie poleceń Tuist z dowolnego
  katalogu w projekcie. Po drugie, jest to kontener dla następujących plików:
  - **ProjectDescriptionHelpers:** Ten katalog zawiera kod Swift, który jest
    współdzielony przez wszystkie pliki manifestu. Pliki manifestów mogą
    `importować ProjectDescriptionHelpers`, aby używać kodu zdefiniowanego w tym
    katalogu. Współdzielenie kodu jest przydatne, aby uniknąć powielania i
    zapewnić spójność między projektami.
  - **Package.swift:** Ten plik zawiera zależności pakietu Swift dla Tuist, aby
    zintegrować je za pomocą projektów Xcode i celów (takich jak
    [CocoaPods](https://cococapods)), które można konfigurować i optymalizować.
    Więcej <LocalizedLink href="/guides/features/projects/dependencies"> tutaj</LocalizedLink>.

- **Katalog główny**: Katalog główny projektu, który zawiera również katalog
  `Tuist`.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Ten plik zawiera konfigurację Tuist, która jest współdzielona przez
    wszystkie projekty, obszary robocze i środowiska. Można go na przykład użyć
    do wyłączenia automatycznego generowania schematów lub zdefiniowania celu
    wdrożenia projektów.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    Ten manifest reprezentuje obszar roboczy Xcode. Służy do grupowania innych
    projektów, a także może dodawać dodatkowe pliki i schematy.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    Ten manifest reprezentuje projekt Xcode. Służy do definiowania obiektów
    docelowych, które są częścią projektu i ich zależności.

Podczas interakcji z powyższym projektem, polecenia oczekują znalezienia pliku
`Workspace.swift` lub `Project.swift` w katalogu roboczym lub katalogu wskazanym
za pomocą flagi `--path`. Manifest powinien znajdować się w katalogu lub
podkatalogu katalogu zawierającego katalog `Tuist`, który reprezentuje korzeń
projektu.

::: napiwek
<!-- -->
Przestrzenie robocze Xcode umożliwiały dzielenie projektów na wiele projektów
Xcode w celu zmniejszenia prawdopodobieństwa wystąpienia konfliktów scalania.
Jeśli właśnie do tego używałeś obszarów roboczych, nie potrzebujesz ich w Tuist.
Tuist automatycznie generuje obszar roboczy zawierający projekt i projekty od
niego zależne.
<!-- -->
:::

## Pakiet Swift <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist obsługuje również projekty pakietów SPM. Jeśli pracujesz nad pakietem SPM,
nie musisz niczego aktualizować. Tuist automatycznie pobiera główny pakiet
`Package.swift` i wszystkie funkcje Tuist działają tak, jakby był to manifest
`Project.swift`.

Aby rozpocząć, uruchom `tuist install` i `tuist generate` w swoim pakiecie SPM.
Twój projekt powinien mieć teraz wszystkie te same schematy i pliki, które
widziałbyś w waniliowej integracji Xcode SPM. Jednak teraz możesz również
uruchomić <LocalizedLink href="/guides/features/cache">`tuist cache`</LocalizedLink> i mieć większość zależności i modułów SPM wstępnie
skompilowanych, dzięki czemu kolejne kompilacje będą niezwykle szybkie.
