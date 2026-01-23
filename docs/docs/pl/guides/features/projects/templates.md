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
można generować pliki na podstawie szablonu. Można zdefiniować własne szablony
lub skorzystać z tych, które są dostarczane wraz z Tuist. Oto kilka scenariuszy,
w których szkielet może być przydatny:

- Utwórz nową funkcję zgodną z podaną architekturą: `tuist scaffold viper --name
  MyFeature`.
- Utwórz nowe projekty: `tuist scaffold feature-project --name Home`

::: info NON-OPINIONATED
<!-- -->
Tuist nie ma zdania na temat zawartości szablonów i tego, do czego są one
używane. Wymagane jest jedynie umieszczenie ich w określonym katalogu.
<!-- -->
:::

## Definiowanie szablonu {#defining-a-template}

Aby zdefiniować szablony, możesz uruchomić
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink>, a następnie utworzyć katalog o nazwie `nazwa_szablonu` w
`Tuist/Templates`, który reprezentuje Twój szablon. Szablony wymagają pliku
manifestu, `name_of_template.swift`, który opisuje szablon. Jeśli więc tworzysz
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

Po zdefiniowaniu szablonu możemy go użyć za pomocą polecenia `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

:: info
<!-- -->
Ponieważ platforma jest argumentem opcjonalnym, możemy również wywołać polecenie
bez argumentu `--platform macos`.
<!-- -->
:::

Jeśli `.string` i `.files` nie zapewniają wystarczającej elastyczności, możesz
skorzystać z języka szablonów [Stencil](https://stencil.fuller.li/en/latest/)
poprzez `.file`. Oprócz tego możesz również użyć dodatkowych filtrów
zdefiniowanych tutaj.

Korzystając z interpolacji ciągów znaków, `\(nameAttribute)` powyżej zostanie
zamienione na `{{ name }}`. Jeśli chcesz użyć filtrów Stencil w definicji
szablonu, możesz ręcznie zastosować tę interpolację i dodać dowolne filtry. Na
przykład, zamiast `\(nameAttribute)` możesz użyć `{ { name | lowercase } }`, aby
uzyskać wartość atrybutu name w małych literach.

Możesz również użyć `.directory`, co daje możliwość skopiowania całych folderów
do określonej ścieżki.

::: tip PROJECT DESCRIPTION HELPERS
<!-- -->
Szablony obsługują użycie
<LocalizedLink href="/guides/features/projects/code-sharing">pomocników opisu
projektu</LocalizedLink> w celu ponownego wykorzystania kodu w różnych
szablonach.
<!-- -->
:::
