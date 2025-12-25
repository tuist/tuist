---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Szablony {#templates}

W projektach o ustalonej architekturze programiści mogą chcieć uruchomić nowe
komponenty lub funkcje, które są spójne z projektem. Dzięki `tuist scaffold`
można generować pliki z szablonu. Możesz zdefiniować własne szablony lub użyć
tych, które są dostarczane z Tuist. Oto kilka scenariuszy, w których rusztowanie
może być przydatne:

- Utwórz nową funkcję o określonej architekturze: `tuist scaffold viper --name
  MyFeature`.
- Tworzenie nowych projektów: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist nie ma zdania na temat zawartości szablonów i tego, do czego ich używasz.
Wymagane jest jedynie, aby znajdowały się one w określonym katalogu.
<!-- -->
:::

## Definiowanie szablonu {#defining-a-template}

Aby zdefiniować szablony, można uruchomić
<LocalizedLink href="/guides/features/projects/editing">`tuist edit`</LocalizedLink>, a następnie utworzyć katalog o nazwie `name_of_template`
w `Tuist/Templates`, który reprezentuje szablon. Szablony wymagają pliku
manifestu, `name_of_template.swift` który opisuje szablon. Jeśli więc tworzysz
szablon o nazwie `framework`, powinieneś utworzyć nowy katalog `framework` w
`Tuist/Templates` z plikiem manifestu o nazwie `framework.swift`, który może
wyglądać następująco:


```swift
import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")

let template = Template(
    description: "Custom template",
    attributes: [
        nameAttribute,
        .optional("platform", default: "ios"),
    ],
    items: [
        .string(
            path: "Project.swift",
            contents: "My template contents of name \(nameAttribute)"
        ),
        .file(
            path: "generated/Up.swift",
            templatePath: "generate.stencil"
        ),
        .directory(
            path: "destinationFolder",
            sourcePath: "sourceFolder"
        ),
    ]
)
```

## Korzystanie z szablonu {#using-a-template}

Po zdefiniowaniu szablonu możemy go użyć z poziomu polecenia `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

:: info
<!-- -->
Ponieważ platforma jest opcjonalnym argumentem, możemy również wywołać polecenie
bez argumentu `--platform macos`.
<!-- -->
:::

Jeśli `.string` i `.files` nie zapewniają wystarczającej elastyczności, można
wykorzystać język szablonów [Stencil](https://stencil.fuller.li/en/latest/)
poprzez przypadek `.file`. Oprócz tego można również użyć dodatkowych filtrów
zdefiniowanych tutaj.

Używając interpolacji ciągów znaków, `\(nameAttribute)` powyżej zostałoby
rozwiązane jako `{{ name }}`. Jeśli chcesz użyć filtrów Stencil w definicji
szablonu, możesz użyć tej interpolacji ręcznie i dodać dowolne filtry. Na
przykład, można użyć `{ { nazwa | małe litery } }` zamiast `\(nameAttribute)`,
aby uzyskać wartość atrybutu name pisaną małymi literami.

Można również użyć `.directory`, który daje możliwość kopiowania całych folderów
do podanej ścieżki.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Szablony obsługują użycie
<LocalizedLink href="/guides/features/projects/code-sharing"> pomocników opisu projektu</LocalizedLink> w celu ponownego wykorzystania kodu między szablonami.
<!-- -->
:::
