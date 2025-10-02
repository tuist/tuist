---
{
  "title": "Migrate a Swift Package",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate from Swift Package Manager as a solution for managing your projects to Tuist projects."
}
---
# Migrar um pacote Swift {#migrate-a-swift-package}

O Gerenciador de Pacotes Swift surgiu como um gerenciador de dependências para o
código Swift que, involuntariamente, se viu resolvendo o problema de gerenciar
projetos e suportar outras linguagens de programação como Objective-C. Como a
ferramenta foi projetada com um propósito diferente em mente, pode ser um
desafio usá-la para gerenciar projetos em escala porque falta flexibilidade,
desempenho e poder que o Tuist fornece. Isso é bem capturado no artigo [Scaling
iOS at
Bumble](https://medium.com/bumble-tech/scaling-ios-at-bumble-239e0fa009f2), que
inclui a seguinte tabela comparando o desempenho do Swift Package Manager e
projetos nativos do Xcode:

<img style="max-width: 400px;" alt="A table that compares the regression in performance when using SPM over native Xcode projects" src="/images/guides/start/migrate/performance-table.webp">

Nós frequentemente encontramos desenvolvedores e organizações que desafiam a
necessidade do Tuist considerando que o Swift Package Manager pode ter um papel
similar de gerenciamento de projetos. Alguns aventuram-se numa migração para
mais tarde perceberem que a sua experiência de programador se degradou
significativamente. Por exemplo, a renomeação de um ficheiro pode demorar até 15
segundos a ser re-indexado. 15 segundos!

**Se a Apple vai fazer do Swift Package Manager um gerenciador de projetos
construído em escala é incerto.** No entanto, não estamos a ver quaisquer sinais
de que isso está a acontecer. De facto, estamos a ver o oposto. Eles estão
tomando decisões inspiradas no Xcode, como conseguir conveniência através de
configurações implícitas, que
<LocalizedLink href="/guides/features/projects/cost-of-convenience">como você
deve saber,</LocalizedLink> é a fonte de complicações em escala. Acreditamos que
seria necessário a Apple ir aos primeiros princípios e rever algumas decisões
que faziam sentido como gestor de dependências mas não como gestor de projectos,
por exemplo a utilização de uma linguagem compilada como interface para definir
projectos.

> [O Tuist trata o Swift Package Manager como um gerenciador de dependências, e
> é um ótimo gerenciador. Nós o usamos para resolver dependências e para
> construí-las. Nós não o usamos para definir projetos porque ele não foi
> projetado para isso.

## Migrando do Gerenciador de pacotes Swift para o Tuist {#migrating-from-swift-package-manager-to-tuist}

As similaridades entre o Swift Package Manager e o Tuist tornam o processo de
migração simples. A principal diferença é que você definirá seus projetos usando
a DSL do Tuist em vez de `Package.swift`.

Primeiro, crie um arquivo `Project.swift` ao lado do seu arquivo
`Package.swift`. O arquivo `Project.swift` conterá a definição do seu projeto.
Aqui está um exemplo de um arquivo `Project.swift` que define um projeto com um
único alvo:

```swift
import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["Sources/**/*.swift"]*
        ),
    ]
)
```

Alguns aspectos a ter em conta:

- **ProjectDescription**: Em vez de utilizar `PackageDescription`, utilizará
  `ProjectDescription`.
- **Projeto:** Em vez de exportar uma instância do pacote `` , exportará uma
  instância do projeto `` .
- **Linguagem do Xcode:** As primitivas que utiliza para definir o seu projeto
  imitam a linguagem do Xcode, pelo que encontrará esquemas, alvos e fases de
  construção, entre outros.

Em seguida, crie um ficheiro `Tuist.swift` com o seguinte conteúdo:

```swift
import ProjectDescription

let tuist = Tuist()
```

O arquivo `Tuist.swift` contém a configuração do seu projeto e seu caminho serve
como referência para determinar a raiz do seu projeto. Pode consultar o
documento
<LocalizedLink href="/guides/features/projects/directory-structure">diretory
structure</LocalizedLink> para saber mais sobre a estrutura dos projectos Tuist.

## Editar o projeto {#editar o projeto}

Pode utilizar <LocalizedLink href="/guides/features/projects/editing">`tuist
edit`</LocalizedLink> para editar o projeto no Xcode. O comando irá gerar um
projeto Xcode que pode abrir e começar a trabalhar nele.

```bash
tuist edit
```

Dependendo da dimensão do projeto, pode considerar utilizá-lo de uma só vez ou
de forma incremental. Recomendamos que comece com um pequeno projeto para se
familiarizar com a DSL e o fluxo de trabalho. O nosso conselho é começar sempre
pelo objetivo mais dependente e trabalhar até ao objetivo de nível superior.
