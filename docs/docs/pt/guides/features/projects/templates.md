---
{
  "title": "Templates",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to create and use templates in Tuist to generate code in your projects."
}
---
# Modelos {#templates}

Em projectos com uma arquitetura estabelecida, os programadores podem querer
criar novos componentes ou funcionalidades que sejam consistentes com o projeto.
Com `tuist scaffold` é possível gerar ficheiros a partir de um modelo. Pode
definir os seus próprios modelos ou utilizar os que são fornecidos com o Tuist.
Estes são alguns cenários onde o scaffolding pode ser útil:

- Criar uma nova funcionalidade que siga uma determinada arquitetura: `tuist
  scaffold viper --name MyFeature`.
- Criar novos projectos: `tuist scaffold feature-project --name Home`

> [NOTA] NÃO OPINIONADO O Tuist não tem opinião sobre o conteúdo dos seus
> modelos e sobre a utilização que lhes dá. Só é necessário que estejam num
> diretório específico.

## Definição de um modelo {#defining-a-template}

Para definir modelos, pode executar
<LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> e, em seguida, criar um diretório chamado
`name_of_template` em `Tuist/Templates` que representa o seu modelo. Os modelos
precisam de um ficheiro de manifesto, `name_of_template.swift` que descreve o
modelo. Portanto, se você estiver criando um modelo chamado `framework`, você
deve criar um novo diretório `framework` em `Tuist/Templates` com um arquivo de
manifesto chamado `framework.swift` que pode ter a seguinte aparência:


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

## Utilizar um modelo {#utilizar um modelo}

Depois de definir o modelo, podemos utilizá-lo a partir do comando `scaffold`:

```bash
tuist scaffold name_of_template --name Name --platform macos
```

> [!NOTE] Como a plataforma é um argumento opcional, também podemos chamar o
> comando sem o argumento `--platform macos`.

Se `.string` e `.files` não proporcionarem flexibilidade suficiente, pode
utilizar a linguagem de criação de modelos
[Stencil](https://stencil.fuller.li/en/latest/) através do caso `.file`. Para
além disso, também pode utilizar filtros adicionais definidos aqui.

Utilizando a interpolação de cadeia de caracteres, `\(nameAttribute)` acima
resolveria para `{{ name }}`. Se pretender utilizar filtros Stencil na definição
do modelo, pode utilizar essa interpolação manualmente e adicionar os filtros
que pretender. Por exemplo, pode utilizar `{ { nome | minúsculas } }` em vez de
`\(nameAttribute)` para obter o valor em minúsculas do atributo name.

Também pode utilizar `.diretory` que dá a possibilidade de copiar pastas
inteiras para um determinado caminho.

> [Os modelos suportam a utilização de
> <LocalizedLink href="/guides/features/projects/code-sharing">ajudantes de
> descrição de projectos</LocalizedLink> para reutilizar código entre modelos.
