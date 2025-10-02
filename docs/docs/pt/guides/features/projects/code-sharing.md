---
{
  "title": "Code sharing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to share code across manifest files to reduce duplications and ensure consistency"
}
---
# Partilha de códigos {#partilha de códigos}

Um dos inconvenientes do Xcode quando o usamos com grandes projectos é que não
permite a reutilização de elementos dos projectos para além das definições de
compilação através dos ficheiros `.xcconfig`. Ser capaz de reutilizar definições
de projeto é útil pelas seguintes razões:

- Facilita a manutenção do **** porque as alterações podem ser aplicadas num
  único local e todos os projectos recebem as alterações automaticamente.
- Permite definir as convenções **** que os novos projectos podem respeitar.
- Os projectos são mais **consistentes** e, por conseguinte, a probabilidade de
  haver falhas de construção devido a inconsistências é significativamente
  menor.
- Adicionar novos projectos torna-se uma tarefa fácil porque podemos reutilizar
  a lógica existente.

A reutilização de código em ficheiros de manifesto é possível no Tuist graças ao
conceito de **ajudantes de descrição de projectos**.

> [Muitas organizações gostam do Tuist porque vêem nos auxiliares de descrição
> de projectos uma plataforma para as equipas da plataforma codificarem as suas
> próprias convenções e criarem a sua própria linguagem para descreverem os seus
> projectos. Por exemplo, os geradores de projectos baseados em YAML têm de
> criar a sua própria solução de modelos propietários baseados em YAML, ou
> forçar as organizações a construir as suas ferramentas.

## Ajudantes de descrição do projeto {#project-description-helpers}

Os auxiliares de descrição de projeto são arquivos Swift que são compilados em
um módulo, `ProjectDescriptionHelpers`, que os arquivos de manifesto podem
importar. O módulo é compilado reunindo todos os ficheiros no diretório
`Tuist/ProjectDescriptionHelpers`.

Pode importá-los para o seu ficheiro de manifesto adicionando uma declaração de
importação no topo do ficheiro:

```swift
// Project.swift
import ProjectDescription
import ProjectDescriptionHelpers
```

`ProjectDescriptionHelpers` estão disponíveis nos seguintes manifestos:
- `Projeto.swift`
- `Package.swift` (apenas por detrás da bandeira do compilador `#TUIST` )
- `Espaço de trabalho.swift`

## Exemplo {#exemplo}

Os snippets abaixo contêm um exemplo de como estendemos o modelo `Project` para
adicionar construtores estáticos e como os usamos a partir de um arquivo
`Project.swift`:

::: grupo de códigos
```swift [Tuist/Project+Templates.swift]
import ProjectDescription

extension Project {
  public static func featureFramework(name: String, dependencies: [TargetDependency] = []) -> Project {
    return Project(
        name: name,
        targets: [
            .target(
                name: name,
                destinations: .iOS,
                product: .framework,
                bundleId: "dev.tuist.\(name)",
                infoPlist: "\(name).plist",
                sources: ["Sources/\(name)/**"],
                resources: ["Resources/\(name)/**",],
                dependencies: dependencies
            ),
            .target(
                name: "\(name)Tests",
                destinations: .iOS,
                product: .unitTests,
                bundleId: "dev.tuist.\(name)Tests",
                infoPlist: "\(name)Tests.plist",
                sources: ["Sources/\(name)Tests/**"],
                resources: ["Resources/\(name)Tests/**",],
                dependencies: [.target(name: name)]
            )
        ]
    )
  }
}
```

```swift {2} [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project.featureFramework(name: "MyFeature")
```
:::

> [Uma ferramenta para estabelecer convenções Repare como, através da função,
> estamos a definir convenções sobre o nome dos alvos, o identificador do pacote
> e a estrutura das pastas.
