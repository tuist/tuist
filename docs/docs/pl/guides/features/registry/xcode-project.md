---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Projekt Xcode {#xcode-project}

Aby dodać pakiety za pomocą rejestru w projekcie Xcode, należy użyć domyślnego
interfejsu użytkownika Xcode. Pakiety można wyszukiwać w rejestrze, klikając
przycisk `+` w zakładce `Package Dependencies` w Xcode. Jeśli pakiet jest
dostępny w rejestrze, w prawym górnym rogu zostanie wyświetlony rejestr
`tuist.dev`:

![Dodawanie zależności
pakietów](/images/guides/features/build/registry/registry-add-package.png)

:: info
<!-- -->
Xcode nie obsługuje obecnie automatycznego zastępowania pakietów kontroli źródła
ich odpowiednikami w rejestrze. Konieczne będzie ręczne usunięcie pakietu
kontroli źródła i dodanie pakietu rejestru, aby przyspieszyć rozwiązywanie.
<!-- -->
:::
