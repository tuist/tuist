---
{
  "title": "Accounts and projects",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to create and manage accounts and projects in Tuist."
}
---
# Konta i projekty {#accounts-and-projects}

Niektóre funkcje Tuist wymagają serwera, który zapewnia trwałość danych i może
współpracować z innymi usługami. Aby współpracować z serwerem, potrzebujesz
konta i projektu, który połączysz ze swoim lokalnym projektem.

## Konta {#accounts}

Aby korzystać z serwera, potrzebujesz konta. Istnieją dwa rodzaje kont:

- **Konto osobiste:** Konta te są tworzone automatycznie podczas rejestracji i
  identyfikowane za pomocą identyfikatora uzyskanego od dostawcy tożsamości (np.
  GitHub) lub pierwszej części adresu e-mail.
- **Konto organizacji:** Konta te są tworzone ręcznie i identyfikowane za pomocą
  identyfikatora zdefiniowanego przez programistę. Organizacje umożliwiają
  zapraszanie innych członków do współpracy nad projektami.

Jeśli znasz serwis [GitHub](https://github.com), koncepcja jest podobna do tej,
gdzie można mieć konta osobiste i organizacyjne, które są identyfikowane przez
identyfikator ** używany podczas tworzenia adresów URL.

::: info CLI-FIRST
<!-- -->
Większość operacji związanych z zarządzaniem kontami i projektami odbywa się za
pośrednictwem CLI. Pracujemy nad interfejsem internetowym, który ułatwi
zarządzanie kontami i projektami.
<!-- -->
:::

Organizacją można zarządzać za pomocą podkomend w
<LocalizedLink href="/cli/organization">`tuist organization`</LocalizedLink>.
Aby utworzyć nowe konto organizacji, uruchom:
```bash
tuist organization create {account-handle}
```

## Projekty {#projects}

Twoje projekty, zarówno Tuist, jak i surowe Xcode, muszą być zintegrowane z
Twoim kontem poprzez projekt zdalny. Kontynuując porównanie z GitHubem, jest to
jak posiadanie lokalnego i zdalnego repozytorium, do którego przesyłasz swoje
zmiany. Możesz użyć <LocalizedLink href="/cli/project">`tuist
project`</LocalizedLink>, aby tworzyć projekty i zarządzać nimi.

Projekty są identyfikowane za pomocą pełnego identyfikatora, który jest wynikiem
połączenia identyfikatora organizacji i identyfikatora projektu. Na przykład,
jeśli masz organizację o identyfikatorze `tuist` i projekt o identyfikatorze
`tuist`, pełny identyfikator będzie wyglądał następująco: `tuist/tuist`.

Powiązanie między projektem lokalnym a zdalnym odbywa się za pośrednictwem pliku
konfiguracyjnego. Jeśli nie masz takiego pliku, utwórz go w lokalizacji
`Tuist.swift` i dodaj następującą treść:

```swift
let tuist = Tuist(fullHandle: "{account-handle}/{project-handle}") // e.g. tuist/tuist
```

::: warning TUIST PROJECT-ONLY FEATURES
<!-- -->
Należy pamiętać, że niektóre funkcje, takie jak
<LocalizedLink href="/guides/features/cache">buforowanie
binarne</LocalizedLink>, wymagają posiadania projektu Tuist. Jeśli korzystasz z
surowych projektów Xcode, nie będziesz mógł korzystać z tych funkcji.
<!-- -->
:::

Adres URL projektu jest tworzony przy użyciu pełnego identyfikatora. Na przykład
publiczny pulpit nawigacyjny Tuist jest dostępny pod adresem
[tuist.dev/tuist/tuist](https://tuist.dev/tuist/tuist), gdzie `tuist/tuist` jest
pełnym identyfikatorem projektu.
