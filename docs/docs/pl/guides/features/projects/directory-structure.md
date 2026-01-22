---
{
  "title": "Directory structure",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the structure of Tuist projects and how to organize them."
}
---
# Struktura katalogów {#directory-structure}

Chociaż projekty Tuist są powszechnie używane do zastępowania projektów Xcode,
nie są one ograniczone do tego zastosowania. Projekty Tuist są również używane
do generowania innych typów projektów, takich jak pakiety SPM, szablony, wtyczki
i zadania. Niniejszy dokument opisuje strukturę projektów Tuist i sposób ich
organizowania. W kolejnych sekcjach omówimy sposób definiowania szablonów,
wtyczek i zadań.

## Standardowe projekty Tuist {#standard-tuist-projects}

Projekty Tuist są projektami typu „ **” (projektami typu „ ”) i są
najpopularniejszym typem projektów generowanych przez Tuist.** Są one używane
między innymi do tworzenia aplikacji, frameworków i bibliotek. W przeciwieństwie
do projektów Xcode, projekty Tuist są definiowane w języku Swift, co sprawia, że
są bardziej elastyczne i łatwiejsze w utrzymaniu. Projekty Tuist są również
bardziej deklaratywne, co sprawia, że są łatwiejsze do zrozumienia i analizy.
Poniższa struktura przedstawia typowy projekt Tuist, który generuje projekt
Xcode:

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

- **Katalog Tuist:** Katalog ten ma dwa cele. Po pierwsze, sygnalizuje **, gdzie
  katalogiem głównym projektu jest**. Umożliwia to tworzenie ścieżek względem
  katalogu głównego projektu, a także uruchamianie poleceń Tuist z dowolnego
  katalogu w ramach projektu. Po drugie, jest to kontener dla następujących
  plików:
  - **ProjectDescriptionHelpers:** Ten katalog zawiera kod Swift, który jest
    wspólny dla wszystkich plików manifestu. Pliki manifestu mogą `import
    ProjectDescriptionHelpers`, aby używać kodu zdefiniowanego w tym katalogu.
    Współdzielenie kodu jest przydatne, aby uniknąć powielania i zapewnić
    spójność między projektami.
  - **Package.swift:** Ten plik zawiera zależności pakietu Swift dla Tuist, aby
    zintegrować je za pomocą projektów i celów Xcode (takich jak
    [CocoaPods](https://cococapods)), które można konfigurować i optymalizować.
    Dowiedz się więcej
    <LocalizedLink href="/guides/features/projects/dependencies">tutaj</LocalizedLink>.

- **Katalog główny**: Katalog główny projektu, który zawiera również katalog
  `Tuist`.
  - <LocalizedLink href="/guides/features/projects/manifests#tuistswift"><bold>Tuist.swift:</bold></LocalizedLink>
    Ten plik zawiera konfigurację Tuist, która jest wspólna dla wszystkich
    projektów, obszarów roboczych i środowisk. Można go na przykład użyć do
    wyłączenia automatycznego generowania schematów lub do zdefiniowania celu
    wdrożenia projektów.
  - <LocalizedLink href="/guides/features/projects/manifests#workspace-swift"><bold>Workspace.swift:</bold></LocalizedLink>
    Ten manifest reprezentuje obszar roboczy Xcode. Służy do grupowania innych
    projektów, a także umożliwia dodawanie dodatkowych plików i schematów.
  - <LocalizedLink href="/guides/features/projects/manifests#project-swift"><bold>Project.swift:</bold></LocalizedLink>
    Ten manifest reprezentuje projekt Xcode. Służy do definiowania celów, które
    są częścią projektu, oraz ich zależności.

Podczas interakcji z powyższym projektem polecenia oczekują znalezienia pliku
`Workspace.swift` lub `Project.swift` w katalogu roboczym lub katalogu wskazanym
za pomocą flagi `--path`. Manifest powinien znajdować się w katalogu lub
podkatalogu katalogu zawierającego katalog `Tuist`, który reprezentuje katalog
główny projektu.

::: napiwek
<!-- -->
Obszary robocze Xcode umożliwiały dzielenie projektów na wiele projektów Xcode w
celu zmniejszenia prawdopodobieństwa konfliktów scalania. Jeśli właśnie do tego
służyły obszary robocze, nie są one potrzebne w Tuist. Tuist automatycznie
generuje obszar roboczy zawierający projekt i projekty zależne.
<!-- -->
:::

## Pakiet Swift <Badge type="warning" text="beta" /> {#swift-package-badge-typewarning-textbeta-}

Tuist obsługuje również projekty pakietów SPM. Jeśli pracujesz nad pakietem SPM,
nie powinieneś musieć niczego aktualizować. Tuist automatycznie pobiera plik
root `Package.swift`, a wszystkie funkcje Tuist działają tak, jakby był to plik
`Project.swift` manifest.

Aby rozpocząć, uruchom `tuist install` oraz `tuist generate` w pakiecie SPM.
Twój projekt powinien teraz zawierać wszystkie schematy i pliki, które można
znaleźć w podstawowej integracji Xcode SPM. Teraz możesz jednak również
uruchomić <LocalizedLink href="/guides/features/cache">`tuist
cache`</LocalizedLink> i skompilować większość zależności i modułów SPM, co
znacznie przyspieszy kolejne kompilacje.
