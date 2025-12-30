---
{
  "title": "Get started",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Get started contributing to Tuist by following this guide."
}
---
# Rozpocznij {#get-started}

Jeśli masz doświadczenie w tworzeniu aplikacji na platformy Apple, takie jak
iOS, dodawanie kodu do Tuist nie powinno się zbytnio różnić. Istnieją dwie
różnice w porównaniu do tworzenia aplikacji, o których warto wspomnieć:

- **Interakcje z CLI odbywają się za pośrednictwem terminala.** Użytkownik
  wykonuje Tuist, który wykonuje żądane zadanie, a następnie powraca z
  powodzeniem lub z kodem statusu. Podczas wykonywania użytkownik może zostać
  powiadomiony poprzez wysłanie informacji wyjściowych na standardowe wyjście i
  standardowy błąd. Nie ma żadnych gestów ani interakcji graficznych, tylko
  intencje użytkownika.

- **Nie ma pętli uruchamiania, która utrzymuje proces przy życiu w oczekiwaniu
  na dane wejściowe**, jak ma to miejsce w aplikacji iOS, gdy aplikacja odbiera
  zdarzenia systemowe lub użytkownika. CLI działa w swoim procesie i kończy
  pracę po jej zakończeniu. Praca asynchroniczna może być wykonywana przy użyciu
  systemowych interfejsów API, takich jak
  [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue)
  lub [structured
  concurrency](https://developer.apple.com/tutorials/app-dev-training/managing-structured-concurrency),
  ale należy upewnić się, że proces jest uruchomiony podczas wykonywania pracy
  asynchronicznej. W przeciwnym razie proces zakończy pracę asynchroniczną.

Jeśli nie masz żadnego doświadczenia ze Swift, polecamy [oficjalną książkę
Apple](https://docs.swift.org/swift-book/), aby zapoznać się z językiem i
najczęściej używanymi elementami API Fundacji.

## Minimalne wymagania {#minimum-requirements}

Aby wnieść wkład do Tuist, minimalne wymagania to:

- macOS 14.0+
- Xcode 16.3+

## Skonfiguruj projekt lokalnie {#set-up-the-project-locally}

Aby rozpocząć pracę nad projektem, możemy wykonać poniższe kroki:

- Sklonuj repozytorium, uruchamiając: `git clone git@github.com:tuist/tuist.git`
- [Install](https://mise.jdx.dev/getting-started.html) Mise, aby udostępnić
  środowisko programistyczne.
- Uruchom `mise install`, aby zainstalować zależności systemowe wymagane przez
  Tuist
- Uruchom `tuist install`, aby zainstalować zewnętrzne zależności wymagane przez
  Tuist.
- (Opcjonalnie) Uruchom `tuist auth login`, aby uzyskać dostęp do
  <LocalizedLink href="/guides/features/cache"> Tuist Cache.</LocalizedLink>
- Uruchom `tuist generate`, aby wygenerować projekt Tuist Xcode przy użyciu
  samego Tuist

**Wygenerowany projekt otworzy się automatycznie**. Jeśli chcesz otworzyć go
ponownie bez generowania, uruchom `open Tuist.xcworkspace` (lub użyj Findera).

::: info XED .
<!-- -->
Próba otwarcia projektu za pomocą `xed .` spowoduje otwarcie pakietu, a nie
projektu wygenerowanego przez Tuist. Zalecamy korzystanie z projektu
wygenerowanego przez Tuist w celu przetestowania narzędzia.
<!-- -->
:::

## Edycja projektu {#edit-the-project}

Jeśli chcesz edytować projekt, na przykład w celu dodania zależności lub
dostosowania celów, możesz użyć polecenia
<LocalizedLink href="/guides/features/projects/editing">`tuist edit` </LocalizedLink>. Jest ono rzadko używane, ale warto wiedzieć, że istnieje.

## Run Tuist {#run-tuist}

### Z Xcode {#from-xcode}

Aby uruchomić `tuist` z wygenerowanego projektu Xcode, edytuj schemat `tuist` i
ustaw argumenty, które chcesz przekazać do polecenia. Na przykład, aby uruchomić
polecenie `tuist generate`, można ustawić argumenty na `generate --no-open`, aby
zapobiec otwarciu projektu po wygenerowaniu.

![Przykład konfiguracji schematu do uruchamiania polecenia generate z
Tuist](/images/contributors/scheme-arguments.png)

Będziesz także musiał ustawić katalog roboczy na katalog główny generowanego
projektu. Można to zrobić za pomocą argumentu `--path`, który akceptują
wszystkie polecenia, lub konfigurując katalog roboczy w schemacie, jak pokazano
poniżej:


![Przykład ustawienia katalogu roboczego do uruchomienia
Tuist](/images/contributors/scheme-working-directory.png)

::: warning PROJECTDESCRIPTION COMPILATION
<!-- -->
Interfejs CLI `tuist` zależy od obecności frameworka `ProjectDescription` w
katalogu zbudowanych produktów. Jeśli `tuist` nie uruchomi się, ponieważ nie
może znaleźć `ProjectDescription` framework, najpierw zbuduj `Tuist-Workspace`
scheme.
<!-- -->
:::

### Z terminala {#from-the-terminal}

Możesz uruchomić `tuist` używając samego Tuist poprzez polecenie `run`:

```bash
tuist run tuist generate --path /path/to/project --no-open
```

Alternatywnie można również uruchomić go bezpośrednio za pomocą Menedżera
pakietów Swift:

```bash
swift build --product ProjectDescription
swift run tuist generate --path /path/to/project --no-open
```
