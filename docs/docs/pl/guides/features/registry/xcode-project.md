---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Registry · Features · Guides · Tuist",
  "description": "Learn how to use the Tuist Registry in an Xcode project."
}
---
# Projekt Xcode {#xcode-project}

Aby dodać pakiety przy użyciu rejestru w projekcie Xcode, użyj domyślnego
interfejsu użytkownika Xcode. Możesz wyszukiwać pakiety w rejestrze, klikając
przycisk „ ` ” (Dodaj pakiet) + „` ” (Dodaj pakiet) w zakładce „ `” (Dodaj
pakiet) „Package Dependencies” (Zależności pakietów) „` ” (Dodaj pakiet) w
Xcode. Jeśli pakiet jest dostępny w rejestrze, w prawym górnym rogu pojawi się
komunikat „ `” (Dodaj pakiet) „tuist.dev” „` ” (Rejestr).

![Dodawanie zależności
pakietu](/images/guides/features/build/registry/registry-add-package.png)

:: info
<!-- -->
Xcode obecnie nie obsługuje automatycznego zastępowania pakietów kontroli źródła
ich odpowiednikami w rejestrze. Aby przyspieszyć rozwiązanie problemu, należy
ręcznie usunąć pakiet kontroli źródła i dodać pakiet rejestru.
<!-- -->
:::
