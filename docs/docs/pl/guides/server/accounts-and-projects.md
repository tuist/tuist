---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Konta i projekty {#accounts-and-projects}

Niektóre funkcje Tuist wymagają serwera, który dodaje trwałość danych i może
wchodzić w interakcje z innymi usługami. Do interakcji z serwerem potrzebne jest
konto i projekt, który łączy się z lokalnym projektem.

## Konta {#accounts}

Do korzystania z serwera potrzebne jest konto. Istnieją dwa rodzaje kont:

- **Konto osobiste:** Konta te są tworzone automatycznie podczas rejestracji i
  są identyfikowane przez uchwyt uzyskany od dostawcy tożsamości (np. GitHub)
  lub pierwszą część adresu e-mail.
- **Konto organizacji:** Te konta są tworzone ręcznie i są identyfikowane przez
  uchwyt zdefiniowany przez dewelopera. Organizacje umożliwiają zapraszanie
  innych członków do współpracy nad projektami.

Jeśli jesteś zaznajomiony z [GitHub](https://github.com), koncepcja jest podobna
do ich, gdzie możesz mieć konta osobiste i organizacyjne, a są one
identyfikowane przez uchwyt ** , który jest używany podczas konstruowania
adresów URL.

::: info CLI-FIRST
<!-- -->
Większość operacji związanych z zarządzaniem kontami i projektami odbywa się za
pośrednictwem interfejsu CLI. Pracujemy nad interfejsem webowym, który ułatwi
zarządzanie kontami i projektami.
<!-- -->
:::

Organizacją można zarządzać za pomocą poleceń podrzędnych w sekcji
<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>.
Aby utworzyć nowe konto organizacji, uruchom polecenie
```bash
tuist organization create {account-handle}
```

## Projekty {#projects}

Twoje projekty, zarówno Tuist, jak i surowy Xcode, muszą być zintegrowane z
Twoim kontem za pośrednictwem zdalnego projektu. Kontynuując porównanie z
GitHubem, jest to jak posiadanie lokalnego i zdalnego repozytorium, do którego
przesyłasz swoje zmiany. Możesz użyć <LocalizedLink href="/cli/project">`tuist project`</LocalizedLink> do tworzenia projektów i zarządzania nimi.

Projekty są identyfikowane przez pełny uchwyt, który jest wynikiem konkatenacji
uchwytu organizacji i uchwytu projektu. Na przykład, jeśli masz organizację z
uchwytem `tuist` i projekt z uchwytem `tuist`, pełny uchwyt to `tuist/tuist`.

Powiązanie między projektem lokalnym i zdalnym odbywa się za pośrednictwem pliku
konfiguracyjnego. Jeśli go nie masz, utwórz go na stronie `Tuist.swift` i dodaj
następującą treść:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
Należy pamiętać, że niektóre funkcje, takie jak
<LocalizedLink href="/guides/features/cache">binary caching</LocalizedLink>,
wymagają posiadania projektu Tuist. Jeśli korzystasz z nieprzetworzonych
projektów Xcode, nie będziesz mógł korzystać z tych funkcji.
<!-- -->
:::

Adres URL projektu jest tworzony przy użyciu pełnego uchwytu. Na przykład pulpit
nawigacyjny Tuist, który jest publiczny, jest dostępny pod adresem
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), gdzie `tuist/tuist` jest
pełnym uchwytem projektu.
